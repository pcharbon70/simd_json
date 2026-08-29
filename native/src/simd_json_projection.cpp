#include "../include/simd_json_abi.h"
#include "../vendor/simdjson/simdjson.h"

/* covers: simd_json.projection_engine.prefix_sharing_plan simd_json.projection_engine.private_abi_v2 simd_json.projection_engine.exception_and_failure_cleanup simd_json.native_build_and_abi.opaque_c_contract simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.partial_failure_cleanup */

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <utility>
#include <vector>

#ifdef SIMD_JSON_TESTING
#include "../test/include/simd_json_test_hooks.h"

#include <atomic>
#include <stdexcept>
#endif

namespace {

constexpr simd_json_status make_status(
    simd_json_status_code code,
    int32_t native_code = SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
    uint64_t byte_offset = SIMD_JSON_BYTE_OFFSET_UNAVAILABLE,
    uint32_t output_slot = SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE) noexcept {
  return {code, native_code, byte_offset, output_slot, UINT32_C(0)};
}

constexpr bool exceeds_size_t(uint64_t value) noexcept {
  if constexpr (sizeof(size_t) >= sizeof(uint64_t)) {
    (void)value;
    return false;
  } else {
    return value > std::numeric_limits<size_t>::max();
  }
}

#ifdef SIMD_JSON_TESTING
std::atomic<uint64_t> live_projection_plans{0};
std::atomic<uint64_t> live_projection_nodes{0};
std::atomic<uint64_t> live_projection_key_bytes{0};
std::atomic<uint64_t> projection_failure_after{UINT64_MAX};
std::atomic<int32_t> projection_failure_kind{0};

void projection_checkpoint() {
  int32_t kind = projection_failure_kind.load(std::memory_order_acquire);

  if (kind == 0) {
    return;
  }

  uint64_t remaining =
      projection_failure_after.load(std::memory_order_acquire);

  while (remaining != 0) {
    if (projection_failure_after.compare_exchange_weak(
            remaining, remaining - 1, std::memory_order_acq_rel,
            std::memory_order_acquire)) {
      return;
    }
  }

  if (!projection_failure_kind.compare_exchange_strong(
          kind, 0, std::memory_order_acq_rel, std::memory_order_acquire)) {
    return;
  }

  projection_failure_after.store(UINT64_MAX, std::memory_order_release);

  switch (kind) {
    case SIMD_JSON_TEST_FAILURE_SIMDJSON:
      throw simdjson::simdjson_error(simdjson::TAPE_ERROR);
    case SIMD_JSON_TEST_FAILURE_BAD_ALLOC:
      throw std::bad_alloc{};
    case SIMD_JSON_TEST_FAILURE_STANDARD:
      throw std::runtime_error{"simd_json_projection_standard_exception"};
    case SIMD_JSON_TEST_FAILURE_UNKNOWN:
      throw 1;
    default:
      return;
  }
}

void account_plan_created() noexcept {
  live_projection_plans.fetch_add(1, std::memory_order_acq_rel);
}

void account_plan_destroyed() noexcept {
  live_projection_plans.fetch_sub(1, std::memory_order_acq_rel);
}

void account_node_created() noexcept {
  live_projection_nodes.fetch_add(1, std::memory_order_acq_rel);
}

void account_node_destroyed() noexcept {
  live_projection_nodes.fetch_sub(1, std::memory_order_acq_rel);
}

void account_key_created(uint64_t length) noexcept {
  live_projection_key_bytes.fetch_add(length, std::memory_order_acq_rel);
}

void account_key_destroyed(uint64_t length) noexcept {
  live_projection_key_bytes.fetch_sub(length, std::memory_order_acq_rel);
}
#else
void projection_checkpoint() {}
void account_plan_created() noexcept {}
void account_plan_destroyed() noexcept {}
void account_node_created() noexcept {}
void account_node_destroyed() noexcept {}
void account_key_created(uint64_t) noexcept {}
void account_key_destroyed(uint64_t) noexcept {}
#endif

class owned_key {
 public:
  owned_key(const uint8_t *data, size_t length)
      : bytes_(length == 0
                   ? std::string{}
                   : std::string{reinterpret_cast<const char *>(data), length}),
        accounted_length_(static_cast<uint64_t>(length)) {
    account_key_created(accounted_length_);
  }

  owned_key(const owned_key &) = delete;
  owned_key &operator=(const owned_key &) = delete;

  owned_key(owned_key &&other) noexcept
      : bytes_(std::move(other.bytes_)),
        accounted_length_(other.accounted_length_) {
    other.accounted_length_ = 0;
  }

  owned_key &operator=(owned_key &&other) noexcept {
    if (this != &other) {
      account_key_destroyed(accounted_length_);
      bytes_ = std::move(other.bytes_);
      accounted_length_ = other.accounted_length_;
      other.accounted_length_ = 0;
    }
    return *this;
  }

