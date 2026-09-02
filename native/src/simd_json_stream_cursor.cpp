#include "../include/simd_json_abi.h"
#include "../vendor/simdjson/simdjson.h"
#include "simd_json_native_internal.hpp"

/* covers: simd_json.stream_cursor.private_abi_v3 simd_json.stream_cursor.opaque_cursor simd_json.stream_cursor.projection_plan_reuse simd_json.stream_cursor.exception_and_failure_cleanup simd_json.native_build_and_abi.opaque_c_contract simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.partial_failure_cleanup */

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <limits>
#include <memory>
#include <new>
#include <stdexcept>
#include <type_traits>
#include <utility>
#include <variant>
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
  for (uint64_t index = 0; index < batch.row_capacity; ++index) {
    batch.rows[index] = simd_json_stream_row{};
  }
  for (uint64_t index = 0; index < batch.slot_capacity; ++index) {
    batch.slots[index] = simd_json_result_slot{};
  }
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

simd_json_stream_status status_from_simdjson(
    simdjson::error_code error,
    uint64_t array_index = SIMD_JSON_ARRAY_INDEX_UNAVAILABLE) noexcept {
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
      code = SIMD_JSON_STATUS_CURSOR_STATE;
      break;
    default:
      code = SIMD_JSON_STATUS_INVALID_JSON;
      break;
  }
  return make_status(code, static_cast<int32_t>(error),
                     SIMD_JSON_BYTE_OFFSET_UNAVAILABLE,
                     SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE, array_index);
}

}  // namespace

struct stream_object_frame {
  simdjson::ondemand::object_iterator position;
  simdjson::ondemand::object_iterator end;
  uint64_t depth;
};

struct stream_array_frame {
  simdjson::ondemand::array_iterator position;
  simdjson::ondemand::array_iterator end;
  uint64_t depth;
};

using stream_parent_frame =
    std::variant<stream_object_frame, stream_array_frame>;

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
  std::atomic<uint64_t> target_lookups{0};
  std::atomic<uint64_t> projection_attempts{0};
  std::atomic<uint64_t> committed_rows{0};
  uint64_t accounted_frames = 0;
  uint64_t accounted_key_bytes = 0;
  bool plan_accounted = false;
  bool target_located = false;
  simdjson::ondemand::array target_array;
  simdjson::ondemand::array_iterator target_position;
  simdjson::ondemand::array_iterator target_end;
  std::vector<simd_json_result_slot> pending_slots;
  uint64_t pending_row_index = 0;
  bool pending_row = false;
  std::vector<stream_parent_frame> parent_frames;

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

