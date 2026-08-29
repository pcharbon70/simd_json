#include "simd_json_abi.h"
#include "simd_json_test_hooks.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* covers: simd_json.native_build_and_abi.c_abi_conformance simd_json.native_build_and_abi.cpp_exception_translation simd_json.native_build_and_abi.partial_failure_cleanup */

#define CHECK(condition)                                                      \
  do {                                                                        \
    if (!(condition)) {                                                       \
      fprintf(stderr, "C ABI conformance failure at line %d\n", __LINE__);    \
      return 1;                                                               \
    }                                                                         \
  } while (0)

#define RANDOMIZED_CASES 512U

static uint64_t randomized_seed(void) {
  const char *configured = getenv("SIMD_JSON_QUALIFICATION_SEED");
  char *end = NULL;
  uint64_t seed;

  if (configured == NULL || configured[0] == '\0') {
    return UINT64_C(260829001);
  }

  seed = strtoull(configured, &end, 10);
  if (end == configured || *end != '\0' || seed == 0) {
    fprintf(stderr, "invalid SIMD_JSON_QUALIFICATION_SEED: %s\n", configured);
    exit(2);
  }

  return seed;
}

static uint64_t next_random(uint64_t *state) {
  uint64_t value = *state;

  value ^= value << 13;
  value ^= value >> 7;
  value ^= value << 17;
  *state = value;
  return value;
}

static uint8_t *padded_copy(const uint8_t *input,
                            uint64_t logical_length,
                            uint64_t *capacity) {
  uint8_t *copy;

  if (logical_length > UINT64_MAX - SIMD_JSON_REQUIRED_PADDING) {
    return NULL;
  }

  *capacity = logical_length + SIMD_JSON_REQUIRED_PADDING;
  copy = (uint8_t *)calloc((size_t)*capacity, 1);

  if (copy != NULL && logical_length != 0) {
    memcpy(copy, input, (size_t)logical_length);
  }

  return copy;
}

static int status_has_safe_metadata(simd_json_status status,
                                    uint64_t logical_length) {
  if (status.byte_offset != SIMD_JSON_BYTE_OFFSET_UNAVAILABLE &&
      status.byte_offset > logical_length) {
    return 0;
  }

  if (status.code == SIMD_JSON_STATUS_OK) {
    return status.native_code == SIMD_JSON_NATIVE_CODE_UNAVAILABLE &&
           status.byte_offset == SIMD_JSON_BYTE_OFFSET_UNAVAILABLE;
  }

  return 1;
}

static int expect_input(const uint8_t *input,
                        uint64_t logical_length,
                        simd_json_status_code expected) {
  uint64_t capacity = 0;
  uint8_t *copy = padded_copy(input, logical_length, &capacity);
  simd_json_parser *parser = NULL;
  simd_json_document *document = NULL;
  simd_json_status status;

  CHECK(copy != NULL);
  status = simd_json_parser_create(&parser);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(parser != NULL);
  CHECK(status_has_safe_metadata(status, logical_length));

  document = (simd_json_document *)(uintptr_t)1;
  status = simd_json_document_open(parser, copy, logical_length, capacity,
                                   &document);
  CHECK(status.code == expected);
  CHECK(status_has_safe_metadata(status, logical_length));

  if (expected == SIMD_JSON_STATUS_OK) {
    CHECK(document != NULL);
    simd_json_document_destroy(document);
    document = NULL;
    simd_json_document_destroy(document);
  } else {
    CHECK(document == NULL);
    CHECK(status.native_code != SIMD_JSON_NATIVE_CODE_UNAVAILABLE);
  }

  simd_json_parser_destroy(parser);
  parser = NULL;
  simd_json_parser_destroy(parser);
  free(copy);

  CHECK(simd_json_test_live_parser_count() == 0);
  CHECK(simd_json_test_live_document_count() == 0);
  return 0;
}

static int valid_input_matrix(void) {
  static const char *inputs[] = {
      "{\"nested\":[1,true,null,\"ok\"]}",
      "[1,{\"two\":2},false]",
      "\"top-level string\"",
      "-12.5e+2",
      "true",
      "false",
      "null",
  };
  size_t index;

  for (index = 0; index < sizeof(inputs) / sizeof(inputs[0]); ++index) {
    CHECK(expect_input((const uint8_t *)inputs[index], strlen(inputs[index]),
                       SIMD_JSON_STATUS_OK) == 0);
  }

  return 0;
}