  ~owned_key() { account_key_destroyed(accounted_length_); }

  const std::string &bytes() const noexcept { return bytes_; }

 private:
  std::string bytes_;
  uint64_t accounted_length_;
};

struct projection_node;

struct object_edge {
  owned_key key;
  projection_node *child;

  object_edge(owned_key &&owned, projection_node *node)
      : key(std::move(owned)), child(node) {}

  object_edge(object_edge &&) noexcept = default;
  object_edge &operator=(object_edge &&) noexcept = default;
  object_edge(const object_edge &) = delete;
  object_edge &operator=(const object_edge &) = delete;
};

struct array_edge {
  uint64_t index;
  projection_node *child;

  array_edge(uint64_t value, projection_node *node) : index(value), child(node) {}

  array_edge(array_edge &&) noexcept = default;
  array_edge &operator=(array_edge &&) noexcept = default;
  array_edge(const array_edge &) = delete;
  array_edge &operator=(const array_edge &) = delete;
};

struct projection_node {
  uint64_t id;
  std::vector<object_edge> object_edges;
  std::vector<array_edge> array_edges;
  std::vector<uint32_t> terminal_slots;

  explicit projection_node(uint64_t node_id) : id(node_id) {
    account_node_created();
  }
  ~projection_node() { account_node_destroyed(); }
  projection_node(const projection_node &) = delete;
  projection_node &operator=(const projection_node &) = delete;
};

bool byte_less(const std::string &left,
               const uint8_t *right,
               size_t right_length) noexcept {
  const size_t shared = std::min(left.size(), right_length);

  for (size_t index = 0; index < shared; ++index) {
    const uint8_t left_byte = static_cast<uint8_t>(left[index]);
    if (left_byte != right[index]) {
      return left_byte < right[index];
    }
  }

  return left.size() < right_length;
}

bool byte_equal(const std::string &left,
                const uint8_t *right,
                size_t right_length) noexcept {
  if (left.size() != right_length) {
    return false;
  }

  for (size_t index = 0; index < right_length; ++index) {
    if (static_cast<uint8_t>(left[index]) != right[index]) {
      return false;
    }
  }

  return true;
}

uint64_t hash_byte(uint64_t hash, uint8_t byte) noexcept {
  return (hash ^ byte) * UINT64_C(1099511628211);
}

uint64_t hash_u64(uint64_t hash, uint64_t value) noexcept {
  for (uint32_t shift = 0; shift < 64; shift += 8) {
    hash = hash_byte(hash, static_cast<uint8_t>(value >> shift));
  }
  return hash;
}

bool descriptor_set_is_valid(const simd_json_projection_entry *entries,
                             uint64_t entry_count,
                             const simd_json_projection_segment *segments,
                             uint64_t segment_count,
                             const uint8_t *key_bytes,
                             uint64_t key_bytes_length) noexcept {
  if (entry_count == 0 || segment_count == 0 || entries == nullptr ||
      segments == nullptr || entry_count > UINT32_MAX ||
      segment_count > UINT32_MAX ||
      exceeds_size_t(entry_count) || exceeds_size_t(segment_count) ||
      exceeds_size_t(key_bytes_length) ||
      (key_bytes_length != 0 && key_bytes == nullptr)) {
    return false;
  }

  for (uint64_t entry_index = 0; entry_index < entry_count; ++entry_index) {
    const simd_json_projection_entry &entry = entries[entry_index];

    if (entry.reserved != 0 || entry.output_slot >= entry_count ||
        entry.segment_count == 0 || entry.segment_offset > segment_count ||
        entry.segment_count > segment_count - entry.segment_offset) {
      return false;
    }

    for (uint64_t previous = 0; previous < entry_index; ++previous) {
      if (entries[previous].output_slot == entry.output_slot) {
        return false;
      }
    }
  }

  for (uint64_t segment_index = 0; segment_index < segment_count;
       ++segment_index) {
    const simd_json_projection_segment &segment = segments[segment_index];

    if (segment.reserved != 0) {
      return false;
    }

    if (segment.tag == SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY) {
      if (segment.array_index != 0 || segment.key_offset > key_bytes_length ||
          segment.key_length > key_bytes_length - segment.key_offset) {
        return false;
      }
    } else if (segment.tag == SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX) {
      if (segment.key_offset != 0 || segment.key_length != 0) {
        return false;
      }
    } else {
      return false;
    }

    bool referenced = false;
    for (uint64_t entry_index = 0; entry_index < entry_count; ++entry_index) {
      const simd_json_projection_entry &entry = entries[entry_index];
      if (segment_index >= entry.segment_offset &&
          segment_index - entry.segment_offset < entry.segment_count) {
        referenced = true;
        break;
      }
    }
    if (!referenced) {
      return false;
    }
  }

  return true;
}

simd_json_status status_from_current_exception() noexcept {
  try {
    throw;
  } catch (const simdjson::simdjson_error &error) {
    return make_status(SIMD_JSON_STATUS_INVALID_JSON,
                       static_cast<int32_t>(error.error()));
  } catch (const std::bad_alloc &) {
    return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY);
  } catch (const std::exception &) {
    return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  } catch (...) {
    return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  }
}

}  // namespace

