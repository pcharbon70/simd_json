#define _GNU_SOURCE

#include "simd_json_abi.h"
#include "simd_json_nif_internal.h"
#include "simd_json_test_hooks.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

/* covers: simd_json.projection_engine.declaration_order_independence simd_json.projection_engine.single_guided_traversal simd_json.projection_engine.complete_source_validation simd_json.projection_engine.duplicate_json_key_policy simd_json.projection_engine.scalar_only_materialization simd_json.projection_engine.typed_result_slots simd_json.projection_engine.transactional_conversion simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_engine.shared_prefix_and_order simd_json.projection_engine.object_array_walk simd_json.projection_engine.invalid_unselected_content simd_json.projection_engine.duplicate_object_keys simd_json.projection_engine.transactional_slot_failure simd_json.projection_engine.abi_v2_conformance simd_json.projection_engine.one_boundary_with_timing */

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "projection engine conformance failure at line %d\n",  \
              __LINE__);                                                       \
      return 1;                                                                \
    }                                                                          \
  } while (0)

#define KEY_SEGMENT(literal)                                                   \
  {                                                                            \
    SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY,                                   \
        (const uint8_t *)(literal), sizeof(literal) - 1U, UINT64_C(0)          \
  }

#define INDEX_SEGMENT(value)                                                   \
  {                                                                            \
    SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX, NULL, 0U, (value)                \
  }

typedef struct path_segment {
  simd_json_projection_segment_tag tag;
  const uint8_t *key;
  size_t key_length;
  uint64_t array_index;
} path_segment;

typedef struct path_definition {
  uint32_t output_slot;
  const path_segment *segments;
  size_t segment_count;
} path_definition;

typedef struct document_fixture {
  uint8_t *storage;
  uint64_t logical_length;
  uint64_t capacity;
  simd_json_parser *parser;
  simd_json_document *document;
} document_fixture;

static int native_state_is_quiescent(void) {
  const simd_json_test_projection_accounting projection =
      simd_json_test_projection_accounting_snapshot();
  return projection.live_plans == 0 && projection.live_nodes == 0 &&
         projection.live_key_bytes == 0 &&
         simd_json_test_live_parser_count() == 0 &&
         simd_json_test_live_document_count() == 0;
}

static void close_document(document_fixture *fixture) {
  simd_json_document_destroy(fixture->document);
  fixture->document = NULL;
  simd_json_parser_destroy(fixture->parser);
  fixture->parser = NULL;
  free(fixture->storage);
  fixture->storage = NULL;
  fixture->logical_length = 0;
  fixture->capacity = 0;
}

static simd_json_status open_document(const uint8_t *source,
                                      size_t source_length,
                                      int validate_before_publication,
                                      document_fixture *fixture) {
  simd_json_status status;

  memset(fixture, 0, sizeof(*fixture));
  if (source_length > UINT64_MAX - SIMD_JSON_REQUIRED_PADDING) {
    return (simd_json_status){SIMD_JSON_STATUS_INVALID_ARGUMENT,
                              SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
                              SIMD_JSON_BYTE_OFFSET_UNAVAILABLE};
  }

  fixture->logical_length = (uint64_t)source_length;
  fixture->capacity = fixture->logical_length + SIMD_JSON_REQUIRED_PADDING;
  fixture->storage = (uint8_t *)malloc((size_t)fixture->capacity);
  if (fixture->storage == NULL) {
    return (simd_json_status){SIMD_JSON_STATUS_OUT_OF_MEMORY,
                              SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
                              SIMD_JSON_BYTE_OFFSET_UNAVAILABLE};
  }
  memcpy(fixture->storage, source, source_length);
  memset(fixture->storage + source_length, 0,
         (size_t)SIMD_JSON_REQUIRED_PADDING);

  status = simd_json_parser_create(&fixture->parser);
  if (status.code != SIMD_JSON_STATUS_OK) {
    close_document(fixture);
    return status;
  }

  if (validate_before_publication != 0) {
    status = simd_json_document_open(
        fixture->parser, fixture->storage, fixture->logical_length,
        fixture->capacity, &fixture->document);
  } else {
    status = simd_json_test_document_open_unvalidated(
        fixture->parser, fixture->storage, fixture->logical_length,
        fixture->capacity, &fixture->document);
  }

  if (status.code != SIMD_JSON_STATUS_OK) {
    close_document(fixture);
  }
  return status;
}

static simd_json_projection_status build_plan(
    const path_definition *paths,
    size_t path_count,
    simd_json_projection_plan **out_plan) {
  simd_json_projection_entry *entries = NULL;
  simd_json_projection_segment *segments = NULL;
  uint8_t *keys = NULL;
  size_t segment_count = 0;
  size_t key_count = 0;
  size_t path_index;
  size_t segment_cursor = 0;
  size_t key_cursor = 0;
  simd_json_projection_status status = {
      SIMD_JSON_STATUS_OUT_OF_MEMORY, SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
      SIMD_JSON_BYTE_OFFSET_UNAVAILABLE, SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE, 0};

  *out_plan = NULL;
  for (path_index = 0; path_index < path_count; ++path_index) {
    size_t segment_index;
    if (paths[path_index].segment_count > SIZE_MAX - segment_count) {
      return status;
    }
    segment_count += paths[path_index].segment_count;
    for (segment_index = 0;
         segment_index < paths[path_index].segment_count; ++segment_index) {
      const path_segment *segment = &paths[path_index].segments[segment_index];
      if (segment->tag == SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY) {
        if (segment->key_length > SIZE_MAX - key_count) {
          return status;
        }
        key_count += segment->key_length;
      }
    }
  }

  entries = (simd_json_projection_entry *)calloc(
      path_count, sizeof(simd_json_projection_entry));
  segments = (simd_json_projection_segment *)calloc(
      segment_count, sizeof(simd_json_projection_segment));
  if (key_count != 0) {
    keys = (uint8_t *)malloc(key_count);
  }
  if (entries == NULL || segments == NULL ||
      (key_count != 0 && keys == NULL)) {
    goto cleanup;
  }

  for (path_index = 0; path_index < path_count; ++path_index) {
    size_t segment_index;
    entries[path_index] = (simd_json_projection_entry){
        paths[path_index].output_slot, 0, (uint64_t)segment_cursor,
        (uint64_t)paths[path_index].segment_count};

    for (segment_index = 0;
         segment_index < paths[path_index].segment_count; ++segment_index) {
      const path_segment *source = &paths[path_index].segments[segment_index];
      simd_json_projection_segment *destination = &segments[segment_cursor++];
      destination->tag = source->tag;
      if (source->tag == SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY) {
        destination->key_offset = (uint64_t)key_cursor;
        destination->key_length = (uint64_t)source->key_length;
        if (source->key_length != 0) {
          memcpy(keys + key_cursor, source->key, source->key_length);
          key_cursor += source->key_length;
        }
      } else {
        destination->array_index = source->array_index;
      }
    }
  }

  status = simd_json_projection_plan_create(
      entries, (uint64_t)path_count, segments, (uint64_t)segment_count, keys,
      (uint64_t)key_count, out_plan);

cleanup:
  free(keys);
  free(segments);
  free(entries);
  return status;
}

