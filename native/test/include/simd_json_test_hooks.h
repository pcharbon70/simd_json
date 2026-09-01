#ifndef SIMD_JSON_TEST_HOOKS_H
#define SIMD_JSON_TEST_HOOKS_H

#include "simd_json_abi.h"

#ifndef SIMD_JSON_TESTING
#error "simd_json_test_hooks.h is available only to native test builds"
#endif

#ifdef __cplusplus
extern "C" {
#define SIMD_JSON_TEST_NOEXCEPT noexcept
#else
#define SIMD_JSON_TEST_NOEXCEPT
#endif

#define SIMD_JSON_TEST_POINT_BEFORE_PARSER_ALLOCATION INT32_C(1)
#define SIMD_JSON_TEST_POINT_AFTER_PARSER_ALLOCATION INT32_C(2)
#define SIMD_JSON_TEST_POINT_DURING_DOCUMENT_CONSTRUCTION INT32_C(3)
#define SIMD_JSON_TEST_POINT_BEFORE_DOCUMENT_PUBLICATION INT32_C(4)

#define SIMD_JSON_TEST_FAILURE_SIMDJSON INT32_C(1)
#define SIMD_JSON_TEST_FAILURE_BAD_ALLOC INT32_C(2)
#define SIMD_JSON_TEST_FAILURE_STANDARD INT32_C(3)
#define SIMD_JSON_TEST_FAILURE_UNKNOWN INT32_C(4)

typedef struct simd_json_test_projection_accounting {
  uint64_t live_plans;
  uint64_t live_nodes;
  uint64_t live_key_bytes;
} simd_json_test_projection_accounting;

typedef struct simd_json_test_projection_summary {
  uint64_t output_slots;
  uint64_t nodes;
  uint64_t object_edges;
  uint64_t array_edges;
  uint64_t terminals;
  uint64_t key_bytes;
  uint64_t maximum_depth;
  uint64_t topology_hash;
} simd_json_test_projection_summary;

typedef struct simd_json_test_projection_execution_summary {
  uint64_t compilation_nanoseconds;
  uint64_t traversal_nanoseconds;
  uint64_t execution_entries;
  uint64_t visited_nodes;
  uint64_t shared_prefix_visits;
  uint64_t filled_slots;
  uint64_t object_fields;
  uint64_t array_elements;
  uint64_t skipped_values;
  uint64_t cancellation_checks;
} simd_json_test_projection_execution_summary;

typedef struct simd_json_test_stream_accounting {
  uint64_t live_cursors;
  uint64_t live_frames;
  uint64_t live_key_bytes;
  uint64_t live_owned_plans;
} simd_json_test_stream_accounting;

typedef struct simd_json_test_stream_summary {
  uint64_t target_segments;
  uint64_t object_segments;
  uint64_t array_segments;
  uint64_t key_bytes;
  uint64_t row_limit;
  uint64_t encoded_byte_limit;
  uint64_t parent_generation;
  uint64_t current_row_index;
  uint64_t batch_sequence;
  uint32_t state;
  uint32_t owns_projection_plan;
} simd_json_test_stream_summary;

void simd_json_test_inject_failure(int32_t point,
                                   int32_t kind) SIMD_JSON_TEST_NOEXCEPT;
void simd_json_test_clear_failure(void) SIMD_JSON_TEST_NOEXCEPT;
uint64_t simd_json_test_live_parser_count(void) SIMD_JSON_TEST_NOEXCEPT;
uint64_t simd_json_test_live_document_count(void) SIMD_JSON_TEST_NOEXCEPT;
uint32_t simd_json_test_document_uses_input(
    simd_json_document *document,
    const uint8_t *data,
    uint64_t logical_length) SIMD_JSON_TEST_NOEXCEPT;
simd_json_status simd_json_test_document_revalidate(
    simd_json_document *document) SIMD_JSON_TEST_NOEXCEPT;
simd_json_status simd_json_test_document_open_unvalidated(
    simd_json_parser *parser,
    const uint8_t *data,
    uint64_t logical_length,
    uint64_t capacity,
    simd_json_document **out_document) SIMD_JSON_TEST_NOEXCEPT;
uint32_t simd_json_test_sanitizer_build(void) SIMD_JSON_TEST_NOEXCEPT;
void simd_json_test_projection_inject_failure(
    uint64_t successful_checkpoints,
    int32_t kind) SIMD_JSON_TEST_NOEXCEPT;
void simd_json_test_projection_clear_failure(void) SIMD_JSON_TEST_NOEXCEPT;
simd_json_test_projection_accounting simd_json_test_projection_accounting_snapshot(
    void) SIMD_JSON_TEST_NOEXCEPT;
uint32_t simd_json_test_projection_summary_read(
    const simd_json_projection_plan *plan,
    simd_json_test_projection_summary *out_summary) SIMD_JSON_TEST_NOEXCEPT;
uint32_t simd_json_test_projection_execution_summary_read(
    const simd_json_projection_plan *plan,
    simd_json_test_projection_execution_summary *out_summary)
    SIMD_JSON_TEST_NOEXCEPT;
void simd_json_test_stream_inject_failure(
    uint64_t successful_checkpoints,
    int32_t kind) SIMD_JSON_TEST_NOEXCEPT;
void simd_json_test_stream_clear_failure(void) SIMD_JSON_TEST_NOEXCEPT;
simd_json_test_stream_accounting simd_json_test_stream_accounting_snapshot(
    void) SIMD_JSON_TEST_NOEXCEPT;
uint32_t simd_json_test_stream_summary_read(
    const simd_json_stream_cursor *cursor,
    simd_json_test_stream_summary *out_summary) SIMD_JSON_TEST_NOEXCEPT;
uint32_t simd_json_test_stream_state_set(
    simd_json_stream_cursor *cursor,
    simd_json_stream_cursor_state state) SIMD_JSON_TEST_NOEXCEPT;

#undef SIMD_JSON_TEST_NOEXCEPT

#ifdef __cplusplus
}
#endif

#endif
