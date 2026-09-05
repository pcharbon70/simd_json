#ifndef SIMD_JSON_ABI_H
#define SIMD_JSON_ABI_H

/* covers: simd_json.native_build_and_abi.opaque_c_contract */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Private ABI between Zig and the C++ shim.
 *
 * This header is deliberately valid as both C11 and C++17. Callers own every
 * input byte. An input passed to simd_json_document_open must remain allocated
 * and unchanged until the returned document is destroyed. `logical_length`
 * excludes padding; `capacity` includes it. At least
 * SIMD_JSON_REQUIRED_PADDING initialized bytes must follow the logical input.
 */

#define SIMD_JSON_ABI_VERSION UINT32_C(4)
#define SIMD_JSON_REQUIRED_PADDING UINT64_C(64)
#define SIMD_JSON_MAX_DEPTH UINT64_C(1024)
#define SIMD_JSON_BYTE_OFFSET_UNAVAILABLE UINT64_MAX
#define SIMD_JSON_NATIVE_CODE_UNAVAILABLE INT32_MIN
#define SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE UINT32_MAX
#define SIMD_JSON_ARRAY_INDEX_UNAVAILABLE UINT64_MAX
#define SIMD_JSON_STREAM_MAX_BATCH_SIZE UINT64_C(10000)
#define SIMD_JSON_STREAM_MAX_BATCH_BYTES UINT64_C(67108864)
#define SIMD_JSON_DECODE_MAX_CONTAINER_ENTRIES UINT64_C(10000000)
#define SIMD_JSON_DECODE_MAX_STRING_BYTES UINT64_C(67108864)
#define SIMD_JSON_DECODE_MAX_OUTPUT_BYTES UINT64_C(268435456)
#define SIMD_JSON_DECODE_BYTE_RANGE_UNAVAILABLE UINT64_MAX

typedef int32_t simd_json_status_code;

#define SIMD_JSON_STATUS_OK INT32_C(0)
#define SIMD_JSON_STATUS_INVALID_JSON INT32_C(1)
#define SIMD_JSON_STATUS_INVALID_UTF8 INT32_C(2)
#define SIMD_JSON_STATUS_UNEXPECTED_EOF INT32_C(3)
#define SIMD_JSON_STATUS_OUT_OF_MEMORY INT32_C(4)
#define SIMD_JSON_STATUS_INVALID_ARGUMENT INT32_C(5)
#define SIMD_JSON_STATUS_INTERNAL_FAILURE INT32_C(6)
#define SIMD_JSON_STATUS_MISSING_FIELD INT32_C(7)
#define SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS INT32_C(8)
#define SIMD_JSON_STATUS_INCORRECT_TYPE INT32_C(9)
#define SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE INT32_C(10)
#define SIMD_JSON_STATUS_CURSOR_CONSUMED INT32_C(11)
#define SIMD_JSON_STATUS_CANCELLED INT32_C(12)
#define SIMD_JSON_STATUS_BATCH_TOO_LARGE INT32_C(13)
#define SIMD_JSON_STATUS_CURSOR_STATE INT32_C(14)
#define SIMD_JSON_STATUS_MAX_DEPTH_EXCEEDED INT32_C(15)
#define SIMD_JSON_STATUS_MAX_CONTAINER_ENTRIES_EXCEEDED INT32_C(16)
#define SIMD_JSON_STATUS_MAX_STRING_BYTES_EXCEEDED INT32_C(17)
#define SIMD_JSON_STATUS_MAX_OUTPUT_BYTES_EXCEEDED INT32_C(18)

typedef struct simd_json_parser simd_json_parser;
typedef struct simd_json_document simd_json_document;
typedef struct simd_json_projection_plan simd_json_projection_plan;
typedef struct simd_json_stream_cursor simd_json_stream_cursor;
typedef struct simd_json_decode_materializer simd_json_decode_materializer;
typedef struct simd_json_decode_result simd_json_decode_result;

typedef struct simd_json_status {
  simd_json_status_code code;
  int32_t native_code;
  uint64_t byte_offset;
} simd_json_status;

/*
 * Projection functions extend the unchanged Milestone 1 status layout with a
 * failing output slot. The sentinel is used when failure is not slot-specific.
 */