static int slot_is_empty(const simd_json_result_slot *slot) {
  simd_json_result_value empty;
  memset(&empty, 0, sizeof(empty));
  return slot->tag == SIMD_JSON_RESULT_EMPTY && slot->reserved == 0 &&
         memcmp(&slot->value, &empty, sizeof(empty)) == 0;
}

static int slot_is_string(const simd_json_result_slot *slot,
                          const char *expected) {
  const size_t length = strlen(expected);
  return slot->tag == SIMD_JSON_RESULT_STRING && slot->reserved == 0 &&
         slot->value.string.length == length &&
         memcmp(slot->value.string.data, expected, length) == 0;
}

static int slot_is_bytes(const simd_json_result_slot *slot,
                         const uint8_t *expected,
                         size_t expected_length) {
  return slot->tag == SIMD_JSON_RESULT_STRING && slot->reserved == 0 &&
         slot->value.string.length == expected_length &&
         memcmp(slot->value.string.data, expected, expected_length) == 0;
}

static int guided_object_matrix(void) {
  static const uint8_t source[] =
      "{\"unselected\":{\"huge\":[1,2,{\"x\":\"y\"}]},"
      "\"root\":{\"right\":2,\"left\":1,\"left\":999},"
      "\"escaped\\u006bey\":\"de\\u0063oded\",\"\":true,"
      "\"nested\":{\"dup\":{\"value\":\"first\"},"
      "\"dup\":{\"value\":\"second\"}}}";
  static const path_segment left[] = {
      KEY_SEGMENT("root"), KEY_SEGMENT("left")};
  static const path_segment right[] = {
      KEY_SEGMENT("root"), KEY_SEGMENT("right")};
  static const path_segment escaped[] = {KEY_SEGMENT("escapedkey")};
  static const path_segment empty[] = {KEY_SEGMENT("")};
  static const path_segment nested[] = {
      KEY_SEGMENT("nested"), KEY_SEGMENT("dup"), KEY_SEGMENT("value")};
  static const path_definition paths[] = {
      {0, left, 2}, {1, right, 2}, {2, left, 2},
      {3, escaped, 1}, {4, empty, 1}, {5, nested, 3},
  };
  simd_json_projection_plan *plan = NULL;
  document_fixture document;
  simd_json_result_slot slots[6] = {0};
  simd_json_test_projection_execution_summary summary;
  simd_json_projection_status projection_status;
  simd_json_status document_status;

  projection_status = build_plan(paths, 6, &plan);
  CHECK(projection_status.code == SIMD_JSON_STATUS_OK && plan != NULL);
  document_status = open_document(source, sizeof(source) - 1U, 1, &document);
  CHECK(document_status.code == SIMD_JSON_STATUS_OK && document.document != NULL);

  projection_status =
      simd_json_projection_execute(document.document, plan, slots, 6);
  CHECK(projection_status.code == SIMD_JSON_STATUS_OK);
  CHECK(projection_status.native_code == SIMD_JSON_NATIVE_CODE_UNAVAILABLE);
  CHECK(projection_status.byte_offset == SIMD_JSON_BYTE_OFFSET_UNAVAILABLE);
  CHECK(projection_status.output_slot == SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE);
  CHECK(slots[0].tag == SIMD_JSON_RESULT_SIGNED_INTEGER);
  CHECK(slots[0].value.signed_integer == INT64_C(1));
  CHECK(slots[1].tag == SIMD_JSON_RESULT_SIGNED_INTEGER);
  CHECK(slots[1].value.signed_integer == INT64_C(2));
  CHECK(slots[2].tag == SIMD_JSON_RESULT_SIGNED_INTEGER);
  CHECK(slots[2].value.signed_integer == INT64_C(1));
  CHECK(slot_is_string(&slots[3], "decoded"));
  CHECK(slots[4].tag == SIMD_JSON_RESULT_BOOLEAN);
  CHECK(slots[4].value.boolean == UINT64_C(1));
  CHECK(slot_is_string(&slots[5], "first"));

  CHECK(simd_json_test_projection_execution_summary_read(plan, &summary) == 1);
  CHECK(summary.execution_entries == 1);
  CHECK(summary.visited_nodes == 9);
  CHECK(summary.shared_prefix_visits == 3);
  CHECK(summary.filled_slots == 6);
  CHECK(summary.object_fields == 14);
  CHECK(summary.array_elements == 3);
  CHECK(summary.skipped_values == 9);
  CHECK(summary.cancellation_checks >= summary.visited_nodes);

  close_document(&document);
  simd_json_projection_plan_destroy(plan);
  CHECK(native_state_is_quiescent());
  return 0;
}

