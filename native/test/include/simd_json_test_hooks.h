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

void simd_json_test_inject_failure(int32_t point,
                                   int32_t kind) SIMD_JSON_TEST_NOEXCEPT;
void simd_json_test_clear_failure(void) SIMD_JSON_TEST_NOEXCEPT;
uint64_t simd_json_test_live_parser_count(void) SIMD_JSON_TEST_NOEXCEPT;
uint64_t simd_json_test_live_document_count(void) SIMD_JSON_TEST_NOEXCEPT;

#undef SIMD_JSON_TEST_NOEXCEPT

#ifdef __cplusplus
}
#endif

#endif