typedef struct simd_json_projection_status {
  simd_json_status_code code;
  int32_t native_code;
  uint64_t byte_offset;
  uint32_t output_slot;
  uint32_t reserved;
} simd_json_projection_status;

typedef uint32_t simd_json_projection_segment_tag;

#define SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY UINT32_C(1)
#define SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX UINT32_C(2)

/*
 * Each entry associates one caller-owned output slot with one non-empty range
 * in the shared segment array. Multiple entries may reference the exact same
 * range. `reserved` must be zero.
 */
typedef struct simd_json_projection_entry {
  uint32_t output_slot;
  uint32_t reserved;
  uint64_t segment_offset;
  uint64_t segment_count;
} simd_json_projection_entry;

/*
 * OBJECT_KEY uses `key_offset` and `key_length` in the caller-owned byte arena
 * and requires `array_index` to be zero. ARRAY_INDEX uses `array_index` and
 * requires both key fields to be zero. `reserved` must always be zero.
 */
typedef struct simd_json_projection_segment {
  simd_json_projection_segment_tag tag;
  uint32_t reserved;
  uint64_t key_offset;
  uint64_t key_length;
  uint64_t array_index;
} simd_json_projection_segment;

typedef uint32_t simd_json_result_tag;

#define SIMD_JSON_RESULT_EMPTY UINT32_C(0)
#define SIMD_JSON_RESULT_SIGNED_INTEGER UINT32_C(1)
#define SIMD_JSON_RESULT_UNSIGNED_INTEGER UINT32_C(2)
#define SIMD_JSON_RESULT_DOUBLE UINT32_C(3)
#define SIMD_JSON_RESULT_BOOLEAN UINT32_C(4)
#define SIMD_JSON_RESULT_NULL UINT32_C(5)
#define SIMD_JSON_RESULT_STRING UINT32_C(6)

typedef struct simd_json_borrowed_string {
  const uint8_t *data;
  uint64_t length;
} simd_json_borrowed_string;

typedef union simd_json_result_value {
  int64_t signed_integer;
  uint64_t unsigned_integer;
  double floating_point;
  uint64_t boolean;
  simd_json_borrowed_string string;
} simd_json_result_value;

/*
 * Result slots are caller-owned and valid only for the duration of one execute
 * operation. A STRING pointer borrows document storage and must be copied
 * before the executing document or operation-owned slot storage is released.
 * `reserved` must be zero on input and remains zero on output.
 */
typedef struct simd_json_result_slot {
  simd_json_result_tag tag;
  uint32_t reserved;
  simd_json_result_value value;
} simd_json_result_slot;

/*
 * A stream target reuses the projection segment tags and byte-arena ranges.
 * Root arrays use a NULL/zero segment pair and a NULL/zero key-byte pair.
 * Non-root descriptors and every referenced byte range remain caller-owned
 * only for the duration of cursor construction.
 */
typedef struct simd_json_stream_target {
  const simd_json_projection_segment *segments;
  uint64_t segment_count;
  const uint8_t *key_bytes;
  uint64_t key_bytes_length;
} simd_json_stream_target;

/*
 * Cursor construction consumes `projection_plan` only when ownership has
 * transferred to a cursor or to constructor rollback. The field is cleared at
 * that transfer point. `parent_generation` must be non-zero and `reserved`
 * must be zero. Public option maxima are frozen at this ABI boundary.
 */
typedef struct simd_json_stream_cursor_config {
  simd_json_projection_plan *projection_plan;
  uint64_t row_limit;
  uint64_t encoded_byte_limit;
  uint64_t parent_generation;
  uint64_t reserved;
} simd_json_stream_cursor_config;

typedef uint32_t (*simd_json_cancellation_check)(void *context);

typedef struct simd_json_cancellation_probe {
  void *context;
  simd_json_cancellation_check check;
} simd_json_cancellation_probe;

typedef struct simd_json_stream_row {
  uint64_t array_index;
  uint64_t slot_offset;
  uint64_t slot_count;
  uint64_t encoded_bytes;
} simd_json_stream_row;

/*
 * Batch storage is caller-owned. Phase 3 will populate rows, typed slots, and
 * copied bytes transactionally. Counts, encoded bytes, and done are cleared on
 * entry; `reserved` must always be zero.
 */