static int deterministic_missing_matrix(void) {
  static const uint8_t source[] = "{\"root\":{},\"tail\":[1,2]}";
  static const path_segment z_path[] = {
      KEY_SEGMENT("root"), KEY_SEGMENT("z")};
  static const path_segment a_path[] = {
      KEY_SEGMENT("root"), KEY_SEGMENT("a")};
  static const path_definition paths[] = {
      {0, z_path, 2},
      {1, a_path, 2},
  };
  simd_json_projection_plan *plan = NULL;
  document_fixture document;
  simd_json_result_slot slots[2];
  simd_json_projection_status status;
  size_t index;

  memset(slots, 0xa5, sizeof(slots));
  slots[0].reserved = 0;
  slots[1].reserved = 0;
  status = build_plan(paths, 2, &plan);
  CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);
  CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
        SIMD_JSON_STATUS_OK);

  status = simd_json_projection_execute(document.document, plan, slots, 2);
  CHECK(status.code == SIMD_JSON_STATUS_MISSING_FIELD);
  CHECK(status.output_slot == 0);
  CHECK(status.native_code == SIMD_JSON_NATIVE_CODE_UNAVAILABLE);
  CHECK(status.byte_offset == SIMD_JSON_BYTE_OFFSET_UNAVAILABLE);
  for (index = 0; index < 2; ++index) {
    CHECK(slot_is_empty(&slots[index]));
  }

  close_document(&document);
  simd_json_projection_plan_destroy(plan);
  CHECK(native_state_is_quiescent());
  return 0;
}

static int typed_array_and_scalar_matrix(void) {
  static const uint8_t source[] =
      "{\"ignored\":[{\"tree\":[1,2,3]}],\"values\":["
      "-9223372036854775808,9223372036854775807,"
      "9223372036854775808,18446744073709551615,1.25,"
      "true,false,null,\"nul\\u0000雪\",{\"unused\":1},[2]]}";
  static const uint8_t expected_string[] = {
      'n', 'u', 'l', 0, 0xe9, 0x9b, 0xaa};
  static const path_segment value_8[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(8))};
  static const path_segment value_0[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(0))};
  static const path_segment value_1[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(1))};
  static const path_segment value_2[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(2))};
  static const path_segment value_3[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(3))};
  static const path_segment value_4[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(4))};
  static const path_segment value_5[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(5))};
  static const path_segment value_6[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(6))};
  static const path_segment value_7[] = {
      KEY_SEGMENT("values"), INDEX_SEGMENT(UINT64_C(7))};
  static const path_definition paths[] = {
      {0, value_8, 2}, {1, value_0, 2}, {2, value_1, 2},
      {3, value_2, 2}, {4, value_3, 2}, {5, value_4, 2},
      {6, value_5, 2}, {7, value_6, 2}, {8, value_7, 2},
      {9, value_8, 2},
  };
  simd_json_projection_plan *plan = NULL;
  document_fixture document;
  simd_json_result_slot slots[10] = {0};
  simd_json_test_projection_execution_summary summary;
  simd_json_projection_status status;

  status = build_plan(paths, 10, &plan);
  CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);
  CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
        SIMD_JSON_STATUS_OK);
  status = simd_json_projection_execute(document.document, plan, slots, 10);
  CHECK(status.code == SIMD_JSON_STATUS_OK);

  CHECK(slot_is_bytes(&slots[0], expected_string, sizeof(expected_string)));
  CHECK(slots[1].tag == SIMD_JSON_RESULT_SIGNED_INTEGER);
  CHECK(slots[1].value.signed_integer == INT64_MIN);
  CHECK(slots[2].tag == SIMD_JSON_RESULT_SIGNED_INTEGER);
  CHECK(slots[2].value.signed_integer == INT64_MAX);
  CHECK(slots[3].tag == SIMD_JSON_RESULT_UNSIGNED_INTEGER);
  CHECK(slots[3].value.unsigned_integer == UINT64_C(9223372036854775808));
  CHECK(slots[4].tag == SIMD_JSON_RESULT_UNSIGNED_INTEGER);
  CHECK(slots[4].value.unsigned_integer == UINT64_MAX);
  CHECK(slots[5].tag == SIMD_JSON_RESULT_DOUBLE);
  CHECK(slots[5].value.floating_point == 1.25);
  CHECK(slots[6].tag == SIMD_JSON_RESULT_BOOLEAN);
  CHECK(slots[6].value.boolean == UINT64_C(1));
  CHECK(slots[7].tag == SIMD_JSON_RESULT_BOOLEAN);
  CHECK(slots[7].value.boolean == UINT64_C(0));
  CHECK(slots[8].tag == SIMD_JSON_RESULT_NULL);
  CHECK(slot_is_bytes(&slots[9], expected_string, sizeof(expected_string)));

  CHECK(simd_json_test_projection_execution_summary_read(plan, &summary) == 1);
  CHECK(summary.execution_entries == 1);
  CHECK(summary.visited_nodes == 11);
  CHECK(summary.shared_prefix_visits == 3);
  CHECK(summary.filled_slots == 10);
  CHECK(summary.array_elements == 16);

  close_document(&document);
  simd_json_projection_plan_destroy(plan);
  CHECK(native_state_is_quiescent());
  return 0;
}

