#include "simd_json_abi.h"
#include "simd_json_nif_internal.h"
#include "simd_json_test_hooks.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
  static const uint8_t source[] = "{\"n\":18446744073709551616}";
  static const path_segment number_path[] = {KEY_SEGMENT("n")};
  static const path_definition paths[] = {{0, number_path, 1}};
  simd_json_projection_plan *plan = NULL;
  document_fixture document;
  simd_json_result_slot slot = {0};
  simd_json_projection_status status = build_plan(paths, 1, &plan);

  CHECK(status.code == SIMD_JSON_STATUS_OK && plan != NULL);
  CHECK(open_document(source, sizeof(source) - 1U, 0, &document).code ==
        SIMD_JSON_STATUS_OK);
  status = simd_json_projection_execute(document.document, plan, &slot, 1);
  CHECK(status.code == SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE);
  CHECK(status.output_slot == 0);
  CHECK(status.byte_offset == SIMD_JSON_BYTE_OFFSET_UNAVAILABLE ||
        status.byte_offset <= sizeof(source) - 1U);
  CHECK(slot_is_empty(&slot));

  close_document(&document);
  simd_json_projection_plan_destroy(plan);
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
  CHECK(native_state_is_quiescent());
  printf("projection engine conformance passed abi=%" PRIu32 "\n",
         SIMD_JSON_ABI_VERSION);
  return 0;
}