typedef struct simd_json_stream_batch_storage {
  simd_json_stream_row *rows;
  uint64_t row_capacity;
  simd_json_result_slot *slots;
  uint64_t slot_capacity;
  uint8_t *copied_bytes;
  uint64_t copied_byte_capacity;
  uint64_t produced_rows;
  uint64_t produced_slots;
  uint64_t encoded_bytes;
  uint32_t done;
  uint32_t reserved;
} simd_json_stream_batch_storage;

/*
 * Stream status preserves the projection status prefix and adds one checked
 * source-array index. The unavailable sentinel is used for target, document,
 * cursor-state, and other failures that are not row-specific.
 */
typedef struct simd_json_stream_status {
  simd_json_status_code code;
  int32_t native_code;
  uint64_t byte_offset;
  uint32_t output_slot;
  uint32_t reserved;
  uint64_t array_index;
} simd_json_stream_status;

typedef uint32_t simd_json_stream_done;

#define SIMD_JSON_STREAM_NOT_DONE UINT32_C(0)
#define SIMD_JSON_STREAM_DONE UINT32_C(1)

typedef uint32_t simd_json_stream_cursor_state;

#define SIMD_JSON_STREAM_CURSOR_READY UINT32_C(0)
#define SIMD_JSON_STREAM_CURSOR_RUNNING UINT32_C(1)
#define SIMD_JSON_STREAM_CURSOR_DONE UINT32_C(2)
#define SIMD_JSON_STREAM_CURSOR_CANCELLED UINT32_C(3)
#define SIMD_JSON_STREAM_CURSOR_CLOSED UINT32_C(4)

typedef uint32_t simd_json_decode_node_tag;

#define SIMD_JSON_DECODE_NODE_OBJECT UINT32_C(1)
#define SIMD_JSON_DECODE_NODE_ARRAY UINT32_C(2)
#define SIMD_JSON_DECODE_NODE_STRING UINT32_C(3)
#define SIMD_JSON_DECODE_NODE_SIGNED_INTEGER UINT32_C(4)
#define SIMD_JSON_DECODE_NODE_UNSIGNED_INTEGER UINT32_C(5)
#define SIMD_JSON_DECODE_NODE_DOUBLE UINT32_C(6)
#define SIMD_JSON_DECODE_NODE_TRUE UINT32_C(7)
#define SIMD_JSON_DECODE_NODE_FALSE UINT32_C(8)
#define SIMD_JSON_DECODE_NODE_NULL UINT32_C(9)

typedef struct simd_json_decode_byte_range {
  uint64_t offset;
  uint64_t length;
} simd_json_decode_byte_range;

typedef union simd_json_decode_node_value {
  int64_t signed_integer;
  uint64_t unsigned_integer;
  double floating_point;
  simd_json_decode_byte_range bytes;
} simd_json_decode_node_value;

/* Container nodes name a contiguous edge range; strings name copied bytes. */
typedef struct simd_json_decode_node {
  simd_json_decode_node_tag tag;
  uint32_t reserved;
  uint64_t edge_offset;
  uint64_t edge_count;
  simd_json_decode_node_value value;
} simd_json_decode_node;

/* Array edges use unavailable key offset/length and object edges name a key. */
typedef struct simd_json_decode_edge {
  uint64_t key_offset;
  uint64_t key_length;
  uint64_t value_node;
  uint64_t reserved;
} simd_json_decode_edge;

typedef struct simd_json_decode_config {
  uint64_t max_depth;
  uint64_t max_container_entries;
  uint64_t max_string_bytes;
  uint64_t max_output_bytes;
  uint64_t reserved;
} simd_json_decode_config;

/* All pointers borrow immutable result-owned storage until result destruction. */
typedef struct simd_json_decode_result_view {
  const simd_json_decode_node *nodes;
  uint64_t node_count;
  const simd_json_decode_edge *edges;
  uint64_t edge_count;
  const uint8_t *copied_bytes;
  uint64_t copied_byte_count;
  uint64_t root_node;
  uint64_t reserved;
} simd_json_decode_result_view;

#if defined(_WIN32) && defined(SIMD_JSON_ABI_BUILD_SHARED)
#define SIMD_JSON_ABI_EXPORT __declspec(dllexport)
#elif defined(SIMD_JSON_ABI_BUILD_SHARED) && defined(__GNUC__)
#define SIMD_JSON_ABI_EXPORT __attribute__((visibility("default")))
#else
#define SIMD_JSON_ABI_EXPORT
#endif