static int index_and_type_failure_matrix(void) {
  static const uint8_t short_array[] = "{\"a\":[0,1]}";
  static const path_segment maximum_index[] = {
      KEY_SEGMENT("a"), INDEX_SEGMENT(UINT64_MAX)};
  static const path_segment index_three[] = {
      KEY_SEGMENT("a"), INDEX_SEGMENT(UINT64_C(3))};
  static const path_definition index_paths[] = {
      {0, maximum_index, 2},
      {1, index_three, 2},
  };
  static const uint8_t wrong_nested_type[] = "{\"a\":[7]}";
  static const path_segment nested_field[] = {
      KEY_SEGMENT("a"), INDEX_SEGMENT(UINT64_C(0)), KEY_SEGMENT("x")};
  static const path_definition nested_path[] = {{0, nested_field, 3}};
  static const uint8_t container_terminal[] = "{\"a\":[{\"x\":1}]}";
  static const path_segment terminal[] = {
      KEY_SEGMENT("a"), INDEX_SEGMENT(UINT64_C(0))};
  static const path_definition terminal_path[] = {{0, terminal, 2}};
  const struct {
    const uint8_t *source;
    size_t source_length;
    const path_definition *paths;
    size_t path_count;
    simd_json_status_code expected_code;
    uint32_t expected_slot;
  } cases[] = {
      {short_array, sizeof(short_array) - 1U, index_paths, 2,
       SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS, 1},
      {wrong_nested_type, sizeof(wrong_nested_type) - 1U, nested_path, 1,
       SIMD_JSON_STATUS_INCORRECT_TYPE, 0},
      {container_terminal, sizeof(container_terminal) - 1U, terminal_path, 1,
       SIMD_JSON_STATUS_INCORRECT_TYPE, 0},
  };
  size_t case_index;

  for (case_index = 0; case_index < sizeof(cases) / sizeof(cases[0]);
       ++case_index) {
    simd_json_projection_plan *plan = NULL;
    document_fixture document;
    simd_json_result_slot slots[2] = {0};
    simd_json_projection_status status =
        build_plan(cases[case_index].paths, cases[case_index].path_count, &plan);
    CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);
    CHECK(open_document(cases[case_index].source,
                        cases[case_index].source_length, 1, &document)
              .code == SIMD_JSON_STATUS_OK);

    status = simd_json_projection_execute(
        document.document, plan, slots, cases[case_index].path_count);
    CHECK(status.code == cases[case_index].expected_code);
    CHECK(status.output_slot == cases[case_index].expected_slot);
    CHECK(slot_is_empty(&slots[0]));
    if (cases[case_index].path_count == 2) {
      CHECK(slot_is_empty(&slots[1]));
    }

    close_document(&document);
    simd_json_projection_plan_destroy(plan);
    CHECK(native_state_is_quiescent());
  }
  return 0;
}

static int numeric_range_matrix(void) {
  static const uint8_t integer_source[] = "{\"n\":18446744073709551616}";
  static const uint8_t floating_source[] = "{\"n\":1e400}";
  static const path_segment number_path[] = {KEY_SEGMENT("n")};
  static const path_definition paths[] = {{0, number_path, 1}};
  const struct {
    const uint8_t *source;
    size_t length;
  } cases[] = {
      {integer_source, sizeof(integer_source) - 1U},
      {floating_source, sizeof(floating_source) - 1U},
  };
  size_t case_index;

  for (case_index = 0; case_index < sizeof(cases) / sizeof(cases[0]);
       ++case_index) {
    simd_json_projection_plan *plan = NULL;
    document_fixture document;
    simd_json_result_slot slot = {0};
    simd_json_projection_status status = build_plan(paths, 1, &plan);

    CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);
    CHECK(open_document(cases[case_index].source, cases[case_index].length, 0,
                        &document)
              .code == SIMD_JSON_STATUS_OK);
    status = simd_json_projection_execute(document.document, plan, &slot, 1);
    CHECK(status.code == SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE);
    CHECK(status.output_slot == 0);
    CHECK(status.byte_offset == SIMD_JSON_BYTE_OFFSET_UNAVAILABLE ||
          status.byte_offset <= cases[case_index].length);
    CHECK(slot_is_empty(&slot));

    close_document(&document);
    simd_json_projection_plan_destroy(plan);
  }
  CHECK(native_state_is_quiescent());
  return 0;
}