static int malformed_input_matrix(void) {
  static const uint8_t invalid_utf8[] = {'"', 0xc3, 0x28, '"'};
  static const uint8_t embedded_null[] = {'"', 'a', 0x00, 'b', '"'};

  CHECK(expect_input((const uint8_t *)"", 0,
                     SIMD_JSON_STATUS_UNEXPECTED_EOF) == 0);
  CHECK(expect_input((const uint8_t *)" \t\r\n", 4,
                     SIMD_JSON_STATUS_UNEXPECTED_EOF) == 0);
  CHECK(expect_input((const uint8_t *)"[1,", 3,
                     SIMD_JSON_STATUS_UNEXPECTED_EOF) == 0);
  CHECK(expect_input((const uint8_t *)"{\"a\":1,}", 8,
                     SIMD_JSON_STATUS_INVALID_JSON) == 0);
  CHECK(expect_input(invalid_utf8, sizeof(invalid_utf8),
                     SIMD_JSON_STATUS_INVALID_UTF8) == 0);
  CHECK(expect_input(embedded_null, sizeof(embedded_null),
                     SIMD_JSON_STATUS_INVALID_JSON) == 0);
  return 0;
}

static int invalid_argument_matrix(void) {
  static const uint8_t input[] = "null";
  uint64_t capacity = 0;
  uint8_t *copy = padded_copy(input, sizeof(input) - 1, &capacity);
  simd_json_parser *parser = NULL;
  simd_json_document *document;
  simd_json_status status;

  CHECK(copy != NULL);
  status = simd_json_parser_create(NULL);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);

  status = simd_json_parser_create(&parser);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(parser != NULL);

  document = (simd_json_document *)(uintptr_t)1;
  status = simd_json_document_open(NULL, copy, sizeof(input) - 1, capacity,
                                   &document);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(document == NULL);

  document = (simd_json_document *)(uintptr_t)1;
  status = simd_json_document_open(parser, NULL, 0,
                                   SIMD_JSON_REQUIRED_PADDING, &document);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(document == NULL);

  status = simd_json_document_open(parser, copy, sizeof(input) - 1, capacity,
                                   NULL);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);

  document = (simd_json_document *)(uintptr_t)1;
  status = simd_json_document_open(parser, copy, sizeof(input) - 1,
                                   capacity - 1, &document);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(document == NULL);

  document = (simd_json_document *)(uintptr_t)1;
  status = simd_json_document_open(parser, copy, UINT64_MAX, UINT64_MAX,
                                   &document);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(document == NULL);

  simd_json_document_destroy(NULL);
  simd_json_document_destroy(NULL);
  simd_json_parser_destroy(parser);
  simd_json_parser_destroy(NULL);
  simd_json_parser_destroy(NULL);
  free(copy);

  CHECK(simd_json_test_live_parser_count() == 0);
  CHECK(simd_json_test_live_document_count() == 0);
  return 0;
}

static simd_json_status_code expected_injected_status(int32_t kind) {
  switch (kind) {
    case SIMD_JSON_TEST_FAILURE_SIMDJSON:
      return SIMD_JSON_STATUS_INVALID_JSON;
    case SIMD_JSON_TEST_FAILURE_BAD_ALLOC:
      return SIMD_JSON_STATUS_OUT_OF_MEMORY;
    case SIMD_JSON_TEST_FAILURE_STANDARD:
    case SIMD_JSON_TEST_FAILURE_UNKNOWN:
      return SIMD_JSON_STATUS_INTERNAL_FAILURE;
    default:
      return SIMD_JSON_STATUS_INTERNAL_FAILURE;
  }
}

static int parser_failure_matrix(void) {
  static const int32_t points[] = {
      SIMD_JSON_TEST_POINT_BEFORE_PARSER_ALLOCATION,
      SIMD_JSON_TEST_POINT_AFTER_PARSER_ALLOCATION,
  };
  static const int32_t kinds[] = {
      SIMD_JSON_TEST_FAILURE_SIMDJSON,
      SIMD_JSON_TEST_FAILURE_BAD_ALLOC,
      SIMD_JSON_TEST_FAILURE_STANDARD,
      SIMD_JSON_TEST_FAILURE_UNKNOWN,
  };
  size_t point_index;
  size_t kind_index;

  for (point_index = 0; point_index < sizeof(points) / sizeof(points[0]);
       ++point_index) {
    for (kind_index = 0; kind_index < sizeof(kinds) / sizeof(kinds[0]);
         ++kind_index) {
      simd_json_parser *parser = (simd_json_parser *)(uintptr_t)1;
      simd_json_status status;

      simd_json_test_inject_failure(points[point_index], kinds[kind_index]);
      status = simd_json_parser_create(&parser);
      CHECK(status.code == expected_injected_status(kinds[kind_index]));
      CHECK(parser == NULL);
      CHECK(simd_json_test_live_parser_count() == 0);
      CHECK(simd_json_test_live_document_count() == 0);
    }
  }

  return 0;
}

