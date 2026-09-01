#include "../include/simd_json_abi.h"
#include "../vendor/simdjson/simdjson.h"

/* covers: simd_json.stream_cursor.private_abi_v3 simd_json.stream_cursor.opaque_cursor simd_json.stream_cursor.projection_plan_reuse simd_json.stream_cursor.exception_and_failure_cleanup simd_json.native_build_and_abi.opaque_c_contract simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.partial_failure_cleanup */

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <limits>
#include <memory>
#include <new>
#include <stdexcept>
#include <utility>
#include <vector>

#ifdef SIMD_JSON_TESTING
#include "../test/include/simd_json_test_hooks.h"
#endif

namespace {

constexpr simd_json_stream_status make_status(
    simd_json_status_code code,
    int32_t native_code = SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
    uint64_t byte_offset = SIMD_JSON_BYTE_OFFSET_UNAVAILABLE,
    uint32_t output_slot = SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE,
    uint64_t array_index = SIMD_JSON_ARRAY_INDEX_UNAVAILABLE) noexcept {
  return {code, native_code, byte_offset, output_slot, UINT32_C(0),
          array_index};
}

constexpr bool exceeds_size_t(uint64_t value) noexcept {
  if constexpr (sizeof(size_t) >= sizeof(uint64_t)) {
    (void)value;
    return false;
  } else {
    return value > std::numeric_limits<size_t>::max();
  }
}

constexpr bool checked_range(uint64_t offset,
                             uint64_t length,
                             uint64_t total) noexcept {
  return offset <= total && length <= total - offset;
}

#ifdef SIMD_JSON_TESTING
std::atomic<uint64_t> live_stream_cursors{0};
std::atomic<uint64_t> live_stream_frames{0};
std::atomic<uint64_t> live_stream_key_bytes{0};
std::atomic<uint64_t> live_stream_owned_plans{0};
std::atomic<uint64_t> stream_failure_after{UINT64_MAX};
std::atomic<int32_t> stream_failure_kind{0};

void stream_checkpoint() {
  int32_t kind = stream_failure_kind.load(std::memory_order_acquire);
  if (kind == 0) {
    return;
  }

  uint64_t remaining = stream_failure_after.load(std::memory_order_acquire);
  while (remaining != 0) {
    if (stream_failure_after.compare_exchange_weak(
            remaining, remaining - 1, std::memory_order_acq_rel,
            std::memory_order_acquire)) {
      return;
    }
  }

  if (!stream_failure_kind.compare_exchange_strong(
          kind, 0, std::memory_order_acq_rel, std::memory_order_acquire)) {
    return;
  }
  stream_failure_after.store(UINT64_MAX, std::memory_order_release);

  switch (kind) {
    case SIMD_JSON_TEST_FAILURE_SIMDJSON:
      throw simdjson::simdjson_error(simdjson::TAPE_ERROR);
    case SIMD_JSON_TEST_FAILURE_BAD_ALLOC:
      throw std::bad_alloc{};
    case SIMD_JSON_TEST_FAILURE_STANDARD:
      throw std::runtime_error{"simd_json_stream_standard_exception"};
    case SIMD_JSON_TEST_FAILURE_UNKNOWN:
      throw 1;
    default:
      return;
  }
}

void account_cursor_created() noexcept {
  live_stream_cursors.fetch_add(1, std::memory_order_acq_rel);
}

void account_cursor_destroyed() noexcept {
  live_stream_cursors.fetch_sub(1, std::memory_order_acq_rel);
}

void account_frames_created(uint64_t count) noexcept {
  live_stream_frames.fetch_add(count, std::memory_order_acq_rel);
}

void account_frames_destroyed(uint64_t count) noexcept {
  live_stream_frames.fetch_sub(count, std::memory_order_acq_rel);
}

void account_key_bytes_created(uint64_t count) noexcept {
  live_stream_key_bytes.fetch_add(count, std::memory_order_acq_rel);
}

void account_key_bytes_destroyed(uint64_t count) noexcept {
  live_stream_key_bytes.fetch_sub(count, std::memory_order_acq_rel);
}

void account_plan_acquired() noexcept {
  live_stream_owned_plans.fetch_add(1, std::memory_order_acq_rel);
}

void account_plan_released() noexcept {
  live_stream_owned_plans.fetch_sub(1, std::memory_order_acq_rel);
}
#else
void stream_checkpoint() {}
void account_cursor_created() noexcept {}
void account_cursor_destroyed() noexcept {}
void account_frames_created(uint64_t) noexcept {}
void account_frames_destroyed(uint64_t) noexcept {}
void account_key_bytes_created(uint64_t) noexcept {}
void account_key_bytes_destroyed(uint64_t) noexcept {}
void account_plan_acquired() noexcept {}
void account_plan_released() noexcept {}
#endif

bool target_is_valid(const simd_json_stream_target &target) noexcept {
  if (target.segment_count == 0) {
    return target.segments == nullptr && target.key_bytes == nullptr &&
           target.key_bytes_length == 0;
  }
  if (target.segments == nullptr || target.segment_count > SIMD_JSON_MAX_DEPTH ||
      exceeds_size_t(target.segment_count) ||
      exceeds_size_t(target.key_bytes_length) ||
      ((target.key_bytes == nullptr) != (target.key_bytes_length == 0))) {
    return false;
  }

  for (uint64_t index = 0; index < target.segment_count; ++index) {
    const simd_json_projection_segment &segment = target.segments[index];
    if (segment.reserved != UINT32_C(0)) {
      return false;
    }

    if (segment.tag == SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY) {
      if (segment.array_index != 0 ||
          !checked_range(segment.key_offset, segment.key_length,
                         target.key_bytes_length) ||
          exceeds_size_t(segment.key_length)) {
        return false;
      }
      if (segment.key_length != 0 &&
          !simdjson::validate_utf8(
              reinterpret_cast<const char *>(target.key_bytes +
                                               segment.key_offset),
              static_cast<size_t>(segment.key_length))) {
        return false;
      }
    } else if (segment.tag == SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX) {
      if (segment.key_offset != 0 || segment.key_length != 0) {
        return false;
      }
    } else {
      return false;
    }
  }

  return true;
}

bool config_is_valid(const simd_json_stream_cursor_config &config) noexcept {
  return config.projection_plan != nullptr && config.row_limit != 0 &&
         config.row_limit <= SIMD_JSON_STREAM_MAX_BATCH_SIZE &&
         config.encoded_byte_limit != 0 &&
         config.encoded_byte_limit <= SIMD_JSON_STREAM_MAX_BATCH_BYTES &&
         config.parent_generation != 0 && config.reserved == 0;
}

bool storage_is_valid(const simd_json_stream_batch_storage &batch,
                      uint64_t row_limit,
                      uint64_t encoded_byte_limit) noexcept {
  if (batch.reserved != UINT32_C(0) || batch.row_capacity == 0 ||
      batch.row_capacity > row_limit || batch.rows == nullptr ||
      batch.slot_capacity == 0 || batch.slots == nullptr ||
      batch.copied_byte_capacity > encoded_byte_limit ||
      ((batch.copied_bytes == nullptr) !=
       (batch.copied_byte_capacity == 0)) ||
      exceeds_size_t(batch.row_capacity) ||
      exceeds_size_t(batch.slot_capacity) ||
      exceeds_size_t(batch.copied_byte_capacity)) {
    return false;
  }
  return true;
}

void clear_batch(simd_json_stream_batch_storage &batch) noexcept {
  batch.produced_rows = 0;
  batch.produced_slots = 0;
  batch.encoded_bytes = 0;
  batch.done = SIMD_JSON_STREAM_NOT_DONE;
}

simd_json_stream_status status_from_current_exception() noexcept {
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

struct simd_json_stream_cursor {
  simd_json_document *document = nullptr;
  simd_json_projection_plan *projection_plan = nullptr;
  std::vector<simd_json_projection_segment> target_segments;
  std::vector<uint8_t> target_key_bytes;
  uint64_t row_limit = 0;
  uint64_t encoded_byte_limit = 0;
  uint64_t parent_generation = 0;
  std::atomic<uint32_t> state{SIMD_JSON_STREAM_CURSOR_READY};
  std::atomic<uint64_t> current_row_index{0};
  std::atomic<uint64_t> batch_sequence{0};
  uint64_t accounted_frames = 0;
  uint64_t accounted_key_bytes = 0;
  bool plan_accounted = false;

  simd_json_stream_cursor() { account_cursor_created(); }

  ~simd_json_stream_cursor() {
    state.store(SIMD_JSON_STREAM_CURSOR_CLOSED, std::memory_order_release);
    if (projection_plan != nullptr) {
      simd_json_projection_plan_destroy(projection_plan);
      projection_plan = nullptr;
      if (plan_accounted) {
        account_plan_released();
        plan_accounted = false;
      }
    }
    account_key_bytes_destroyed(accounted_key_bytes);
    account_frames_destroyed(accounted_frames);
    accounted_key_bytes = 0;
    accounted_frames = 0;
    document = nullptr;
    account_cursor_destroyed();
  }

  simd_json_stream_cursor(const simd_json_stream_cursor &) = delete;
  simd_json_stream_cursor &operator=(const simd_json_stream_cursor &) = delete;
};

extern "C" simd_json_stream_status simd_json_stream_cursor_create(
    simd_json_document *document,
    const simd_json_stream_target *target,
    simd_json_stream_cursor_config *config,
    simd_json_stream_cursor **out_cursor) noexcept {
  if (out_cursor == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }
  *out_cursor = nullptr;

  if (document == nullptr || target == nullptr || config == nullptr ||
      !target_is_valid(*target) || !config_is_valid(*config)) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  try {
    stream_checkpoint();
    auto cursor = std::make_unique<simd_json_stream_cursor>();
    cursor->document = document;
    cursor->row_limit = config->row_limit;
    cursor->encoded_byte_limit = config->encoded_byte_limit;
    cursor->parent_generation = config->parent_generation;

    stream_checkpoint();
    if (target->segment_count != 0) {
      cursor->target_segments.assign(
          target->segments, target->segments + target->segment_count);
    }
    cursor->accounted_frames = target->segment_count;
    account_frames_created(cursor->accounted_frames);

    stream_checkpoint();
    if (target->key_bytes_length != 0) {
      cursor->target_key_bytes.assign(
          target->key_bytes, target->key_bytes + target->key_bytes_length);
    }
    cursor->accounted_key_bytes = target->key_bytes_length;
    account_key_bytes_created(cursor->accounted_key_bytes);

    cursor->projection_plan = config->projection_plan;
    config->projection_plan = nullptr;
    cursor->plan_accounted = true;
    account_plan_acquired();

    stream_checkpoint();
    *out_cursor = cursor.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    return status_from_current_exception();
  }
}

extern "C" void simd_json_stream_cursor_destroy(
    simd_json_stream_cursor *cursor) noexcept {
  try {
    delete cursor;
  } catch (...) {
  }
}

extern "C" simd_json_stream_status simd_json_stream_next_batch(
    simd_json_stream_cursor *cursor,
    const simd_json_cancellation_probe *cancellation,
    simd_json_stream_batch_storage *batch) noexcept {
  if (cursor == nullptr || batch == nullptr ||
      !storage_is_valid(*batch, cursor == nullptr ? 0 : cursor->row_limit,
                        cursor == nullptr ? 0 : cursor->encoded_byte_limit)) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }
  clear_batch(*batch);

  if (cancellation != nullptr) {
    if (cancellation->check == nullptr) {
      return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
    }
    const uint32_t cancelled = cancellation->check(cancellation->context);
    if (cancelled > UINT32_C(1)) {
      return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
    }
    if (cancelled == UINT32_C(1)) {
      uint32_t expected = SIMD_JSON_STREAM_CURSOR_READY;
      cursor->state.compare_exchange_strong(
          expected, SIMD_JSON_STREAM_CURSOR_CANCELLED,
          std::memory_order_acq_rel, std::memory_order_acquire);
      return make_status(SIMD_JSON_STATUS_CANCELLED);
    }
  }

  uint32_t expected = SIMD_JSON_STREAM_CURSOR_READY;
  if (!cursor->state.compare_exchange_strong(
          expected, SIMD_JSON_STREAM_CURSOR_RUNNING, std::memory_order_acq_rel,
          std::memory_order_acquire)) {
    if (expected == SIMD_JSON_STREAM_CURSOR_DONE) {
      batch->done = SIMD_JSON_STREAM_DONE;
      return make_status(SIMD_JSON_STATUS_OK);
    }
    if (expected == SIMD_JSON_STREAM_CURSOR_CANCELLED) {
      return make_status(SIMD_JSON_STATUS_CANCELLED);
    }
    return make_status(SIMD_JSON_STATUS_CURSOR_STATE);
  }

  try {
    stream_checkpoint();
    cursor->state.store(SIMD_JSON_STREAM_CURSOR_READY,
                        std::memory_order_release);
    return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  } catch (...) {
    cursor->state.store(SIMD_JSON_STREAM_CURSOR_READY,
                        std::memory_order_release);
    return status_from_current_exception();
  }
}

#ifdef SIMD_JSON_TESTING
extern "C" void simd_json_test_stream_inject_failure(
    uint64_t successful_checkpoints, int32_t kind) noexcept {
  try {
    stream_failure_after.store(successful_checkpoints,
                               std::memory_order_release);
    stream_failure_kind.store(kind, std::memory_order_release);
  } catch (...) {
    stream_failure_kind.store(0, std::memory_order_release);
    stream_failure_after.store(UINT64_MAX, std::memory_order_release);
  }
}

extern "C" void simd_json_test_stream_clear_failure(void) noexcept {
  try {
    stream_failure_kind.store(0, std::memory_order_release);
    stream_failure_after.store(UINT64_MAX, std::memory_order_release);
  } catch (...) {
  }
}

extern "C" simd_json_test_stream_accounting
simd_json_test_stream_accounting_snapshot(void) noexcept {
  try {
    return {
        live_stream_cursors.load(std::memory_order_acquire),
        live_stream_frames.load(std::memory_order_acquire),
        live_stream_key_bytes.load(std::memory_order_acquire),
        live_stream_owned_plans.load(std::memory_order_acquire),
    };
  } catch (...) {
    return {UINT64_MAX, UINT64_MAX, UINT64_MAX, UINT64_MAX};
  }
}

extern "C" uint32_t simd_json_test_stream_summary_read(
    const simd_json_stream_cursor *cursor,
    simd_json_test_stream_summary *out_summary) noexcept {
  if (cursor == nullptr || out_summary == nullptr) {
    return UINT32_C(0);
  }
  try {
    uint64_t object_segments = 0;
    uint64_t array_segments = 0;
    for (const simd_json_projection_segment &segment :
         cursor->target_segments) {
      if (segment.tag == SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY) {
        ++object_segments;
      } else if (segment.tag == SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX) {
        ++array_segments;
      }
    }
    *out_summary = {
        static_cast<uint64_t>(cursor->target_segments.size()),
        object_segments,
        array_segments,
        static_cast<uint64_t>(cursor->target_key_bytes.size()),
        cursor->row_limit,
        cursor->encoded_byte_limit,
        cursor->parent_generation,
        cursor->current_row_index.load(std::memory_order_acquire),
        cursor->batch_sequence.load(std::memory_order_acquire),
        cursor->state.load(std::memory_order_acquire),
        cursor->projection_plan == nullptr ? UINT32_C(0) : UINT32_C(1),
    };
    return UINT32_C(1);
  } catch (...) {
    return UINT32_C(0);
  }
}

extern "C" uint32_t simd_json_test_stream_state_set(
    simd_json_stream_cursor *cursor,
    simd_json_stream_cursor_state state) noexcept {
  if (cursor == nullptr || state > SIMD_JSON_STREAM_CURSOR_CLOSED) {
    return UINT32_C(0);
  }
  cursor->state.store(state, std::memory_order_release);
  return UINT32_C(1);
}
#endif