static int complete_validation_matrix(void) {
  static const uint8_t before_selected[] =
      "{\"bad\":[1,],\"selected\":1}";
  static const uint8_t inside_selected[] =
      "{\"selected\":{\"value\":tru}}";
  static const uint8_t after_selected[] =
      "{\"selected\":1,\"bad\":{\"x\":tru}}";
  static const uint8_t trailing_content[] = "{\"selected\":1} true";
  static const uint8_t unexpected_eof[] =
      "{\"selected\":1,\"bad\":[1,2";
  static const uint8_t later_duplicate[] =
      "{\"selected\":1,\"selected\":[1,]}";
  static const uint8_t malformed_number[] = "{\"selected\":1e}";
  static const path_segment selected[] = {KEY_SEGMENT("selected")};
  static const path_segment selected_value[] = {
      KEY_SEGMENT("selected"), KEY_SEGMENT("value")};
  static const path_definition selected_path[] = {{0, selected, 1}};
  static const path_definition selected_value_path[] = {
      {0, selected_value, 2}};
  const struct {
    const uint8_t *source;
    size_t length;
    const path_definition *paths;
    simd_json_status_code expected;
  } cases[] = {
      {before_selected, sizeof(before_selected) - 1U, selected_path,
       SIMD_JSON_STATUS_INVALID_JSON},
      {inside_selected, sizeof(inside_selected) - 1U, selected_value_path,
       SIMD_JSON_STATUS_INVALID_JSON},
      {after_selected, sizeof(after_selected) - 1U, selected_path,
       SIMD_JSON_STATUS_INVALID_JSON},
      {trailing_content, sizeof(trailing_content) - 1U, selected_path,
       SIMD_JSON_STATUS_UNEXPECTED_EOF},
      {unexpected_eof, sizeof(unexpected_eof) - 1U, selected_path,
       SIMD_JSON_STATUS_UNEXPECTED_EOF},
      {later_duplicate, sizeof(later_duplicate) - 1U, selected_path,
       SIMD_JSON_STATUS_INVALID_JSON},
      {malformed_number, sizeof(malformed_number) - 1U, selected_path,
       SIMD_JSON_STATUS_INVALID_JSON},
  };
  size_t case_index;
  size_t executed_cases = 0;

  for (case_index = 0; case_index < sizeof(cases) / sizeof(cases[0]);
       ++case_index) {
    simd_json_projection_plan *plan = NULL;
    document_fixture document;
    simd_json_result_slot slot;
    simd_json_projection_status projection_status;
    const size_t path_count = cases[case_index].paths == selected_path ? 1U : 1U;
    const simd_json_status document_status =
        open_document(cases[case_index].source, cases[case_index].length, 0,
                      &document);

    CHECK(document_status.code == SIMD_JSON_STATUS_OK ||
          document_status.code == cases[case_index].expected);
    if (document_status.code != SIMD_JSON_STATUS_OK) {
      continue;
    }

    projection_status =
        build_plan(cases[case_index].paths, path_count, &plan);
    CHECK(projection_status.code == SIMD_JSON_STATUS_OK && plan != NULL);
    memset(&slot, 0xa5, sizeof(slot));
    slot.reserved = 0;
    projection_status =
        simd_json_projection_execute(document.document, plan, &slot, 1);
    if (projection_status.code != cases[case_index].expected) {
      fprintf(stderr,
              "validation case=%zu expected=%" PRId32 " actual=%" PRId32
              " native=%" PRId32 " offset=%" PRIu64 "\n",
              case_index, cases[case_index].expected, projection_status.code,
              projection_status.native_code, projection_status.byte_offset);
    }
    CHECK(projection_status.code == cases[case_index].expected);
    CHECK(projection_status.output_slot == SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE ||
          projection_status.output_slot == 0);
    CHECK(projection_status.byte_offset != SIMD_JSON_BYTE_OFFSET_UNAVAILABLE);
    CHECK(projection_status.byte_offset <= cases[case_index].length);
    CHECK(slot_is_empty(&slot));
    ++executed_cases;

    close_document(&document);
    simd_json_projection_plan_destroy(plan);
    CHECK(native_state_is_quiescent());
  }

  CHECK(executed_cases >= 5);
  return 0;
}

static int invalid_utf8_matrix(void) {
  static const uint8_t source[] = {
      '{', '"', 's', 'e', 'l', 'e', 'c', 't', 'e', 'd', '"', ':', '"',
      0xff, '"', '}'};
  document_fixture document;
  const simd_json_status status =
      open_document(source, sizeof(source), 0, &document);

  CHECK(status.code == SIMD_JSON_STATUS_INVALID_UTF8);
  CHECK(document.document == NULL);
  CHECK(native_state_is_quiescent());
  return 0;
}

typedef struct cancellation_context {
  uint64_t successful_checks;
} cancellation_context;

static uint32_t cancellation_probe(void *opaque) {
  cancellation_context *context = (cancellation_context *)opaque;
  if (context->successful_checks == 0) {
    return UINT32_C(1);
  }
  --context->successful_checks;
  return UINT32_C(0);
}

static void dirty_slots(simd_json_result_slot *slots, size_t slot_count) {
  size_t index;
  memset(slots, 0xa5, slot_count * sizeof(*slots));
  for (index = 0; index < slot_count; ++index) {
    slots[index].reserved = 0;
  }
}

static int slots_are_empty(const simd_json_result_slot *slots,
                           size_t slot_count) {
  size_t index;
  for (index = 0; index < slot_count; ++index) {
    if (!slot_is_empty(&slots[index])) {
      return 0;
    }
  }
  return 1;
}

static int cancellation_matrix(void) {
  static const uint8_t source[] =
      "{\"skip\":[{\"x\":[1,2,3]},{\"y\":false}],"
      "\"root\":{\"b\":2,\"a\":\"value\"},"
      "\"tail\":[null,{\"deep\":[4,5,6]}]}";
  static const path_segment a_path[] = {
      KEY_SEGMENT("root"), KEY_SEGMENT("a")};
  static const path_segment b_path[] = {
      KEY_SEGMENT("root"), KEY_SEGMENT("b")};
  static const path_definition paths[] = {
      {0, a_path, 2}, {1, b_path, 2}, {2, a_path, 2}};
  simd_json_projection_plan *plan = NULL;
  simd_json_projection_status status = build_plan(paths, 3, &plan);
  uint64_t boundary;
  int observed_success = 0;

  CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);

  {
    document_fixture document;
    simd_json_result_slot slots[3];
    cancellation_context context = {0};
    CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
          SIMD_JSON_STATUS_OK);
    dirty_slots(slots, 3);
    simd_json_nif_projection_set_cancellation(
        document.document, &context, cancellation_probe);
    status = simd_json_projection_execute(document.document, plan, slots, 3);
    CHECK(status.code == SIMD_JSON_STATUS_CANCELLED);
    CHECK(slots_are_empty(slots, 3));
    simd_json_nif_projection_clear_cancellation(document.document);
    status = simd_json_projection_execute(document.document, plan, slots, 3);
    CHECK(status.code == SIMD_JSON_STATUS_OK);
    close_document(&document);
  }

  {
    document_fixture document;
    simd_json_result_slot slots[3];
    cancellation_context context = {5};
    CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
          SIMD_JSON_STATUS_OK);
    dirty_slots(slots, 3);
    simd_json_nif_projection_set_cancellation(
        document.document, &context, cancellation_probe);
    status = simd_json_projection_execute(document.document, plan, slots, 3);
    CHECK(status.code == SIMD_JSON_STATUS_CANCELLED);
    CHECK(slots_are_empty(slots, 3));
    simd_json_nif_projection_clear_cancellation(document.document);
    status = simd_json_projection_execute(document.document, plan, slots, 3);
    CHECK(status.code == SIMD_JSON_STATUS_CURSOR_CONSUMED);
    CHECK(slots_are_empty(slots, 3));
    close_document(&document);
  }

  for (boundary = 0; boundary < UINT64_C(1024); ++boundary) {
    document_fixture document;
    simd_json_result_slot slots[3];
    cancellation_context context = {boundary};
    CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
          SIMD_JSON_STATUS_OK);
    dirty_slots(slots, 3);
    simd_json_nif_projection_set_cancellation(
        document.document, &context, cancellation_probe);
    status = simd_json_projection_execute(document.document, plan, slots, 3);
    simd_json_nif_projection_clear_cancellation(document.document);

    if (status.code == SIMD_JSON_STATUS_OK) {
      observed_success = 1;
      CHECK(boundary > 10);
      close_document(&document);
      break;
    }

    CHECK(status.code == SIMD_JSON_STATUS_CANCELLED);
    CHECK(slots_are_empty(slots, 3));
    close_document(&document);
  }

  CHECK(observed_success);
  simd_json_projection_plan_destroy(plan);
  CHECK(native_state_is_quiescent());
  return 0;
}