struct simd_json_projection_plan {
  std::vector<std::unique_ptr<projection_node>> owned_nodes;
  projection_node *root = nullptr;
  uint64_t output_slots = 0;
  uint64_t nodes = 0;
  uint64_t object_edges = 0;
  uint64_t array_edges = 0;
  uint64_t terminals = 0;
  uint64_t key_bytes = 0;
  uint64_t maximum_depth = 0;
  uint64_t topology_hash = 0;

  simd_json_projection_plan() { account_plan_created(); }
  ~simd_json_projection_plan() {
    release_owned_nodes();
    account_plan_destroyed();
  }
  simd_json_projection_plan(const simd_json_projection_plan &) = delete;
  simd_json_projection_plan &operator=(const simd_json_projection_plan &) =
      delete;

 private:
  void release_owned_nodes() noexcept {
    root = nullptr;
    while (!owned_nodes.empty()) {
      owned_nodes.pop_back();
    }
  }
};

namespace {

projection_node *create_node(simd_json_projection_plan &plan) {
  projection_checkpoint();
  auto node = std::make_unique<projection_node>(plan.nodes);
  projection_node *node_pointer = node.get();
  projection_checkpoint();
  plan.owned_nodes.emplace_back(std::move(node));
  ++plan.nodes;
  return node_pointer;
}

projection_node *object_child(simd_json_projection_plan &plan,
                              projection_node &node,
                              const uint8_t *key,
                              size_t key_length) {
  auto position = std::lower_bound(
      node.object_edges.begin(), node.object_edges.end(), key,
      [key_length](const object_edge &edge, const uint8_t *candidate) {
        return byte_less(edge.key.bytes(), candidate, key_length);
      });

  if (position != node.object_edges.end() &&
      byte_equal(position->key.bytes(), key, key_length)) {
    return position->child;
  }

  projection_checkpoint();
  owned_key copied_key{key, key_length};
  projection_node *child_pointer = create_node(plan);
  projection_checkpoint();
  node.object_edges.emplace(position, std::move(copied_key), child_pointer);
  ++plan.object_edges;
  plan.key_bytes += static_cast<uint64_t>(key_length);
  return child_pointer;
}

projection_node *array_child(simd_json_projection_plan &plan,
                             projection_node &node,
                             uint64_t index) {
  auto position = std::lower_bound(
      node.array_edges.begin(), node.array_edges.end(), index,
      [](const array_edge &edge, uint64_t candidate) {
        return edge.index < candidate;
      });

  if (position != node.array_edges.end() && position->index == index) {
    return position->child;
  }

  projection_node *child_pointer = create_node(plan);
  projection_checkpoint();
  node.array_edges.emplace(position, index, child_pointer);
  ++plan.array_edges;
  return child_pointer;
}

void add_terminal(simd_json_projection_plan &plan,
                  projection_node &node,
                  uint32_t output_slot) {
  const auto position = std::lower_bound(node.terminal_slots.begin(),
                                         node.terminal_slots.end(), output_slot);
  projection_checkpoint();
  node.terminal_slots.emplace(position, output_slot);
  ++plan.terminals;
}

void insert_entry(simd_json_projection_plan &plan,
                  const simd_json_projection_entry &entry,
                  const simd_json_projection_segment *segments,
                  const uint8_t *key_bytes) {
  projection_node *node = plan.root;

  for (uint64_t path_index = 0; path_index < entry.segment_count;
       ++path_index) {
    const simd_json_projection_segment &segment =
        segments[entry.segment_offset + path_index];

    if (segment.tag == SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY) {
      const uint8_t *key = segment.key_length == 0
                               ? reinterpret_cast<const uint8_t *>("")
                               : key_bytes + segment.key_offset;
      node = object_child(plan, *node, key,
                          static_cast<size_t>(segment.key_length));
    } else {
      node = array_child(plan, *node, segment.array_index);
    }

    plan.maximum_depth = std::max(plan.maximum_depth, path_index + 1);
  }

  add_terminal(plan, *node, entry.output_slot);
}

uint64_t retained_topology_hash(
    const simd_json_projection_plan &plan) noexcept {
  uint64_t hash = UINT64_C(14695981039346656037);

  for (const std::unique_ptr<projection_node> &owned_node : plan.owned_nodes) {
    const projection_node &node = *owned_node;
    hash = hash_byte(hash, UINT8_C(0xa1));
    hash = hash_u64(hash, node.id);
    hash = hash_u64(hash, static_cast<uint64_t>(node.terminal_slots.size()));
    for (uint32_t slot : node.terminal_slots) {
      hash = hash_u64(hash, slot);
    }

    hash = hash_u64(hash, static_cast<uint64_t>(node.object_edges.size()));
    for (const object_edge &edge : node.object_edges) {
      hash = hash_byte(hash, UINT8_C(0xb1));
      hash = hash_u64(hash, static_cast<uint64_t>(edge.key.bytes().size()));
      for (char byte : edge.key.bytes()) {
        hash = hash_byte(hash, static_cast<uint8_t>(byte));
      }
      hash = hash_u64(hash, edge.child->id);
    }

    hash = hash_u64(hash, static_cast<uint64_t>(node.array_edges.size()));
    for (const array_edge &edge : node.array_edges) {
      hash = hash_byte(hash, UINT8_C(0xc1));
      hash = hash_u64(hash, edge.index);
      hash = hash_u64(hash, edge.child->id);
    }
  }

  return hash;
}

}  // namespace