static int document_failure_matrix(void) {
  static const uint8_t input[] = "{\"valid\":true}";
  static const int32_t points[] = {
      SIMD_JSON_TEST_POINT_DURING_DOCUMENT_CONSTRUCTION,
      SIMD_JSON_TEST_POINT_BEFORE_DOCUMENT_PUBLICATION,
  };
  static const int32_t kinds[] = {
      SIMD_JSON_TEST_FAILURE_SIMDJSON,
      SIMD_JSON_TEST_FAILURE_BAD_ALLOC,
      SIMD_JSON_TEST_FAILURE_STANDARD,
      SIMD_JSON_TEST_FAILURE_UNKNOWN,
  };
  size_t point_index;
  size_t kind_index;

  for (point_index = 0; point_index < sizeof(points) / sizeof(points[0]);
       ++point_index) {
    for (kind_index = 0; kind_index < sizeof(kinds) / sizeof(kinds[0]);
         ++kind_index) {
      uint64_t capacity = 0;
      uint8_t *copy = padded_copy(input, sizeof(input) - 1, &capacity);
      simd_json_parser *parser = NULL;
      simd_json_document *document = (simd_json_document *)(uintptr_t)1;
      simd_json_status status;

      CHECK(copy != NULL);
      status = simd_json_parser_create(&parser);
      CHECK(status.code == SIMD_JSON_STATUS_OK);
      CHECK(simd_json_test_live_parser_count() == 1);

      simd_json_test_inject_failure(points[point_index], kinds[kind_index]);
      status = simd_json_document_open(parser, copy, sizeof(input) - 1,
                                       capacity, &document);
      CHECK(status.code == expected_injected_status(kinds[kind_index]));
      CHECK(document == NULL);
      CHECK(simd_json_test_live_parser_count() == 1);
      CHECK(simd_json_test_live_document_count() == 0);

      status = simd_json_document_open(parser, copy, sizeof(input) - 1,
                                       capacity, &document);
      CHECK(status.code == SIMD_JSON_STATUS_OK);
      CHECK(document != NULL);
      simd_json_document_destroy(document);
      document = NULL;
      simd_json_document_destroy(document);

      simd_json_parser_destroy(parser);
      parser = NULL;
      simd_json_parser_destroy(parser);
      free(copy);

      CHECK(simd_json_test_live_parser_count() == 0);
      CHECK(simd_json_test_live_document_count() == 0);
    }
  }

  return 0;
}

static int randomized_malformed_and_lifecycle_matrix(uint64_t seed) {
  uint8_t input[256];
  uint32_t case_index;
  uint64_t state = seed;

  for (case_index = 0; case_index < RANDOMIZED_CASES; ++case_index) {
    const uint64_t logical_length = next_random(&state) % sizeof(input);
    uint64_t capacity = 0;
    uint8_t *copy;
    simd_json_parser *parser = NULL;
    simd_json_document *document = NULL;
    simd_json_status status;
    uint64_t byte_index;

    for (byte_index = 0; byte_index < logical_length; ++byte_index) {
      input[byte_index] = (uint8_t)(next_random(&state) & UINT64_C(0xff));
    }

    copy = padded_copy(input, logical_length, &capacity);
    CHECK(copy != NULL);
    status = simd_json_parser_create(&parser);
    CHECK(status.code == SIMD_JSON_STATUS_OK);
    CHECK(parser != NULL);

    status = simd_json_document_open(parser, copy, logical_length, capacity,
                                     &document);
    CHECK(status.code >= SIMD_JSON_STATUS_OK);
    CHECK(status.code <= SIMD_JSON_STATUS_CANCELLED);
    CHECK(status_has_safe_metadata(status, logical_length));

    if (status.code == SIMD_JSON_STATUS_OK) {
      CHECK(document != NULL);
      simd_json_document_destroy(document);
      document = NULL;
    } else {
      CHECK(document == NULL);
    }

    if ((next_random(&state) & UINT64_C(1)) != 0) {
      simd_json_document_destroy(NULL);
    }

    simd_json_parser_destroy(parser);
    parser = NULL;

    if ((next_random(&state) & UINT64_C(1)) != 0) {
      simd_json_parser_destroy(NULL);
    }

    free(copy);
    CHECK(simd_json_test_live_parser_count() == 0);
    CHECK(simd_json_test_live_document_count() == 0);
  }

  return 0;
}

int main(void) {
  const uint64_t seed = randomized_seed();

  simd_json_test_clear_failure();
  CHECK(valid_input_matrix() == 0);
  CHECK(malformed_input_matrix() == 0);
  CHECK(invalid_argument_matrix() == 0);
  CHECK(parser_failure_matrix() == 0);
  CHECK(document_failure_matrix() == 0);
  CHECK(randomized_malformed_and_lifecycle_matrix(seed) == 0);
  CHECK(simd_json_test_live_parser_count() == 0);
  CHECK(simd_json_test_live_document_count() == 0);
  printf("C ABI conformance passed seed=%" PRIu64 " randomized_cases=%u\n",
         seed, RANDOMIZED_CASES);
  return 0;
}