static simd_json_status_code expected_execution_injection(int32_t kind) {
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

static int traversal_failure_injection_matrix(void) {
  static const uint8_t source[] =
      "{\"skip\":[1,{\"nested\":[2,3]}],"
      "\"root\":{\"left\":\"value\",\"right\":9},"
      "\"tail\":false}";
  static const path_segment left[] = {
      KEY_SEGMENT("root"), KEY_SEGMENT("left")};
  static const path_segment right[] = {
      KEY_SEGMENT("root"), KEY_SEGMENT("right")};
  static const path_definition paths[] = {
      {0, left, 2}, {1, right, 2}, {2, left, 2}};
  static const int32_t exception_kinds[] = {
      SIMD_JSON_TEST_FAILURE_SIMDJSON,
      SIMD_JSON_TEST_FAILURE_STANDARD,
      SIMD_JSON_TEST_FAILURE_UNKNOWN,
  };
  simd_json_projection_plan *plan = NULL;
  simd_json_projection_status status = build_plan(paths, 3, &plan);
  uint64_t checkpoint;
  size_t kind_index;
  int observed_success = 0;

  CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);
  for (checkpoint = 0; checkpoint < UINT64_C(1024); ++checkpoint) {
    document_fixture document;
    simd_json_result_slot slots[3];
    CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
          SIMD_JSON_STATUS_OK);
    dirty_slots(slots, 3);
    simd_json_test_projection_inject_failure(
        checkpoint, SIMD_JSON_TEST_FAILURE_BAD_ALLOC);
    status = simd_json_projection_execute(document.document, plan, slots, 3);
    simd_json_test_projection_clear_failure();

    if (status.code == SIMD_JSON_STATUS_OK) {
      observed_success = 1;
      CHECK(checkpoint > 10);
      close_document(&document);
      break;
    }

    CHECK(status.code == SIMD_JSON_STATUS_OUT_OF_MEMORY);
    CHECK(status.output_slot == SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE);
    CHECK(slots_are_empty(slots, 3));
    close_document(&document);
  }
  CHECK(observed_success);

  for (kind_index = 0;
       kind_index < sizeof(exception_kinds) / sizeof(exception_kinds[0]);
       ++kind_index) {
    document_fixture document;
    simd_json_result_slot slots[3];
    CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
          SIMD_JSON_STATUS_OK);
    dirty_slots(slots, 3);
    simd_json_test_projection_inject_failure(5, exception_kinds[kind_index]);
    status = simd_json_projection_execute(document.document, plan, slots, 3);
    simd_json_test_projection_clear_failure();
    CHECK(status.code == expected_execution_injection(exception_kinds[kind_index]));
    CHECK(slots_are_empty(slots, 3));
    close_document(&document);
  }

  simd_json_projection_plan_destroy(plan);
  simd_json_test_projection_clear_failure();
  CHECK(native_state_is_quiescent());
  return 0;
}

static int execution_argument_and_cursor_matrix(void) {
  static const uint8_t source[] = "{\"value\":7}";
  static const path_segment value_path[] = {KEY_SEGMENT("value")};
  static const path_definition paths[] = {{0, value_path, 1}};
  simd_json_projection_plan *plan = NULL;
  document_fixture document;
  simd_json_result_slot slots[2];
  simd_json_projection_status status = build_plan(paths, 1, &plan);

  CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);
  CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
        SIMD_JSON_STATUS_OK);

  dirty_slots(slots, 2);
  status = simd_json_projection_execute(document.document, plan, slots, 2);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(slots[0].tag != SIMD_JSON_RESULT_EMPTY);

  dirty_slots(slots, 2);
  slots[0].reserved = 1;
  status = simd_json_projection_execute(document.document, plan, slots, 1);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(slots[0].tag != SIMD_JSON_RESULT_EMPTY);

  slots[0].reserved = 0;
  status = simd_json_projection_execute(document.document, plan, slots, 1);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(slots[0].tag == SIMD_JSON_RESULT_SIGNED_INTEGER);
  CHECK(slots[0].value.signed_integer == 7);

  dirty_slots(slots, 1);
  status = simd_json_projection_execute(document.document, plan, slots, 1);
  CHECK(status.code == SIMD_JSON_STATUS_CURSOR_CONSUMED);
  CHECK(slot_is_empty(&slots[0]));

  status = simd_json_projection_execute(NULL, plan, slots, 1);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  status = simd_json_projection_execute(document.document, plan, NULL, 1);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);

  close_document(&document);
  simd_json_projection_plan_destroy(plan);
  CHECK(native_state_is_quiescent());
  return 0;
}

