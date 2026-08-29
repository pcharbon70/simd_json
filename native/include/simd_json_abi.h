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

#define SIMD_JSON_ABI_VERSION UINT32_C(2)
#define SIMD_JSON_REQUIRED_PADDING UINT64_C(64)
#define SIMD_JSON_BYTE_OFFSET_UNAVAILABLE UINT64_MAX
#define SIMD_JSON_NATIVE_CODE_UNAVAILABLE INT32_MIN
#define SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE UINT32_MAX

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

typedef struct simd_json_parser simd_json_parser;
typedef struct simd_json_document simd_json_document;
typedef struct simd_json_projection_plan simd_json_projection_plan;

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
 * Executes a compiled plan into caller-owned slots. Phase 2 freezes this
 * signature and slot lifetime; traversal behavior is implemented in Phase 3.
 */
SIMD_JSON_ABI_EXPORT simd_json_projection_status simd_json_projection_execute(
    simd_json_document *document,
    const simd_json_projection_plan *plan,
    simd_json_result_slot *result_slots,
    uint64_t result_slot_count) SIMD_JSON_ABI_NOEXCEPT;

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

#undef SIMD_JSON_ABI_STATIC_ASSERT

#endif
