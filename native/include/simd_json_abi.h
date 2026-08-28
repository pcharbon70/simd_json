#ifndef SIMD_JSON_ABI_H
#define SIMD_JSON_ABI_H

/* covers: simd_json.native_build_and_abi.opaque_c_contract */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Private Milestone 1 ABI between Zig and the C++ shim.
 *
 * This header is deliberately valid as both C11 and C++17. Callers own every
 * input byte. An input passed to simd_json_document_open must remain allocated
 * and unchanged until the returned document is destroyed. `logical_length`
 * excludes padding; `capacity` includes it. At least
 * SIMD_JSON_REQUIRED_PADDING initialized bytes must follow the logical input.
 */

#define SIMD_JSON_ABI_VERSION UINT32_C(1)
#define SIMD_JSON_REQUIRED_PADDING UINT64_C(64)
#define SIMD_JSON_BYTE_OFFSET_UNAVAILABLE UINT64_MAX
#define SIMD_JSON_NATIVE_CODE_UNAVAILABLE INT32_MIN

typedef int32_t simd_json_status_code;

#define SIMD_JSON_STATUS_OK INT32_C(0)
#define SIMD_JSON_STATUS_INVALID_JSON INT32_C(1)
#define SIMD_JSON_STATUS_INVALID_UTF8 INT32_C(2)
#define SIMD_JSON_STATUS_UNEXPECTED_EOF INT32_C(3)
#define SIMD_JSON_STATUS_OUT_OF_MEMORY INT32_C(4)
#define SIMD_JSON_STATUS_INVALID_ARGUMENT INT32_C(5)
#define SIMD_JSON_STATUS_INTERNAL_FAILURE INT32_C(6)

typedef struct simd_json_parser simd_json_parser;
typedef struct simd_json_document simd_json_document;

typedef struct simd_json_status {
  simd_json_status_code code;
  int32_t native_code;
  uint64_t byte_offset;
} simd_json_status;

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
                            "status layout changed");

#undef SIMD_JSON_ABI_STATIC_ASSERT

#endif
