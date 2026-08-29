#include "../include/simd_json_abi.h"
#include "../vendor/simdjson/simdjson.h"
#include "simd_json_native_internal.hpp"

/* covers: simd_json.projection_engine.prefix_sharing_plan simd_json.projection_engine.declaration_order_independence simd_json.projection_engine.single_guided_traversal simd_json.projection_engine.complete_source_validation simd_json.projection_engine.duplicate_json_key_policy simd_json.projection_engine.scalar_only_materialization simd_json.projection_engine.typed_result_slots simd_json.projection_engine.transactional_conversion simd_json.projection_engine.private_abi_v2 simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_engine.internal_phase_timing simd_json.native_build_and_abi.opaque_c_contract simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.partial_failure_cleanup */

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#ifdef SIMD_JSON_TESTING
#include "../test/include/simd_json_test_hooks.h"

#include <atomic>
#include <chrono>
#include <stdexcept>
#endif

namespace {

constexpr simd_json_projection_status make_status(
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
  uint64_t execution_id;

  object_edge(owned_key &&owned, projection_node *node, uint64_t edge_id)
      : key(std::move(owned)), child(node), execution_id(edge_id) {}

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
  uint64_t subtree_output_slots = 0;
  uint32_t first_output_slot = SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE;

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

simd_json_projection_status status_from_current_exception() noexcept {
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
  uint64_t shared_prefix_nodes = 0;

#ifdef SIMD_JSON_TESTING
  uint64_t compilation_nanoseconds = 0;
  mutable std::atomic<uint64_t> execution_entries{0};
  mutable std::atomic<uint64_t> last_traversal_nanoseconds{0};
  mutable std::atomic<uint64_t> last_visited_nodes{0};
  mutable std::atomic<uint64_t> last_shared_prefix_visits{0};
  mutable std::atomic<uint64_t> last_filled_slots{0};
  mutable std::atomic<uint64_t> last_object_fields{0};
  mutable std::atomic<uint64_t> last_array_elements{0};
  mutable std::atomic<uint64_t> last_skipped_values{0};
  mutable std::atomic<uint64_t> last_cancellation_checks{0};
#endif

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
  node.object_edges.emplace(position, std::move(copied_key), child_pointer,
                            plan.object_edges);
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

void finalize_plan_metadata(simd_json_projection_plan &plan) noexcept {
  plan.shared_prefix_nodes = 0;

  for (auto position = plan.owned_nodes.rbegin();
       position != plan.owned_nodes.rend(); ++position) {
    projection_node &node = **position;
    node.subtree_output_slots =
        static_cast<uint64_t>(node.terminal_slots.size());
    node.first_output_slot = node.terminal_slots.empty()
                                 ? SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE
                                 : node.terminal_slots.front();

    const auto include_child = [&node](const projection_node *child) noexcept {
      node.subtree_output_slots += child->subtree_output_slots;
      node.first_output_slot =
          std::min(node.first_output_slot, child->first_output_slot);
    };

    for (const object_edge &edge : node.object_edges) {
      include_child(edge.child);
    }
    for (const array_edge &edge : node.array_edges) {
      include_child(edge.child);
    }

    if (node.subtree_output_slots > 1) {
      ++plan.shared_prefix_nodes;
    }
  }
}

void saturating_increment(uint64_t &value) noexcept {
  if (value != UINT64_MAX) {
    ++value;
  }
}

bool valid_json_number_syntax(std::string_view token) noexcept {
  size_t start = 0;
  size_t end = token.size();
  const auto whitespace = [](char byte) noexcept {
    return byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n';
  };
  while (start < end && whitespace(token[start])) {
    ++start;
  }
  while (end > start && whitespace(token[end - 1])) {
    --end;
  }
  if (start == end) {
    return false;
  }

  size_t position = start;
  if (token[position] == '-') {
    ++position;
    if (position == end) {
      return false;
    }
  }

  if (token[position] == '0') {
    ++position;
  } else if (token[position] >= '1' && token[position] <= '9') {
    do {
      ++position;
    } while (position < end && token[position] >= '0' &&
             token[position] <= '9');
  } else {
    return false;
  }

  if (position < end && token[position] == '.') {
    ++position;
    const size_t fraction_start = position;
    while (position < end && token[position] >= '0' &&
           token[position] <= '9') {
      ++position;
    }
    if (position == fraction_start) {
      return false;
    }
  }

  if (position < end &&
      (token[position] == 'e' || token[position] == 'E')) {
    ++position;
    if (position < end &&
        (token[position] == '+' || token[position] == '-')) {
      ++position;
    }
    const size_t exponent_start = position;
    while (position < end && token[position] >= '0' &&
           token[position] <= '9') {
      ++position;
    }
    if (position == exponent_start) {
      return false;
    }
  }

  return position == end;
}

struct traversal_counters {
  uint64_t visited_nodes = 0;
  uint64_t shared_prefix_visits = 0;
  uint64_t filled_slots = 0;
  uint64_t object_fields = 0;
  uint64_t array_elements = 0;
  uint64_t skipped_values = 0;
  uint64_t cancellation_checks = 0;
};

struct traversal_context {
  simd_json_document *opaque_document;
  simdjson::ondemand::document &document;
  const uint8_t *data;
  uint64_t logical_length;
  simd_json_result_slot *result_slots;
  std::vector<uint8_t> &satisfied_object_edges;
  simd_json_projection_status pending_path_failure =
      make_status(SIMD_JSON_STATUS_OK);
  traversal_counters &counters;
};

uint64_t current_byte_offset(const traversal_context &context) noexcept {
  const char *location = nullptr;
  if (context.document.current_location().get(location) != simdjson::SUCCESS ||
      location == nullptr || context.data == nullptr) {
    return SIMD_JSON_BYTE_OFFSET_UNAVAILABLE;
  }

  const uintptr_t start = reinterpret_cast<uintptr_t>(context.data);
  const uintptr_t current = reinterpret_cast<uintptr_t>(location);
  if (current < start || current - start > context.logical_length) {
    return SIMD_JSON_BYTE_OFFSET_UNAVAILABLE;
  }

  return static_cast<uint64_t>(current - start);
}

simd_json_projection_status status_from_simdjson(
    simdjson::error_code error,
    const traversal_context &context,
    uint32_t output_slot = SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE) noexcept {
  simd_json_status_code code = SIMD_JSON_STATUS_INVALID_JSON;

  switch (error) {
    case simdjson::SUCCESS:
      return make_status(SIMD_JSON_STATUS_OK);
    case simdjson::UTF8_ERROR:
      code = SIMD_JSON_STATUS_INVALID_UTF8;
      break;
    case simdjson::EMPTY:
    case simdjson::UNCLOSED_STRING:
    case simdjson::INCOMPLETE_ARRAY_OR_OBJECT:
      code = SIMD_JSON_STATUS_UNEXPECTED_EOF;
      break;
    case simdjson::MEMALLOC:
    case simdjson::OUT_OF_CAPACITY:
      code = SIMD_JSON_STATUS_OUT_OF_MEMORY;
      break;
    case simdjson::CAPACITY:
    case simdjson::INSUFFICIENT_PADDING:
      code = SIMD_JSON_STATUS_INVALID_ARGUMENT;
      break;
    case simdjson::NO_SUCH_FIELD:
      code = SIMD_JSON_STATUS_MISSING_FIELD;
      break;
    case simdjson::INDEX_OUT_OF_BOUNDS:
      code = SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS;
      break;
    case simdjson::INCORRECT_TYPE:
      code = SIMD_JSON_STATUS_INCORRECT_TYPE;
      break;
    case simdjson::BIGINT_ERROR:
    case simdjson::NUMBER_OUT_OF_RANGE:
      code = SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE;
      break;
    case simdjson::OUT_OF_ORDER_ITERATION:
      code = SIMD_JSON_STATUS_CURSOR_CONSUMED;
      break;
    case simdjson::UNINITIALIZED:
    case simdjson::UNSUPPORTED_ARCHITECTURE:
    case simdjson::UNEXPECTED_ERROR:
    case simdjson::PARSER_IN_USE:
    case simdjson::SCALAR_DOCUMENT_AS_VALUE:
    case simdjson::OUT_OF_BOUNDS:
      code = SIMD_JSON_STATUS_INTERNAL_FAILURE;
      break;
    default:
      code = SIMD_JSON_STATUS_INVALID_JSON;
      break;
  }

  const uint64_t offset =
      code == SIMD_JSON_STATUS_OUT_OF_MEMORY ||
              code == SIMD_JSON_STATUS_INVALID_ARGUMENT ||
              code == SIMD_JSON_STATUS_INTERNAL_FAILURE ||
              code == SIMD_JSON_STATUS_CURSOR_CONSUMED
          ? SIMD_JSON_BYTE_OFFSET_UNAVAILABLE
          : current_byte_offset(context);
  return make_status(code, static_cast<int32_t>(error), offset, output_slot);
}

bool cancellation_requested(traversal_context &context) {
  saturating_increment(context.counters.cancellation_checks);
  projection_checkpoint();
  return simd_json_native::projection_cancelled(context.opaque_document);
}

void note_node_visit(const projection_node &node,
                     traversal_context &context) noexcept {
  saturating_increment(context.counters.visited_nodes);
  if (node.subtree_output_slots > 1) {
    saturating_increment(context.counters.shared_prefix_visits);
  }
}

void record_path_failure(traversal_context &context,
                         simd_json_status_code code,
                         uint32_t output_slot) noexcept {
  if (output_slot == SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE) {
    return;
  }

  if (context.pending_path_failure.code == SIMD_JSON_STATUS_OK ||
      output_slot < context.pending_path_failure.output_slot) {
    context.pending_path_failure = make_status(
        code, SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
        SIMD_JSON_BYTE_OFFSET_UNAVAILABLE, output_slot);
  }
}

uint32_t first_child_output_slot(const projection_node &node) noexcept {
  uint32_t first = SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE;
  for (const object_edge &edge : node.object_edges) {
    first = std::min(first, edge.child->first_output_slot);
  }
  for (const array_edge &edge : node.array_edges) {
    first = std::min(first, edge.child->first_output_slot);
  }
  return first;
}

uint32_t first_object_child_output_slot(
    const projection_node &node) noexcept {
  uint32_t first = SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE;
  for (const object_edge &edge : node.object_edges) {
    first = std::min(first, edge.child->first_output_slot);
  }
  return first;
}

uint32_t first_array_child_output_slot(
    const projection_node &node) noexcept {
  uint32_t first = SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE;
  for (const array_edge &edge : node.array_edges) {
    first = std::min(first, edge.child->first_output_slot);
  }
  return first;
}

simd_json_projection_status validate_unselected_value(
    simdjson::ondemand::value &value,
    traversal_context &context);

simd_json_projection_status validate_unselected_array(
    simdjson::ondemand::array &array,
    traversal_context &context) {
  for (auto child_result : array) {
    if (cancellation_requested(context)) {
      return make_status(SIMD_JSON_STATUS_CANCELLED);
    }

    saturating_increment(context.counters.array_elements);
    simdjson::ondemand::value child;
    simdjson::error_code error = child_result.get(child);
    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(error, context);
    }

    simd_json_projection_status status =
        validate_unselected_value(child, context);
    if (status.code != SIMD_JSON_STATUS_OK) {
      return status;
    }
  }

  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_projection_status validate_unselected_object(
    simdjson::ondemand::object &object,
    traversal_context &context) {
  for (auto field_result : object) {
    if (cancellation_requested(context)) {
      return make_status(SIMD_JSON_STATUS_CANCELLED);
    }

    saturating_increment(context.counters.object_fields);
    simdjson::ondemand::field field;
    simdjson::error_code error = std::move(field_result).get(field);
    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(error, context);
    }

    std::string_view key;
    error = field.unescaped_key().get(key);
    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(error, context);
    }
    (void)key;

    simd_json_projection_status status =
        validate_unselected_value(field.value(), context);
    if (status.code != SIMD_JSON_STATUS_OK) {
      return status;
    }
  }

  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_projection_status validate_unselected_value(
    simdjson::ondemand::value &value,
    traversal_context &context) {
  if (cancellation_requested(context)) {
    return make_status(SIMD_JSON_STATUS_CANCELLED);
  }
  saturating_increment(context.counters.skipped_values);

  simdjson::ondemand::json_type type;
  simdjson::error_code error = value.type().get(type);
  if (error != simdjson::SUCCESS) {
    return status_from_simdjson(error, context);
  }

  switch (type) {
    case simdjson::ondemand::json_type::array: {
      simdjson::ondemand::array array;
      error = value.get_array().get(array);
      return error == simdjson::SUCCESS
                 ? validate_unselected_array(array, context)
                 : status_from_simdjson(error, context);
    }
    case simdjson::ondemand::json_type::object: {
      simdjson::ondemand::object object;
      error = value.get_object().get(object);
      return error == simdjson::SUCCESS
                 ? validate_unselected_object(object, context)
                 : status_from_simdjson(error, context);
    }
    case simdjson::ondemand::json_type::number: {
      const std::string_view raw = value.raw_json_token();
      simdjson::ondemand::number number;
      error = value.get_number().get(number);
      if (error != simdjson::SUCCESS) {
        if (error == simdjson::NUMBER_ERROR &&
            valid_json_number_syntax(raw)) {
          return make_status(SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
                             static_cast<int32_t>(error),
                             current_byte_offset(context));
        }
        return status_from_simdjson(error, context);
      }
      if (number.get_number_type() ==
              simdjson::ondemand::number_type::big_integer ||
          (number.get_number_type() ==
               simdjson::ondemand::number_type::floating_point_number &&
           !std::isfinite(number.get_double()))) {
        return make_status(SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
                           SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
                           current_byte_offset(context));
      }
      return make_status(SIMD_JSON_STATUS_OK);
    }
    case simdjson::ondemand::json_type::string: {
      std::string_view string;
      error = value.get_string().get(string);
      (void)string;
      break;
    }
    case simdjson::ondemand::json_type::boolean: {
      bool boolean = false;
      error = value.get_bool().get(boolean);
      (void)boolean;
      break;
    }
    case simdjson::ondemand::json_type::null: {
      bool is_null = false;
      error = value.is_null().get(is_null);
      if (error == simdjson::SUCCESS && !is_null) {
        error = simdjson::TAPE_ERROR;
      }
      break;
    }
    case simdjson::ondemand::json_type::unknown:
      error = simdjson::TAPE_ERROR;
      break;
  }

  return error == simdjson::SUCCESS
             ? make_status(SIMD_JSON_STATUS_OK)
             : status_from_simdjson(error, context);
}

simd_json_projection_status materialize_scalar(
    simdjson::ondemand::value &value,
    simdjson::ondemand::json_type type,
    const projection_node &node,
    traversal_context &context) {
  if (cancellation_requested(context)) {
    return make_status(SIMD_JSON_STATUS_CANCELLED);
  }

  simd_json_result_slot materialized{};
  simdjson::error_code error = simdjson::SUCCESS;

  switch (type) {
    case simdjson::ondemand::json_type::number: {
      const std::string_view raw = value.raw_json_token();
      simdjson::ondemand::number number;
      error = value.get_number().get(number);
      if (error != simdjson::SUCCESS) {
        if (error == simdjson::NUMBER_ERROR &&
            valid_json_number_syntax(raw)) {
          return make_status(
              SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
              static_cast<int32_t>(error), current_byte_offset(context),
              node.terminal_slots.empty() ? SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE
                                          : node.terminal_slots.front());
        }
        return status_from_simdjson(
            error, context,
            node.terminal_slots.empty() ? SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE
                                        : node.terminal_slots.front());
      }

      switch (number.get_number_type()) {
        case simdjson::ondemand::number_type::signed_integer:
          materialized.tag = SIMD_JSON_RESULT_SIGNED_INTEGER;
          materialized.value.signed_integer = number.get_int64();
          break;
        case simdjson::ondemand::number_type::unsigned_integer:
          materialized.tag = SIMD_JSON_RESULT_UNSIGNED_INTEGER;
          materialized.value.unsigned_integer = number.get_uint64();
          break;
        case simdjson::ondemand::number_type::floating_point_number:
          if (!std::isfinite(number.get_double())) {
            return make_status(
                SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
                SIMD_JSON_NATIVE_CODE_UNAVAILABLE, current_byte_offset(context),
                node.terminal_slots.empty() ? SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE
                                            : node.terminal_slots.front());
          }
          materialized.tag = SIMD_JSON_RESULT_DOUBLE;
          materialized.value.floating_point = number.get_double();
          break;
        case simdjson::ondemand::number_type::big_integer:
          return make_status(
              SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
              SIMD_JSON_NATIVE_CODE_UNAVAILABLE, current_byte_offset(context),
              node.terminal_slots.empty() ? SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE
                                          : node.terminal_slots.front());
      }
      break;
    }
    case simdjson::ondemand::json_type::string: {
      std::string_view string;
      error = value.get_string().get(string);
      if (error == simdjson::SUCCESS) {
        materialized.tag = SIMD_JSON_RESULT_STRING;
        materialized.value.string.data =
            reinterpret_cast<const uint8_t *>(string.data());
        materialized.value.string.length = static_cast<uint64_t>(string.size());
      }
      break;
    }
    case simdjson::ondemand::json_type::boolean: {
      bool boolean = false;
      error = value.get_bool().get(boolean);
      if (error == simdjson::SUCCESS) {
        materialized.tag = SIMD_JSON_RESULT_BOOLEAN;
        materialized.value.boolean = boolean ? UINT64_C(1) : UINT64_C(0);
      }
      break;
    }
    case simdjson::ondemand::json_type::null: {
      bool is_null = false;
      error = value.is_null().get(is_null);
      if (error == simdjson::SUCCESS && !is_null) {
        error = simdjson::TAPE_ERROR;
      } else if (error == simdjson::SUCCESS) {
        materialized.tag = SIMD_JSON_RESULT_NULL;
      }
      break;
    }
    case simdjson::ondemand::json_type::array:
    case simdjson::ondemand::json_type::object:
    case simdjson::ondemand::json_type::unknown:
      return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  }

  if (error != simdjson::SUCCESS) {
    return status_from_simdjson(
        error, context,
        node.terminal_slots.empty() ? SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE
                                    : node.terminal_slots.front());
  }

  for (uint32_t output_slot : node.terminal_slots) {
    if (cancellation_requested(context)) {
      return make_status(SIMD_JSON_STATUS_CANCELLED);
    }
    context.result_slots[output_slot] = materialized;
    saturating_increment(context.counters.filled_slots);
  }

  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_projection_status traverse_value(
    simdjson::ondemand::value &value,
    const projection_node &node,
    traversal_context &context);

simd_json_projection_status traverse_object(
    simdjson::ondemand::object &object,
    const projection_node &node,
    traversal_context &context) {
  if (!node.terminal_slots.empty()) {
    record_path_failure(context, SIMD_JSON_STATUS_INCORRECT_TYPE,
                        node.terminal_slots.front());
  }
  record_path_failure(context, SIMD_JSON_STATUS_INCORRECT_TYPE,
                      first_array_child_output_slot(node));

  for (auto field_result : object) {
    if (cancellation_requested(context)) {
      return make_status(SIMD_JSON_STATUS_CANCELLED);
    }

    saturating_increment(context.counters.object_fields);
    simdjson::ondemand::field field;
    simdjson::error_code error = std::move(field_result).get(field);
    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(error, context);
    }

    std::string_view key;
    error = field.unescaped_key().get(key);
    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(error, context);
    }

    const uint8_t *key_bytes =
        reinterpret_cast<const uint8_t *>(key.data());
    const auto edge = std::lower_bound(
        node.object_edges.begin(), node.object_edges.end(), key_bytes,
        [&key](const object_edge &candidate, const uint8_t *bytes) {
          return byte_less(candidate.key.bytes(), bytes, key.size());
        });

    simd_json_projection_status status;
    if (edge != node.object_edges.end() &&
        byte_equal(edge->key.bytes(), key_bytes, key.size()) &&
        context.satisfied_object_edges[edge->execution_id] == 0) {
      context.satisfied_object_edges[edge->execution_id] = UINT8_C(1);
      status = traverse_value(field.value(), *edge->child, context);
    } else {
      status = validate_unselected_value(field.value(), context);
    }

    if (status.code != SIMD_JSON_STATUS_OK) {
      return status;
    }
  }

  for (const object_edge &edge : node.object_edges) {
    if (context.satisfied_object_edges[edge.execution_id] == 0) {
      record_path_failure(context, SIMD_JSON_STATUS_MISSING_FIELD,
                          edge.child->first_output_slot);
    }
  }

  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_projection_status traverse_array(
    simdjson::ondemand::array &array,
    const projection_node &node,
    traversal_context &context) {
  if (!node.terminal_slots.empty()) {
    record_path_failure(context, SIMD_JSON_STATUS_INCORRECT_TYPE,
                        node.terminal_slots.front());
  }
  record_path_failure(context, SIMD_JSON_STATUS_INCORRECT_TYPE,
                      first_object_child_output_slot(node));

  size_t requested_position = 0;
  uint64_t source_index = 0;
  for (auto child_result : array) {
    if (cancellation_requested(context)) {
      return make_status(SIMD_JSON_STATUS_CANCELLED);
    }

    saturating_increment(context.counters.array_elements);
    simdjson::ondemand::value child;
    simdjson::error_code error = child_result.get(child);
    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(error, context);
    }

    simd_json_projection_status status;
    if (requested_position < node.array_edges.size() &&
        node.array_edges[requested_position].index == source_index) {
      status = traverse_value(
          child, *node.array_edges[requested_position].child, context);
      ++requested_position;
    } else {
      status = validate_unselected_value(child, context);
    }

    if (status.code != SIMD_JSON_STATUS_OK) {
      return status;
    }
    if (source_index == UINT64_MAX) {
      return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
    }
    ++source_index;
  }

  if (requested_position < node.array_edges.size()) {
    record_path_failure(
        context, SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS,
        node.array_edges[requested_position].child->first_output_slot);
  }

  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_projection_status traverse_value(
    simdjson::ondemand::value &value,
    const projection_node &node,
    traversal_context &context) {
  if (cancellation_requested(context)) {
    return make_status(SIMD_JSON_STATUS_CANCELLED);
  }
  note_node_visit(node, context);

  simdjson::ondemand::json_type type;
  simdjson::error_code error = value.type().get(type);
  if (error != simdjson::SUCCESS) {
    return status_from_simdjson(error, context);
  }

  switch (type) {
    case simdjson::ondemand::json_type::object: {
      simdjson::ondemand::object object;
      error = value.get_object().get(object);
      return error == simdjson::SUCCESS
                 ? traverse_object(object, node, context)
                 : status_from_simdjson(error, context);
    }
    case simdjson::ondemand::json_type::array: {
      simdjson::ondemand::array array;
      error = value.get_array().get(array);
      return error == simdjson::SUCCESS
                 ? traverse_array(array, node, context)
                 : status_from_simdjson(error, context);
    }
    case simdjson::ondemand::json_type::number:
    case simdjson::ondemand::json_type::string:
    case simdjson::ondemand::json_type::boolean:
    case simdjson::ondemand::json_type::null:
      record_path_failure(context, SIMD_JSON_STATUS_INCORRECT_TYPE,
                          first_child_output_slot(node));
      return materialize_scalar(value, type, node, context);
    case simdjson::ondemand::json_type::unknown:
      return status_from_simdjson(simdjson::TAPE_ERROR, context);
  }

  return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
}

simd_json_projection_status consume_root_scalar(
    simdjson::ondemand::json_type type,
    const projection_node &root,
    traversal_context &context) {
  simdjson::error_code error = simdjson::SUCCESS;

  switch (type) {
    case simdjson::ondemand::json_type::number: {
      std::string_view raw;
      simdjson::error_code raw_error =
          context.document.raw_json_token().get(raw);
      if (raw_error != simdjson::SUCCESS) {
        return status_from_simdjson(raw_error, context);
      }
      simdjson::ondemand::number number;
      error = context.document.get_number().get(number);
      if (error == simdjson::NUMBER_ERROR && valid_json_number_syntax(raw)) {
        return make_status(SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
                           static_cast<int32_t>(error),
                           current_byte_offset(context));
      }
      if (error == simdjson::SUCCESS &&
          (number.get_number_type() ==
               simdjson::ondemand::number_type::big_integer ||
           (number.get_number_type() ==
                simdjson::ondemand::number_type::floating_point_number &&
            !std::isfinite(number.get_double())))) {
        return make_status(SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
                           SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
                           current_byte_offset(context));
      }
      break;
    }
    case simdjson::ondemand::json_type::string: {
      std::string_view string;
      error = context.document.get_string().get(string);
      (void)string;
      break;
    }
    case simdjson::ondemand::json_type::boolean: {
      bool boolean = false;
      error = context.document.get_bool().get(boolean);
      (void)boolean;
      break;
    }
    case simdjson::ondemand::json_type::null: {
      bool is_null = false;
      error = context.document.is_null().get(is_null);
      if (error == simdjson::SUCCESS && !is_null) {
        error = simdjson::TAPE_ERROR;
      }
      break;
    }
    case simdjson::ondemand::json_type::array:
    case simdjson::ondemand::json_type::object:
    case simdjson::ondemand::json_type::unknown:
      return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  }

  if (error != simdjson::SUCCESS) {
    return status_from_simdjson(error, context);
  }

  record_path_failure(context, SIMD_JSON_STATUS_INCORRECT_TYPE,
                      root.first_output_slot);
  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_projection_status traverse_document(
    const simd_json_projection_plan &plan,
    traversal_context &context) {
  if (cancellation_requested(context)) {
    return make_status(SIMD_JSON_STATUS_CANCELLED);
  }
  note_node_visit(*plan.root, context);

  simdjson::ondemand::json_type type;
  simdjson::error_code error = context.document.type().get(type);
  if (error != simdjson::SUCCESS) {
    return status_from_simdjson(error, context);
  }

  switch (type) {
    case simdjson::ondemand::json_type::object: {
      simdjson::ondemand::object object;
      error = context.document.get_object().get(object);
      return error == simdjson::SUCCESS
                 ? traverse_object(object, *plan.root, context)
                 : status_from_simdjson(error, context);
    }
    case simdjson::ondemand::json_type::array: {
      simdjson::ondemand::array array;
      error = context.document.get_array().get(array);
      return error == simdjson::SUCCESS
                 ? traverse_array(array, *plan.root, context)
                 : status_from_simdjson(error, context);
    }
    case simdjson::ondemand::json_type::number:
    case simdjson::ondemand::json_type::string:
    case simdjson::ondemand::json_type::boolean:
    case simdjson::ondemand::json_type::null:
      return consume_root_scalar(type, *plan.root, context);
    case simdjson::ondemand::json_type::unknown:
      return status_from_simdjson(simdjson::TAPE_ERROR, context);
  }

  return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
}

void clear_result_slots(simd_json_result_slot *result_slots,
                        uint64_t result_slot_count) noexcept {
  for (uint64_t index = 0; index < result_slot_count; ++index) {
    result_slots[index] = simd_json_result_slot{};
  }
}

#ifdef SIMD_JSON_TESTING
uint64_t elapsed_nanoseconds(
    std::chrono::steady_clock::time_point started) noexcept {
  const auto elapsed = std::chrono::steady_clock::now() - started;
  const auto nanoseconds =
      std::chrono::duration_cast<std::chrono::nanoseconds>(elapsed).count();
  return nanoseconds <= 0 ? 0 : static_cast<uint64_t>(nanoseconds);
}

void record_execution(const simd_json_projection_plan &plan,
                      const traversal_counters &counters,
                      std::chrono::steady_clock::time_point started) noexcept {
  plan.last_traversal_nanoseconds.store(elapsed_nanoseconds(started),
                                        std::memory_order_release);
  plan.last_visited_nodes.store(counters.visited_nodes,
                                std::memory_order_release);
  plan.last_shared_prefix_visits.store(counters.shared_prefix_visits,
                                       std::memory_order_release);
  plan.last_filled_slots.store(counters.filled_slots,
                               std::memory_order_release);
  plan.last_object_fields.store(counters.object_fields,
                                std::memory_order_release);
  plan.last_array_elements.store(counters.array_elements,
                                 std::memory_order_release);
  plan.last_skipped_values.store(counters.skipped_values,
                                 std::memory_order_release);
  plan.last_cancellation_checks.store(counters.cancellation_checks,
                                      std::memory_order_release);
}
#endif

}  // namespace

extern "C" simd_json_projection_status simd_json_projection_plan_create(
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
#ifdef SIMD_JSON_TESTING
    const auto compilation_started = std::chrono::steady_clock::now();
#endif
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

    finalize_plan_metadata(*plan);
    plan->topology_hash = retained_topology_hash(*plan);
#ifdef SIMD_JSON_TESTING
    plan->compilation_nanoseconds = elapsed_nanoseconds(compilation_started);
#endif
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

extern "C" simd_json_projection_status simd_json_projection_execute(
    simd_json_document *document,
    const simd_json_projection_plan *plan,
    simd_json_result_slot *result_slots,
    uint64_t result_slot_count) noexcept {
  if (document == nullptr || plan == nullptr || result_slots == nullptr ||
      result_slot_count != plan->output_slots || exceeds_size_t(result_slot_count)) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  for (uint64_t index = 0; index < result_slot_count; ++index) {
    if (result_slots[index].reserved != UINT32_C(0)) {
      return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
    }
  }

  clear_result_slots(result_slots, result_slot_count);
  traversal_counters counters;

#ifdef SIMD_JSON_TESTING
  const auto traversal_started = std::chrono::steady_clock::now();
  plan->execution_entries.fetch_add(1, std::memory_order_acq_rel);
#endif

  const auto finish = [&](simd_json_projection_status status) noexcept {
    if (status.code != SIMD_JSON_STATUS_OK) {
      clear_result_slots(result_slots, result_slot_count);
    }
#ifdef SIMD_JSON_TESTING
    record_execution(*plan, counters, traversal_started);
#endif
    return status;
  };

  try {
    projection_checkpoint();
    std::vector<uint8_t> satisfied_object_edges(
        static_cast<size_t>(plan->object_edges), UINT8_C(0));
    simdjson::ondemand::document *native_document =
        simd_json_native::document_value(document);
    const uint8_t *data = simd_json_native::document_data(document);
    const uint64_t logical_length =
        simd_json_native::document_logical_length(document);
    if (native_document == nullptr || data == nullptr) {
      return finish(make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT));
    }

    traversal_context context{
        document,       *native_document, data, logical_length,
        result_slots,   satisfied_object_edges,
        make_status(SIMD_JSON_STATUS_OK), counters,
    };

    if (cancellation_requested(context)) {
      return finish(make_status(SIMD_JSON_STATUS_CANCELLED));
    }
    if (!simd_json_native::claim_projection_cursor(document)) {
      return finish(make_status(SIMD_JSON_STATUS_CURSOR_CONSUMED));
    }

    simd_json_projection_status status = traverse_document(*plan, context);
    if (status.code != SIMD_JSON_STATUS_OK) {
      return finish(status);
    }
    if (context.pending_path_failure.code != SIMD_JSON_STATUS_OK) {
      return finish(context.pending_path_failure);
    }

    for (uint64_t index = 0; index < result_slot_count; ++index) {
      if (result_slots[index].tag == SIMD_JSON_RESULT_EMPTY ||
          result_slots[index].reserved != UINT32_C(0)) {
        return finish(make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE));
      }
    }

    return finish(make_status(SIMD_JSON_STATUS_OK));
  } catch (...) {
    return finish(status_from_current_exception());
  }
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

extern "C" uint32_t simd_json_test_projection_execution_summary_read(
    const simd_json_projection_plan *plan,
    simd_json_test_projection_execution_summary *out_summary) noexcept {
  if (plan == nullptr || out_summary == nullptr) {
    return UINT32_C(0);
  }

  try {
    *out_summary = {
        plan->compilation_nanoseconds,
        plan->last_traversal_nanoseconds.load(std::memory_order_acquire),
        plan->execution_entries.load(std::memory_order_acquire),
        plan->last_visited_nodes.load(std::memory_order_acquire),
        plan->last_shared_prefix_visits.load(std::memory_order_acquire),
        plan->last_filled_slots.load(std::memory_order_acquire),
        plan->last_object_fields.load(std::memory_order_acquire),
        plan->last_array_elements.load(std::memory_order_acquire),
        plan->last_skipped_values.load(std::memory_order_acquire),
        plan->last_cancellation_checks.load(std::memory_order_acquire),
    };
    return UINT32_C(1);
  } catch (...) {
    return UINT32_C(0);
  }
}
#endif