static uint8_t *nested_object_source(size_t depth, size_t *out_length) {
  const size_t length = depth * 6U + 1U;
  uint8_t *source = (uint8_t *)malloc(length);
  size_t cursor = 0;
  size_t index;

  if (source == NULL) {
    return NULL;
  }
  for (index = 0; index < depth; ++index) {
    memcpy(source + cursor, "{\"d\":", 5);
    cursor += 5;
  }
  source[cursor++] = '1';
  for (index = 0; index < depth; ++index) {
    source[cursor++] = '}';
  }
  if (cursor != length) {
    free(source);
    return NULL;
  }
  *out_length = length;
  return source;
}

static int depth_and_recursion_bound_matrix(void) {
  static const size_t valid_depth = 256U;
  static const size_t excessive_depth = 1100U;
  const size_t depths[] = {valid_depth, excessive_depth};
  size_t case_index;

  for (case_index = 0; case_index < sizeof(depths) / sizeof(depths[0]);
       ++case_index) {
    const size_t depth = depths[case_index];
    path_segment *segments =
        (path_segment *)calloc(depth, sizeof(path_segment));
    path_definition path;
    simd_json_projection_plan *plan = NULL;
    document_fixture document;
    simd_json_result_slot slot = {0};
    simd_json_projection_status projection_status;
    simd_json_status document_status;
    uint8_t *source;
    size_t source_length = 0;
    size_t index;

    CHECK(segments != NULL);
    source = nested_object_source(depth, &source_length);
    CHECK(source != NULL);
    for (index = 0; index < depth; ++index) {
      segments[index] =
          (path_segment)KEY_SEGMENT("d");
    }
    path = (path_definition){0, segments, depth};
    projection_status = build_plan(&path, 1, &plan);
    CHECK(projection_status.code == SIMD_JSON_STATUS_OK && plan != NULL);

    document_status = open_document(
        source, source_length, depth == valid_depth ? 1 : 0, &document);
    if (depth == valid_depth) {
      CHECK(document_status.code == SIMD_JSON_STATUS_OK);
      projection_status =
          simd_json_projection_execute(document.document, plan, &slot, 1);
      CHECK(projection_status.code == SIMD_JSON_STATUS_OK);
      CHECK(slot.tag == SIMD_JSON_RESULT_SIGNED_INTEGER);
      CHECK(slot.value.signed_integer == 1);
      close_document(&document);
    } else if (document_status.code == SIMD_JSON_STATUS_OK) {
      projection_status =
          simd_json_projection_execute(document.document, plan, &slot, 1);
      CHECK(projection_status.code == SIMD_JSON_STATUS_INVALID_JSON);
      CHECK(projection_status.native_code != SIMD_JSON_NATIVE_CODE_UNAVAILABLE);
      CHECK(slot_is_empty(&slot));
      close_document(&document);
    } else {
      CHECK(document_status.code == SIMD_JSON_STATUS_INVALID_JSON);
    }

    simd_json_projection_plan_destroy(plan);
    free(source);
    free(segments);
    CHECK(native_state_is_quiescent());
  }
  return 0;
}

static int unicode_nested_array_matrix(void) {
  static const uint8_t source[] =
      "{\"雪\":{\"items\":[{\"名\":\"值\"},[],{}]},"
      "\"unused\":{\"深\":[1,2,3]}}";
  static const uint8_t expected[] = {0xe5, 0x80, 0xbc};
  static const path_segment selected[] = {
      KEY_SEGMENT("雪"), KEY_SEGMENT("items"), INDEX_SEGMENT(UINT64_C(0)),
      KEY_SEGMENT("名")};
  static const path_definition paths[] = {{0, selected, 4}};
  static const path_segment empty_array_index[] = {
      KEY_SEGMENT("雪"), KEY_SEGMENT("items"), INDEX_SEGMENT(UINT64_C(1)),
      INDEX_SEGMENT(UINT64_C(0))};
  static const path_definition empty_array_path[] = {
      {0, empty_array_index, 4}};
  simd_json_projection_plan *plan = NULL;
  document_fixture document;
  simd_json_result_slot slot = {0};
  simd_json_projection_status status = build_plan(paths, 1, &plan);

  CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);
  CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
        SIMD_JSON_STATUS_OK);
  status = simd_json_projection_execute(document.document, plan, &slot, 1);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(slot_is_bytes(&slot, expected, sizeof(expected)));
  close_document(&document);
  simd_json_projection_plan_destroy(plan);

  plan = NULL;
  memset(&slot, 0, sizeof(slot));
  CHECK(build_plan(empty_array_path, 1, &plan).code == SIMD_JSON_STATUS_OK);
  CHECK(open_document(source, sizeof(source) - 1U, 1, &document).code ==
        SIMD_JSON_STATUS_OK);
  status = simd_json_projection_execute(document.document, plan, &slot, 1);
  CHECK(status.code == SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS);
  CHECK(status.output_slot == 0);
  CHECK(slot_is_empty(&slot));
  close_document(&document);
  simd_json_projection_plan_destroy(plan);
  CHECK(native_state_is_quiescent());
  return 0;
}

static uint8_t *large_unselected_source(size_t element_count,
                                        int malformed_tail,
                                        size_t *out_length) {
  static const char prefix[] = "{\"selected\":\"ok\",\"unselected\":[";
  static const char valid_suffix[] = "0]}";
  static const char malformed_suffix[] = "tru]}";
  const char *suffix = malformed_tail != 0 ? malformed_suffix : valid_suffix;
  const size_t suffix_length = strlen(suffix);
  const size_t repeated = element_count == 0 ? 0 : (element_count - 1U) * 2U;
  const size_t length = sizeof(prefix) - 1U + repeated + suffix_length;
  uint8_t *source = (uint8_t *)malloc(length);
  size_t cursor = 0;
  size_t index;

  if (source == NULL || element_count == 0) {
    free(source);
    return NULL;
  }
  memcpy(source + cursor, prefix, sizeof(prefix) - 1U);
  cursor += sizeof(prefix) - 1U;
  for (index = 1; index < element_count; ++index) {
    source[cursor++] = '0';
    source[cursor++] = ',';
  }
  memcpy(source + cursor, suffix, suffix_length);
  cursor += suffix_length;
  if (cursor != length) {
    free(source);
    return NULL;
  }
  *out_length = length;
  return source;
}