namespace {

simd_json_stream_status object_segment(
    simd_json_document *document,
    simdjson::ondemand::object &object,
    const simd_json_projection_segment &segment,
    const std::vector<uint8_t> &key_bytes,
    simdjson::ondemand::value &out,
    std::vector<stream_parent_frame> &frames) {
  const std::string_view wanted{
      reinterpret_cast<const char *>(key_bytes.data() + segment.key_offset),
      static_cast<size_t>(segment.key_length)};
  simdjson::ondemand::object_iterator position;
  simdjson::ondemand::object_iterator end;
  simdjson::error_code error = object.begin().get(position);
  if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  error = object.end().get(end);
  if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  while (position != end) {
    auto field_result = *position;
    simdjson::ondemand::field field;
    error = std::move(field_result).get(field);
    if (error != simdjson::SUCCESS) return status_from_simdjson(error);
    std::string_view key;
    error = field.unescaped_key().get(key);
    if (error != simdjson::SUCCESS) return status_from_simdjson(error);
    if (key == wanted) {
      out = field.value();
      frames.emplace_back(stream_object_frame{
          position, end, static_cast<uint64_t>(frames.size()) + 1});
      return make_status(SIMD_JSON_STATUS_OK);
    }
    simdjson::ondemand::value skipped = field.value();
    const simd_json_projection_status validated =
        simd_json_native::projection_validate_value(document, skipped, 1);
    if (validated.code != SIMD_JSON_STATUS_OK) {
      return make_status(validated.code, validated.native_code,
                         validated.byte_offset, validated.output_slot);
    }
    ++position;
  }
  return make_status(SIMD_JSON_STATUS_MISSING_FIELD);
}

simd_json_stream_status array_segment(
    simd_json_document *document,
    simdjson::ondemand::array &array,
    const simd_json_projection_segment &segment,
    simdjson::ondemand::value &out,
    std::vector<stream_parent_frame> &frames) {
  uint64_t index = 0;
  simdjson::ondemand::array_iterator position;
  simdjson::ondemand::array_iterator end;
  simdjson::error_code error = array.begin().get(position);
  if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  error = array.end().get(end);
  if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  while (position != end) {
    auto child_result = *position;
    simdjson::ondemand::value child;
    error = child_result.get(child);
    if (error != simdjson::SUCCESS) return status_from_simdjson(error);
    if (index == segment.array_index) {
      out = child;
      frames.emplace_back(stream_array_frame{
          position, end, static_cast<uint64_t>(frames.size()) + 1});
      return make_status(SIMD_JSON_STATUS_OK);
    }
    const simd_json_projection_status validated =
        simd_json_native::projection_validate_value(document, child, 1);
    if (validated.code != SIMD_JSON_STATUS_OK) {
      return make_status(validated.code, validated.native_code,
                         validated.byte_offset, validated.output_slot);
    }
    if (index == UINT64_MAX) return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
    ++index;
    ++position;
  }
  return make_status(SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS);
}

simd_json_stream_status locate_target(simd_json_stream_cursor &cursor) {
  cursor.target_lookups.fetch_add(1, std::memory_order_acq_rel);
  simdjson::ondemand::document *document =
      simd_json_native::document_value(cursor.document);
  if (document == nullptr) return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);

  simdjson::error_code error;
  if (cursor.target_segments.empty()) {
    error = document->get_array().get(cursor.target_array);
    if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  } else {
    simdjson::ondemand::value value;
    const auto &first = cursor.target_segments.front();
    if (first.tag == SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY) {
      simdjson::ondemand::object object;
      error = document->get_object().get(object);
      if (error != simdjson::SUCCESS) return status_from_simdjson(error);
      simd_json_stream_status status =
          object_segment(cursor.document, object, first,
                         cursor.target_key_bytes, value,
                         cursor.parent_frames);
      if (status.code != SIMD_JSON_STATUS_OK) return status;
    } else {
      simdjson::ondemand::array array;
      error = document->get_array().get(array);
      if (error != simdjson::SUCCESS) return status_from_simdjson(error);
      simd_json_stream_status status =
          array_segment(cursor.document, array, first, value,
                        cursor.parent_frames);
      if (status.code != SIMD_JSON_STATUS_OK) return status;
    }

    for (size_t index = 1; index < cursor.target_segments.size(); ++index) {
      const auto &segment = cursor.target_segments[index];
      simdjson::ondemand::value next;
      simd_json_stream_status status;
      if (segment.tag == SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY) {
        simdjson::ondemand::object object;
        error = value.get_object().get(object);
        if (error != simdjson::SUCCESS) return status_from_simdjson(error);
        status = object_segment(cursor.document, object, segment,
                                cursor.target_key_bytes, next,
                                cursor.parent_frames);
      } else {
        simdjson::ondemand::array array;
        error = value.get_array().get(array);
        if (error != simdjson::SUCCESS) return status_from_simdjson(error);
        status = array_segment(cursor.document, array, segment, next,
                               cursor.parent_frames);
      }
      if (status.code != SIMD_JSON_STATUS_OK) return status;
      value = next;
    }
    error = value.get_array().get(cursor.target_array);
    if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  }

  error = cursor.target_array.begin().get(cursor.target_position);
  if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  error = cursor.target_array.end().get(cursor.target_end);
  if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  cursor.target_located = true;
  return make_status(SIMD_JSON_STATUS_OK);
}

bool cancellation_requested(
    const simd_json_cancellation_probe *cancellation,
    simd_json_stream_status &status,
    uint64_t array_index = SIMD_JSON_ARRAY_INDEX_UNAVAILABLE) {
  if (cancellation == nullptr) return false;
  const uint32_t cancelled = cancellation->check(cancellation->context);
  if (cancelled == UINT32_C(0)) return false;
  status = cancelled == UINT32_C(1)
               ? make_status(SIMD_JSON_STATUS_CANCELLED,
                             SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
                             SIMD_JSON_BYTE_OFFSET_UNAVAILABLE,
                             SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE, array_index)
               : make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  return true;
}