extern "C" simd_json_status simd_json_projection_plan_create(
    const simd_json_projection_entry *entries,
    uint64_t entry_count,
    const simd_json_projection_segment *segments,
    uint64_t segment_count,
    const uint8_t *key_bytes,
    uint64_t key_bytes_length,
    simd_json_projection_plan **out_plan) noexcept {
  if (out_plan == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  *out_plan = nullptr;

  if (!descriptor_set_is_valid(entries, entry_count, segments, segment_count,
                               key_bytes, key_bytes_length)) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  try {
    projection_checkpoint();
    auto plan = std::make_unique<simd_json_projection_plan>();
    plan->root = create_node(*plan);
    plan->output_slots = entry_count;

    for (uint64_t output_slot = 0; output_slot < entry_count; ++output_slot) {
      for (uint64_t entry_index = 0; entry_index < entry_count; ++entry_index) {
        if (entries[entry_index].output_slot == output_slot) {
          insert_entry(*plan, entries[entry_index], segments, key_bytes);
          break;
        }
      }
    }

    plan->topology_hash = retained_topology_hash(*plan);
    *out_plan = plan.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    return status_from_current_exception();
  }
}

extern "C" void simd_json_projection_plan_destroy(
    simd_json_projection_plan *plan) noexcept {
  try {
    delete plan;
  } catch (...) {
  }
}

extern "C" simd_json_status simd_json_projection_execute(
    simd_json_document *document,
    const simd_json_projection_plan *plan,
    simd_json_result_slot *result_slots,
    uint64_t result_slot_count) noexcept {
  if (document == nullptr || plan == nullptr || result_slots == nullptr ||
      result_slot_count != plan->output_slots || exceeds_size_t(result_slot_count)) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  /* Phase 3 replaces this bounded placeholder with the guided traversal. */
  return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
}

#ifdef SIMD_JSON_TESTING
extern "C" void simd_json_test_projection_inject_failure(
    uint64_t successful_checkpoints, int32_t kind) noexcept {
  try {
    projection_failure_after.store(successful_checkpoints,
                                   std::memory_order_release);
    projection_failure_kind.store(kind, std::memory_order_release);
  } catch (...) {
    projection_failure_kind.store(0, std::memory_order_release);
    projection_failure_after.store(UINT64_MAX, std::memory_order_release);
  }
}

extern "C" void simd_json_test_projection_clear_failure(void) noexcept {
  try {
    projection_failure_kind.store(0, std::memory_order_release);
    projection_failure_after.store(UINT64_MAX, std::memory_order_release);
  } catch (...) {
  }
}

extern "C" simd_json_test_projection_accounting
simd_json_test_projection_accounting_snapshot(void) noexcept {
  try {
    return {
        live_projection_plans.load(std::memory_order_acquire),
        live_projection_nodes.load(std::memory_order_acquire),
        live_projection_key_bytes.load(std::memory_order_acquire),
    };
  } catch (...) {
    return {UINT64_MAX, UINT64_MAX, UINT64_MAX};
  }
}

extern "C" uint32_t simd_json_test_projection_summary_read(
    const simd_json_projection_plan *plan,
    simd_json_test_projection_summary *out_summary) noexcept {
  if (plan == nullptr || out_summary == nullptr) {
    return UINT32_C(0);
  }

  try {
    *out_summary = {
        plan->output_slots, plan->nodes,         plan->object_edges,
        plan->array_edges, plan->terminals,     plan->key_bytes,
        plan->maximum_depth, plan->topology_hash,
    };
    return UINT32_C(1);
  } catch (...) {
    return UINT32_C(0);
  }
}
#endif