#ifdef __cplusplus
#define SIMD_JSON_ABI_NOEXCEPT noexcept
#else
#define SIMD_JSON_ABI_NOEXCEPT
#endif

/*
 * On every return, `out_parser` is either NULL or points to one owned parser.
 * Passing NULL for `out_parser` returns INVALID_ARGUMENT.
 */
SIMD_JSON_ABI_EXPORT simd_json_status
simd_json_parser_create(simd_json_parser **out_parser) SIMD_JSON_ABI_NOEXCEPT;

/* NULL is accepted. A parser must outlive all documents opened through it. */
SIMD_JSON_ABI_EXPORT void
simd_json_parser_destroy(simd_json_parser *parser) SIMD_JSON_ABI_NOEXCEPT;

/*
 * On every return, `out_document` is either NULL or points to one owned
 * document. `parser`, `data`, and `out_document` must be non-NULL. Capacity
 * must cover logical_length plus SIMD_JSON_REQUIRED_PADDING without overflow.
 * Available byte offsets are relative to `data` and never include padding.
 */
SIMD_JSON_ABI_EXPORT simd_json_status simd_json_document_open(
    simd_json_parser *parser,
    const uint8_t *data,
    uint64_t logical_length,
    uint64_t capacity,
    simd_json_document **out_document) SIMD_JSON_ABI_NOEXCEPT;

/* NULL is accepted. The caller must clear a consumed non-NULL handle. */
SIMD_JSON_ABI_EXPORT void
simd_json_document_destroy(simd_json_document *document) SIMD_JSON_ABI_NOEXCEPT;

/*
 * Compiles all entries into one immutable prefix-sharing plan. The constructor
 * validates the complete descriptor set before retaining data, copies every
 * object-key byte it needs, and always clears `out_plan` before returning.
 * Entries must use unique output slots in [0, entry_count). All pointer/count
 * pairs must be representable by the host, and every path must be non-empty.
 */
SIMD_JSON_ABI_EXPORT simd_json_projection_status simd_json_projection_plan_create(
    const simd_json_projection_entry *entries,
    uint64_t entry_count,
    const simd_json_projection_segment *segments,
    uint64_t segment_count,
    const uint8_t *key_bytes,
    uint64_t key_bytes_length,
    simd_json_projection_plan **out_plan) SIMD_JSON_ABI_NOEXCEPT;

/* NULL is accepted. A plan is operation-scoped and has exactly one owner. */
SIMD_JSON_ABI_EXPORT void simd_json_projection_plan_destroy(
    simd_json_projection_plan *plan) SIMD_JSON_ABI_NOEXCEPT;

/*
 * Executes a compiled plan once in source order and publishes caller-owned
 * typed slots only after the complete logical document validates. Every
 * failure clears all slots; a second cursor claim returns CURSOR_CONSUMED.
 */
SIMD_JSON_ABI_EXPORT simd_json_projection_status simd_json_projection_execute(
    simd_json_document *document,
    const simd_json_projection_plan *plan,
    simd_json_result_slot *result_slots,
    uint64_t result_slot_count) SIMD_JSON_ABI_NOEXCEPT;

/*
 * Constructs an opaque parent-borrowing cursor owner without locating or
 * advancing the target. On transfer, `config->projection_plan` is cleared and
 * exactly one cursor or rollback path owns it. `out_cursor` is always cleared
 * before validation.
 */
SIMD_JSON_ABI_EXPORT simd_json_stream_status simd_json_stream_cursor_create(
    simd_json_document *document,
    const simd_json_stream_target *target,
    simd_json_stream_cursor_config *config,
    simd_json_stream_cursor **out_cursor) SIMD_JSON_ABI_NOEXCEPT;

/* NULL is accepted. The owning layer must prevent destruction while running. */
SIMD_JSON_ABI_EXPORT void simd_json_stream_cursor_destroy(
    simd_json_stream_cursor *cursor) SIMD_JSON_ABI_NOEXCEPT;

/*
 * Reserved ABI v3 batch boundary. Phase 2 validates cursor state,
 * cancellation, and bounded caller storage but intentionally performs no
 * target or row traversal. Phase 3 will populate the frozen storage layout.
 */