static int large_unselected_validation_matrix(void) {
  static const size_t element_count = 100000U;
  static const path_segment selected[] = {KEY_SEGMENT("selected")};
  static const path_definition paths[] = {{0, selected, 1}};
  int malformed;

  for (malformed = 0; malformed <= 1; ++malformed) {
    size_t source_length = 0;
    uint8_t *source =
        large_unselected_source(element_count, malformed, &source_length);
    simd_json_projection_plan *plan = NULL;
    document_fixture document;
    simd_json_result_slot slot = {0};
    simd_json_test_projection_execution_summary summary;
    simd_json_projection_status status;

    CHECK(source != NULL);
    CHECK(build_plan(paths, 1, &plan).code == SIMD_JSON_STATUS_OK);
    CHECK(open_document(source, source_length, malformed == 0, &document).code ==
          SIMD_JSON_STATUS_OK);
    status = simd_json_projection_execute(document.document, plan, &slot, 1);

    if (malformed == 0) {
      CHECK(status.code == SIMD_JSON_STATUS_OK);
      CHECK(slot_is_string(&slot, "ok"));
      CHECK(simd_json_test_projection_execution_summary_read(plan, &summary) ==
            1);
      CHECK(summary.array_elements == element_count);
      CHECK(summary.skipped_values >= element_count);
    } else {
      CHECK(status.code == SIMD_JSON_STATUS_INVALID_JSON);
      CHECK(status.byte_offset != SIMD_JSON_BYTE_OFFSET_UNAVAILABLE);
      CHECK(status.byte_offset <= source_length);
      CHECK(slot_is_empty(&slot));
    }

    close_document(&document);
    simd_json_projection_plan_destroy(plan);
    free(source);
    CHECK(native_state_is_quiescent());
  }
  return 0;
}

static int guard_page_and_borrowed_string_matrix(void) {
  static const uint8_t source[] =
      "{\"selected\":\"edge\\u0000雪\",\"tail\":[1,2,3]}";
  static const uint8_t expected[] = {
      'e', 'd', 'g', 'e', 0, 0xe9, 0x9b, 0xaa};
  static const path_segment selected[] = {KEY_SEGMENT("selected")};
  static const path_definition paths[] = {{0, selected, 1}};
  const long reported_page_size = sysconf(_SC_PAGESIZE);
  const size_t logical_length = sizeof(source) - 1U;
  const size_t capacity = logical_length + (size_t)SIMD_JSON_REQUIRED_PADDING;
  size_t page_size;
  uint8_t *mapping;
  uint8_t *input;
  simd_json_parser *parser = NULL;
  simd_json_document *document = NULL;
  simd_json_projection_plan *plan = NULL;
  simd_json_result_slot slot = {0};
  simd_json_status document_status;
  simd_json_projection_status projection_status;

  CHECK(reported_page_size > 0);
  page_size = (size_t)reported_page_size;
  CHECK(capacity < page_size);
  mapping = (uint8_t *)mmap(NULL, page_size * 2U, PROT_READ | PROT_WRITE,
                            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  CHECK(mapping != MAP_FAILED);
  CHECK(mprotect(mapping + page_size, page_size, PROT_NONE) == 0);
  input = mapping + page_size - capacity;
  memcpy(input, source, logical_length);
  memset(input + logical_length, 0, (size_t)SIMD_JSON_REQUIRED_PADDING);

  document_status = simd_json_parser_create(&parser);
  CHECK(document_status.code == SIMD_JSON_STATUS_OK && parser != NULL);
  document_status = simd_json_document_open(
      parser, input, logical_length, capacity, &document);
  CHECK(document_status.code == SIMD_JSON_STATUS_OK && document != NULL);
  projection_status = build_plan(paths, 1, &plan);
  CHECK(projection_status.code == SIMD_JSON_STATUS_OK && plan != NULL);
  projection_status =
      simd_json_projection_execute(document, plan, &slot, 1);
  CHECK(projection_status.code == SIMD_JSON_STATUS_OK);
  CHECK(slot_is_bytes(&slot, expected, sizeof(expected)));

  simd_json_projection_plan_destroy(plan);
  simd_json_document_destroy(document);
  simd_json_parser_destroy(parser);
  CHECK(munmap(mapping, page_size * 2U) == 0);
  CHECK(native_state_is_quiescent());
  return 0;
}

int main(void) {
  simd_json_test_clear_failure();
  simd_json_test_projection_clear_failure();
  CHECK(native_state_is_quiescent());
  CHECK(guided_object_matrix() == 0);
  CHECK(deterministic_missing_matrix() == 0);
  CHECK(typed_array_and_scalar_matrix() == 0);
  CHECK(index_and_type_failure_matrix() == 0);
  CHECK(numeric_range_matrix() == 0);
  CHECK(complete_validation_matrix() == 0);
  CHECK(invalid_utf8_matrix() == 0);
  CHECK(cancellation_matrix() == 0);
  CHECK(traversal_failure_injection_matrix() == 0);
  CHECK(execution_argument_and_cursor_matrix() == 0);
  CHECK(depth_and_recursion_bound_matrix() == 0);
  CHECK(unicode_nested_array_matrix() == 0);
  CHECK(large_unselected_validation_matrix() == 0);
  CHECK(guard_page_and_borrowed_string_matrix() == 0);
  CHECK(native_state_is_quiescent());
  printf("projection engine conformance passed abi=%" PRIu32 "\n",
         SIMD_JSON_ABI_VERSION);
  return 0;
}