bool checked_add(uint64_t left, uint64_t right, uint64_t &out) noexcept {
  if (right > UINT64_MAX - left) return false;
  out = left + right;
  return true;
}

bool checked_multiply(uint64_t left, uint64_t right, uint64_t &out) noexcept {
  if (left != 0 && right > UINT64_MAX / left) return false;
  out = left * right;
  return true;
}

simd_json_stream_status project_current_row(simd_json_stream_cursor &cursor) {
  stream_checkpoint();
  cursor.projection_attempts.fetch_add(1, std::memory_order_acq_rel);
  const uint64_t slot_count =
      simd_json_native::projection_output_slots(cursor.projection_plan);
  cursor.pending_slots.assign(static_cast<size_t>(slot_count),
                              simd_json_result_slot{});
  simdjson::ondemand::value row;
  simdjson::error_code error = (*cursor.target_position).get(row);
  if (error != simdjson::SUCCESS) {
    return status_from_simdjson(error, cursor.current_row_index.load());
  }
  const simd_json_projection_status projected =
      simd_json_native::projection_execute_value(
          cursor.document, cursor.projection_plan, row,
          cursor.pending_slots.data(), slot_count);
  if (projected.code != SIMD_JSON_STATUS_OK) {
    return make_status(projected.code, projected.native_code,
                       projected.byte_offset, projected.output_slot,
                       cursor.current_row_index.load());
  }
  cursor.pending_row_index = cursor.current_row_index.load();
  cursor.pending_row = true;
  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_stream_status append_pending_row(
    simd_json_stream_cursor &cursor,
    simd_json_stream_batch_storage &batch,
    const simd_json_cancellation_probe *cancellation,
    bool &fits) {
  stream_checkpoint();
  simd_json_stream_status cancellation_status;
  if (cancellation_requested(cancellation, cancellation_status,
                             cursor.pending_row_index)) {
    return cancellation_status;
  }
  uint64_t string_bytes = 0;
  for (const simd_json_result_slot &slot : cursor.pending_slots) {
    if (slot.tag == SIMD_JSON_RESULT_STRING &&
        !checked_add(string_bytes, slot.value.string.length, string_bytes)) {
      return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY,
                         SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
                         SIMD_JSON_BYTE_OFFSET_UNAVAILABLE,
                         SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE,
                         cursor.pending_row_index);
    }
  }
  uint64_t slot_bytes = 0;
  uint64_t row_bytes = sizeof(simd_json_stream_row);
  if (!checked_multiply(static_cast<uint64_t>(cursor.pending_slots.size()),
                        sizeof(simd_json_result_slot), slot_bytes) ||
      !checked_add(row_bytes, slot_bytes, row_bytes) ||
      !checked_add(row_bytes, string_bytes, row_bytes)) {
    return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY,
                       SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
                       SIMD_JSON_BYTE_OFFSET_UNAVAILABLE,
                       SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE,
                       cursor.pending_row_index);
  }

  uint64_t next_encoded = 0;
  const uint64_t copied_used = batch.encoded_bytes -
      batch.produced_rows * sizeof(simd_json_stream_row) -
      batch.produced_slots * sizeof(simd_json_result_slot);
  fits = checked_add(batch.encoded_bytes, row_bytes, next_encoded) &&
         next_encoded <= cursor.encoded_byte_limit &&
         string_bytes <= batch.copied_byte_capacity - copied_used;
  if (!fits) {
    if (batch.produced_rows == 0) {
      return make_status(SIMD_JSON_STATUS_BATCH_TOO_LARGE,
                         SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
                         SIMD_JSON_BYTE_OFFSET_UNAVAILABLE,
                         SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE,
                         cursor.pending_row_index);
    }
    return make_status(SIMD_JSON_STATUS_OK);
  }

  const uint64_t slot_offset = batch.produced_slots;
  uint64_t byte_offset = copied_used;
  for (size_t index = 0; index < cursor.pending_slots.size(); ++index) {
    if (cancellation_requested(cancellation, cancellation_status,
                               cursor.pending_row_index)) {
      return cancellation_status;
    }
    simd_json_result_slot copied = cursor.pending_slots[index];
    if (copied.tag == SIMD_JSON_RESULT_STRING) {
      const uint64_t length = copied.value.string.length;
      if (length != 0) {
        std::copy_n(copied.value.string.data, static_cast<size_t>(length),
                    batch.copied_bytes + byte_offset);
      }
      copied.value.string.data = batch.copied_bytes + byte_offset;
      byte_offset += length;
    }
    batch.slots[slot_offset + index] = copied;
  }
  batch.rows[batch.produced_rows] = {
      cursor.pending_row_index, slot_offset,
      static_cast<uint64_t>(cursor.pending_slots.size()), row_bytes};
  ++batch.produced_rows;
  batch.produced_slots += static_cast<uint64_t>(cursor.pending_slots.size());
  batch.encoded_bytes = next_encoded;
  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_stream_status validate_source_completion(
    simd_json_stream_cursor &cursor,
    const simd_json_cancellation_probe *cancellation) {
  stream_checkpoint();
  simd_json_stream_status cancellation_status;
  if (cancellation_requested(cancellation, cancellation_status,
                             SIMD_JSON_ARRAY_INDEX_UNAVAILABLE)) {
    return cancellation_status;
  }
  while (!cursor.parent_frames.empty()) {
    stream_parent_frame &parent = cursor.parent_frames.back();
    simd_json_stream_status status = std::visit(
        [&](auto &frame) -> simd_json_stream_status {
          ++frame.position;
          while (frame.position != frame.end) {
            if (cancellation_requested(cancellation, cancellation_status,
                                       SIMD_JSON_ARRAY_INDEX_UNAVAILABLE)) {
              return cancellation_status;
            }
            simdjson::ondemand::value value;
            if constexpr (std::is_same_v<std::decay_t<decltype(frame)>,
                                         stream_object_frame>) {
              simdjson::ondemand::field field;
              simdjson::error_code error =
                  std::move(*frame.position).get(field);
              if (error != simdjson::SUCCESS) return status_from_simdjson(error);
              std::string_view key;
              error = field.unescaped_key().get(key);
              if (error != simdjson::SUCCESS) return status_from_simdjson(error);
              (void)key;
              value = field.value();
            } else {
              simdjson::error_code error = (*frame.position).get(value);
              if (error != simdjson::SUCCESS) return status_from_simdjson(error);
            }
            const simd_json_projection_status validated =
                simd_json_native::projection_validate_value(
                    cursor.document, value, frame.depth + 1);
            if (validated.code != SIMD_JSON_STATUS_OK) {
              return make_status(validated.code, validated.native_code,
                                 validated.byte_offset,
                                 validated.output_slot);
            }
            ++frame.position;
          }
          return make_status(SIMD_JSON_STATUS_OK);
        },
        parent);
    if (status.code != SIMD_JSON_STATUS_OK) return status;
    cursor.parent_frames.pop_back();
  }
  simdjson::ondemand::document *document =
      simd_json_native::document_value(cursor.document);
  if (document == nullptr) return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  return document->at_end() ? make_status(SIMD_JSON_STATUS_OK)
                            : make_status(SIMD_JSON_STATUS_INVALID_JSON);
}

}  // namespace

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
    if (!cursor->target_located) {
      const simd_json_stream_status located = locate_target(*cursor);
      if (located.code != SIMD_JSON_STATUS_OK) {
        cursor->state.store(SIMD_JSON_STREAM_CURSOR_READY,
                            std::memory_order_release);
        return located;
      }
    }
    const uint64_t slot_count =
        simd_json_native::projection_output_slots(cursor->projection_plan);
    uint64_t needed_slots = 0;
    if (slot_count == 0 ||
        !checked_multiply(batch->row_capacity, slot_count, needed_slots) ||
        needed_slots > batch->slot_capacity) {
      cursor->state.store(SIMD_JSON_STREAM_CURSOR_READY,
                          std::memory_order_release);
      return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
    }

    while (batch->produced_rows < batch->row_capacity &&
           batch->produced_rows < cursor->row_limit) {
      simd_json_stream_status cancelled_status;
      if (cancellation_requested(cancellation, cancelled_status,
                                 cursor->current_row_index.load())) {
        clear_batch(*batch);
        cursor->state.store(
            cancelled_status.code == SIMD_JSON_STATUS_CANCELLED
                ? SIMD_JSON_STREAM_CURSOR_CANCELLED
                : SIMD_JSON_STREAM_CURSOR_READY,
            std::memory_order_release);
        return cancelled_status;
      }
      if (!cursor->pending_row && cursor->target_position == cursor->target_end) {
        const simd_json_stream_status completion =
            validate_source_completion(*cursor, cancellation);
        if (completion.code != SIMD_JSON_STATUS_OK) {
          clear_batch(*batch);
          cursor->state.store(SIMD_JSON_STREAM_CURSOR_CANCELLED,
                              std::memory_order_release);
          return completion;
        }
        batch->done = SIMD_JSON_STREAM_DONE;
        cursor->state.store(SIMD_JSON_STREAM_CURSOR_DONE,
                            std::memory_order_release);
        cursor->batch_sequence.fetch_add(1, std::memory_order_acq_rel);
        return make_status(SIMD_JSON_STATUS_OK);
      }
      if (!cursor->pending_row) {
        simd_json_stream_status status = project_current_row(*cursor);
        if (status.code != SIMD_JSON_STATUS_OK) {
          clear_batch(*batch);
          cursor->state.store(SIMD_JSON_STREAM_CURSOR_CANCELLED,
                              std::memory_order_release);
          return status;
        }
      }
      bool fits = false;
      simd_json_stream_status status =
          append_pending_row(*cursor, *batch, cancellation, fits);
      if (status.code != SIMD_JSON_STATUS_OK) {
        clear_batch(*batch);
        cursor->state.store(SIMD_JSON_STREAM_CURSOR_CANCELLED,
                            std::memory_order_release);
        return status;
      }
      if (!fits) break;
      cursor->pending_row = false;
      cursor->pending_slots.clear();
      ++cursor->target_position;
      if (cursor->current_row_index.load() == UINT64_MAX) {
        clear_batch(*batch);
        cursor->state.store(SIMD_JSON_STREAM_CURSOR_CANCELLED,
                            std::memory_order_release);
        return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
      }
      cursor->current_row_index.fetch_add(1, std::memory_order_acq_rel);
      cursor->committed_rows.fetch_add(1, std::memory_order_acq_rel);
    }
    if (!cursor->pending_row && cursor->target_position == cursor->target_end) {
      const simd_json_stream_status completion =
          validate_source_completion(*cursor, cancellation);
      if (completion.code != SIMD_JSON_STATUS_OK) {
        clear_batch(*batch);
        cursor->state.store(SIMD_JSON_STREAM_CURSOR_CANCELLED,
                            std::memory_order_release);
        return completion;
      }
      batch->done = SIMD_JSON_STREAM_DONE;
      cursor->state.store(SIMD_JSON_STREAM_CURSOR_DONE,
                          std::memory_order_release);
    } else {
      cursor->state.store(SIMD_JSON_STREAM_CURSOR_READY,
                          std::memory_order_release);
    }
    cursor->batch_sequence.fetch_add(1, std::memory_order_acq_rel);
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    clear_batch(*batch);
    cursor->state.store(SIMD_JSON_STREAM_CURSOR_CANCELLED,
                        std::memory_order_release);
    const simd_json_stream_status failure = status_from_current_exception();
    return make_status(failure.code, failure.native_code,
                       failure.byte_offset, failure.output_slot,
                       cursor->target_located
                           ? cursor->current_row_index.load(
                                 std::memory_order_acquire)
                           : SIMD_JSON_ARRAY_INDEX_UNAVAILABLE);
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
        cursor->target_lookups.load(std::memory_order_acquire),
        cursor->projection_attempts.load(std::memory_order_acquire),
        cursor->committed_rows.load(std::memory_order_acquire),
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