SIMD_JSON_ABI_EXPORT simd_json_stream_status simd_json_stream_next_batch(
    simd_json_stream_cursor *cursor,
    const simd_json_cancellation_probe *cancellation,
    simd_json_stream_batch_storage *batch) SIMD_JSON_ABI_NOEXCEPT;

/*
 * Constructs an operation-scoped iterative materializer. The document remains
 * caller-owned and must outlive the materializer. `out_materializer` is always
 * cleared before validation and receives the only owner on success.
 */
SIMD_JSON_ABI_EXPORT simd_json_status simd_json_decode_materializer_create(
    simd_json_document *document,
    const simd_json_decode_config *config,
    simd_json_decode_materializer **out_materializer) SIMD_JSON_ABI_NOEXCEPT;

/* NULL is accepted. A materializer may publish at most one result. */
SIMD_JSON_ABI_EXPORT void simd_json_decode_materializer_destroy(
    simd_json_decode_materializer *materializer) SIMD_JSON_ABI_NOEXCEPT;

/*
 * Builds privately and publishes only a complete owned result. On every
 * failure `out_result` is NULL. Phase 3 supplies value traversal.
 */
SIMD_JSON_ABI_EXPORT simd_json_status simd_json_decode_materializer_execute(
    simd_json_decode_materializer *materializer,
    const simd_json_cancellation_probe *cancellation,
    simd_json_decode_result **out_result) SIMD_JSON_ABI_NOEXCEPT;

/* Returns an immutable borrowed graph view; the output is cleared on failure. */
SIMD_JSON_ABI_EXPORT simd_json_status simd_json_decode_result_read(
    const simd_json_decode_result *result,
    simd_json_decode_result_view *out_view) SIMD_JSON_ABI_NOEXCEPT;

/* NULL is accepted. Every graph allocation is released exactly once. */
SIMD_JSON_ABI_EXPORT void simd_json_decode_result_destroy(
    simd_json_decode_result *result) SIMD_JSON_ABI_NOEXCEPT;

#undef SIMD_JSON_ABI_EXPORT
#undef SIMD_JSON_ABI_NOEXCEPT

#ifdef __cplusplus
}
#endif

#if defined(__cplusplus)
#define SIMD_JSON_ABI_STATIC_ASSERT(condition, message) static_assert(condition, message)
#else
#define SIMD_JSON_ABI_STATIC_ASSERT(condition, message) _Static_assert(condition, message)
#endif

SIMD_JSON_ABI_STATIC_ASSERT(sizeof(uint8_t) == 1, "uint8_t must be one byte");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(int32_t) == 4, "int32_t must be four bytes");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(uint32_t) == 4, "uint32_t must be four bytes");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(uint64_t) == 8, "uint64_t must be eight bytes");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_status_code) == 4,
                            "status codes must be four bytes");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_status, code) == 0,
                            "status code layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_status, native_code) == 4,
                            "native code layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_status, byte_offset) == 8,
                            "byte offset layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_status) == 16,
                            "Milestone 1 status layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_status, code) == 0,
                            "projection status code layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_status, native_code) == 4,
                            "projection native code layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_status, byte_offset) == 8,
                            "projection byte offset layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_status, output_slot) == 16,
                            "output slot layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_status, reserved) == 20,
                            "status reserved layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_projection_status) == 24,
                            "projection status layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_projection_segment_tag) == 4,
                            "projection segment tags must be four bytes");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_entry, output_slot) == 0,
                            "projection entry slot layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_entry, reserved) == 4,
                            "projection entry reserved layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_entry, segment_offset) == 8,
                            "projection entry offset layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_entry, segment_count) == 16,
                            "projection entry count layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_projection_entry) == 24,
                            "projection entry layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_segment, tag) == 0,
                            "projection segment tag layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_segment, reserved) == 4,
                            "projection segment reserved layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_segment, key_offset) == 8,
                            "projection segment key offset layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_segment, key_length) == 16,
                            "projection segment key length layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_projection_segment, array_index) == 24,
                            "projection segment index layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_projection_segment) == 32,
                            "projection segment layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_result_tag) == 4,
                            "result tags must be four bytes");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_borrowed_string, data) == 0,
                            "borrowed string pointer layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_borrowed_string, length) == 8,
                            "borrowed string length layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_borrowed_string) == 16,
                            "borrowed string layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_result_value) == 16,
                            "result value layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_result_slot, tag) == 0,
                            "result slot tag layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_result_slot, reserved) == 4,
                            "result slot reserved layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_result_slot, value) == 8,
                            "result slot value layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_result_slot) == 24,
                            "result slot layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(SIMD_JSON_ABI_VERSION == UINT32_C(4),
                            "private ABI version changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(void *) == 8,
                            "ABI v4 requires 64-bit data pointers");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_cancellation_check) == 8,
                            "ABI v4 requires 64-bit function pointers");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_target, segments) == 0,
                            "stream target segment pointer layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_target, segment_count) == 8,
                            "stream target segment count layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_target, key_bytes) == 16,
                            "stream target key pointer layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_target, key_bytes_length) == 24,
                            "stream target key length layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_stream_target) == 32,
                            "stream target layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_cursor_config, projection_plan) == 0,
                            "stream cursor plan layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_cursor_config, row_limit) == 8,
                            "stream cursor row limit layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_cursor_config, encoded_byte_limit) == 16,
                            "stream cursor byte limit layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_cursor_config, parent_generation) == 24,
                            "stream cursor generation layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_cursor_config, reserved) == 32,
                            "stream cursor reserved layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_stream_cursor_config) == 40,
                            "stream cursor config layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_cancellation_probe, context) == 0,
                            "cancellation context layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_cancellation_probe, check) == 8,
                            "cancellation callback layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_cancellation_probe) == 16,
                            "cancellation probe layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_row, array_index) == 0,
                            "stream row index layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_row, slot_offset) == 8,
                            "stream row slot offset layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_row, slot_count) == 16,
                            "stream row slot count layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_row, encoded_bytes) == 24,
                            "stream row byte layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_stream_row) == 32,
                            "stream row layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, rows) == 0,
                            "stream batch rows layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, row_capacity) == 8,
                            "stream batch row capacity layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, slots) == 16,
                            "stream batch slots layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, slot_capacity) == 24,
                            "stream batch slot capacity layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, copied_bytes) == 32,
                            "stream batch byte pointer layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, copied_byte_capacity) == 40,
                            "stream batch byte capacity layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, produced_rows) == 48,
                            "stream batch produced rows layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, produced_slots) == 56,
                            "stream batch produced slots layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, encoded_bytes) == 64,
                            "stream batch encoded bytes layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, done) == 72,
                            "stream batch done layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_batch_storage, reserved) == 76,
                            "stream batch reserved layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_stream_batch_storage) == 80,
                            "stream batch storage layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_status, code) == 0,
                            "stream status code layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_status, native_code) == 4,
                            "stream native code layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_status, byte_offset) == 8,
                            "stream byte offset layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_status, output_slot) == 16,
                            "stream output slot layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_status, reserved) == 20,
                            "stream status reserved layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_stream_status, array_index) == 24,
                            "stream array index layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_stream_status) == 32,
                            "stream status layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_decode_node_tag) == 4,
                            "decode node tags must be four bytes");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_decode_byte_range) == 16,
                            "decode byte range layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_decode_node_value) == 16,
                            "decode node value layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_decode_node, tag) == 0,
                            "decode node tag layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_decode_node, edge_offset) == 8,
                            "decode node edge offset layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_decode_node, value) == 24,
                            "decode node value layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_decode_node) == 40,
                            "decode node layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_decode_edge) == 32,
                            "decode edge layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_decode_config) == 40,
                            "decode config layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_decode_result_view, nodes) == 0,
                            "decode view node pointer layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_decode_result_view, edges) == 16,
                            "decode view edge pointer layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_decode_result_view, copied_bytes) == 32,
                            "decode view byte pointer layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(offsetof(simd_json_decode_result_view, root_node) == 48,
                            "decode view root layout changed");
SIMD_JSON_ABI_STATIC_ASSERT(sizeof(simd_json_decode_result_view) == 64,
                            "decode result view layout changed");

#undef SIMD_JSON_ABI_STATIC_ASSERT

#endif
