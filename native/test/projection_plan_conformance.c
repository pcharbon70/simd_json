#include "simd_json_abi.h"
#include "simd_json_test_hooks.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* covers: simd_json.projection_engine.prefix_sharing_plan simd_json.projection_engine.private_abi_v2 simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_engine.abi_v2_conformance */

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "projection plan conformance failure at line %d\n",    \
              __LINE__);                                                       \
      return 1;                                                                \
    }                                                                          \
  } while (0)

#define DEEP_PATH_SEGMENTS 256U
#define LARGE_PLAN_ENTRIES 1024U

typedef struct shared_fixture {
  uint8_t key_bytes[13];
  simd_json_projection_segment segments[4];
  simd_json_projection_entry entries[3];
} shared_fixture;

static void initialize_shared_fixture(shared_fixture *fixture) {
  static const uint8_t keys[13] = {
      'r', 'o', 'o', 't', 'l', 'e', 'f', 't', 'r', 'i', 'g', 'h', 't'};

  memcpy(fixture->key_bytes, keys, sizeof(keys));
  fixture->segments[0] = (simd_json_projection_segment){
      SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0, 4, 0};
  fixture->segments[1] = (simd_json_projection_segment){
      SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 4, 4, 0};
  fixture->segments[2] = (simd_json_projection_segment){
      SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0, 4, 0};
  fixture->segments[3] = (simd_json_projection_segment){
      SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 8, 5, 0};

  fixture->entries[0] = (simd_json_projection_entry){0, 0, 0, 2};
  fixture->entries[1] = (simd_json_projection_entry){1, 0, 2, 2};
  fixture->entries[2] = (simd_json_projection_entry){2, 0, 0, 2};
}

static int at_accounting_baseline(void) {
  const simd_json_test_projection_accounting snapshot =
      simd_json_test_projection_accounting_snapshot();
  return snapshot.live_plans == 0 && snapshot.live_nodes == 0 &&
         snapshot.live_key_bytes == 0;
}

static int status_metadata_is_safe(simd_json_projection_status status) {
  return status.byte_offset == SIMD_JSON_BYTE_OFFSET_UNAVAILABLE &&
         status.output_slot == SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE &&
         status.reserved == UINT32_C(0);
}

static int status_and_result_contract_matrix(void) {
  static const simd_json_status_code projection_statuses[] = {
      SIMD_JSON_STATUS_MISSING_FIELD,
      SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS,
      SIMD_JSON_STATUS_INCORRECT_TYPE,
      SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
      SIMD_JSON_STATUS_CURSOR_CONSUMED,
      SIMD_JSON_STATUS_CANCELLED,
  };
  static const uint8_t borrowed[] = "borrowed";
  simd_json_result_slot slots[7] = {0};
  size_t left;
  size_t right;

  for (left = 0;
       left < sizeof(projection_statuses) / sizeof(projection_statuses[0]);
       ++left) {
    CHECK(projection_statuses[left] == (simd_json_status_code)(left + 7));
    for (right = left + 1;
         right < sizeof(projection_statuses) / sizeof(projection_statuses[0]);
         ++right) {
      CHECK(projection_statuses[left] != projection_statuses[right]);
    }
  }

  slots[0].tag = SIMD_JSON_RESULT_SIGNED_INTEGER;
  slots[0].value.signed_integer = INT64_MIN;
  slots[1].tag = SIMD_JSON_RESULT_UNSIGNED_INTEGER;
  slots[1].value.unsigned_integer = UINT64_MAX;
  slots[2].tag = SIMD_JSON_RESULT_DOUBLE;
  slots[2].value.floating_point = 1.25;
  slots[3].tag = SIMD_JSON_RESULT_BOOLEAN;
  slots[3].value.boolean = UINT64_C(1);
  slots[4].tag = SIMD_JSON_RESULT_NULL;
  slots[5].tag = SIMD_JSON_RESULT_STRING;
  slots[5].value.string.data = borrowed;
  slots[5].value.string.length = sizeof(borrowed) - 1;
  slots[6].tag = SIMD_JSON_RESULT_EMPTY;

  CHECK(slots[0].value.signed_integer == INT64_MIN);
  CHECK(slots[1].value.unsigned_integer == UINT64_MAX);
  CHECK(slots[2].value.floating_point == 1.25);
  CHECK(slots[3].value.boolean == UINT64_C(1));
  CHECK(slots[4].tag == SIMD_JSON_RESULT_NULL);
  CHECK(slots[5].value.string.data == borrowed);
  CHECK(slots[5].value.string.length == sizeof(borrowed) - 1);
  CHECK(memcmp(slots[5].value.string.data, "borrowed",
               (size_t)slots[5].value.string.length) == 0);
  CHECK(slots[6].tag == SIMD_JSON_RESULT_EMPTY);
  return 0;
}

static simd_json_projection_status create_shared_plan(
    shared_fixture *fixture,
    simd_json_projection_plan **out_plan) {
  return simd_json_projection_plan_create(
      fixture->entries, 3, fixture->segments, 4, fixture->key_bytes,
      sizeof(fixture->key_bytes), out_plan);
}

static int shared_prefix_and_copy_matrix(void) {
  shared_fixture fixture;
  simd_json_projection_plan *first = NULL;
  simd_json_projection_plan *second = NULL;
  simd_json_test_projection_summary first_summary;
  simd_json_test_projection_summary second_summary;
  simd_json_projection_status status;

  initialize_shared_fixture(&fixture);
  status = create_shared_plan(&fixture, &first);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(status_metadata_is_safe(status));
  CHECK(first != NULL);
  CHECK(simd_json_test_projection_summary_read(first, &first_summary) == 1);
  CHECK(first_summary.output_slots == 3);
  CHECK(first_summary.nodes == 4);
  CHECK(first_summary.object_edges == 3);
  CHECK(first_summary.array_edges == 0);
  CHECK(first_summary.terminals == 3);
  CHECK(first_summary.key_bytes == 13);
  CHECK(first_summary.maximum_depth == 2);
  CHECK(first_summary.topology_hash != 0);

  memset(fixture.key_bytes, 'x', sizeof(fixture.key_bytes));
  CHECK(simd_json_test_projection_summary_read(first, &second_summary) == 1);
  CHECK(memcmp(&first_summary, &second_summary, sizeof(first_summary)) == 0);

  initialize_shared_fixture(&fixture);
  {
    const simd_json_projection_entry reordered[3] = {
        fixture.entries[2], fixture.entries[0], fixture.entries[1]};
    status = simd_json_projection_plan_create(
        reordered, 3, fixture.segments, 4, fixture.key_bytes,
        sizeof(fixture.key_bytes), &second);
  }
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(second != NULL);
  CHECK(simd_json_test_projection_summary_read(second, &second_summary) == 1);
  CHECK(memcmp(&first_summary, &second_summary, sizeof(first_summary)) == 0);

  simd_json_projection_plan_destroy(second);
  second = NULL;
  simd_json_projection_plan_destroy(second);
  simd_json_projection_plan_destroy(first);
  first = NULL;
  simd_json_projection_plan_destroy(first);
  simd_json_projection_plan_destroy(NULL);
  CHECK(at_accounting_baseline());
  return 0;
}

static int typed_edge_matrix(void) {
  static const uint8_t key_bytes[] = {'a'};
  const simd_json_projection_segment segments[3] = {
      {SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0, 1, 0},
      {SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX, 0, 0, 0, UINT64_MAX},
      {SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX, 0, 0, 0, 0},
  };
  const simd_json_projection_entry entries[2] = {
      {1, 0, 2, 1},
      {0, 0, 0, 2},
  };
  simd_json_projection_plan *plan = NULL;
  simd_json_test_projection_summary summary;
  simd_json_projection_status status = simd_json_projection_plan_create(
      entries, 2, segments, 3, key_bytes, sizeof(key_bytes), &plan);

  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(plan != NULL);
  CHECK(simd_json_test_projection_summary_read(plan, &summary) == 1);
  CHECK(summary.output_slots == 2);
  CHECK(summary.nodes == 4);
  CHECK(summary.object_edges == 1);
  CHECK(summary.array_edges == 2);
  CHECK(summary.terminals == 2);
  CHECK(summary.maximum_depth == 2);
  simd_json_projection_plan_destroy(plan);
  CHECK(at_accounting_baseline());
  return 0;
}

static int boundary_and_scale_matrix(void) {
  static const uint8_t unicode_key[] = {0xe9, 0x9b, 0xaa};
  simd_json_projection_segment deep_segments[DEEP_PATH_SEGMENTS];
  simd_json_projection_segment large_segments[LARGE_PLAN_ENTRIES];
  simd_json_projection_entry large_entries[LARGE_PLAN_ENTRIES];
  simd_json_projection_entry entry = {0, 0, 0, 1};
  simd_json_projection_plan *plan = NULL;
  simd_json_test_projection_summary summary;
  simd_json_projection_status status;
  uint32_t index;

  {
    const simd_json_projection_segment empty_key = {
        SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0, 0, 0};
    status = simd_json_projection_plan_create(&entry, 1, &empty_key, 1, NULL,
                                              0, &plan);
    CHECK(status.code == SIMD_JSON_STATUS_OK);
    CHECK(simd_json_test_projection_summary_read(plan, &summary) == 1);
    CHECK(summary.output_slots == 1 && summary.nodes == 2);
    CHECK(summary.object_edges == 1 && summary.key_bytes == 0);
    simd_json_projection_plan_destroy(plan);
    plan = NULL;
  }

  {
    const simd_json_projection_segment unicode_segment = {
        SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0,
        sizeof(unicode_key), 0};
    status = simd_json_projection_plan_create(
        &entry, 1, &unicode_segment, 1, unicode_key, sizeof(unicode_key),
        &plan);
    CHECK(status.code == SIMD_JSON_STATUS_OK);
    CHECK(simd_json_test_projection_summary_read(plan, &summary) == 1);
    CHECK(summary.nodes == 2 && summary.key_bytes == sizeof(unicode_key));
    simd_json_projection_plan_destroy(plan);
    plan = NULL;
  }

  entry.segment_count = DEEP_PATH_SEGMENTS;
  for (index = 0; index < DEEP_PATH_SEGMENTS; ++index) {
    deep_segments[index] = (simd_json_projection_segment){
        SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0, 1, 0};
  }
  status = simd_json_projection_plan_create(
      &entry, 1, deep_segments, DEEP_PATH_SEGMENTS, (const uint8_t *)"d", 1,
      &plan);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(simd_json_test_projection_summary_read(plan, &summary) == 1);
  CHECK(summary.nodes == DEEP_PATH_SEGMENTS + 1);
  CHECK(summary.object_edges == DEEP_PATH_SEGMENTS);
  CHECK(summary.maximum_depth == DEEP_PATH_SEGMENTS);
  simd_json_projection_plan_destroy(plan);
  plan = NULL;

  for (index = 0; index < DEEP_PATH_SEGMENTS; ++index) {
    deep_segments[index] = (simd_json_projection_segment){
        SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX, 0, 0, 0, index};
  }
  status = simd_json_projection_plan_create(
      &entry, 1, deep_segments, DEEP_PATH_SEGMENTS, NULL, 0, &plan);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(simd_json_test_projection_summary_read(plan, &summary) == 1);
  CHECK(summary.nodes == DEEP_PATH_SEGMENTS + 1);
  CHECK(summary.array_edges == DEEP_PATH_SEGMENTS);
  CHECK(summary.maximum_depth == DEEP_PATH_SEGMENTS);
  simd_json_projection_plan_destroy(plan);
  plan = NULL;

  for (index = 0; index < LARGE_PLAN_ENTRIES; ++index) {
    large_segments[index] = (simd_json_projection_segment){
        SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX, 0, 0, 0,
        LARGE_PLAN_ENTRIES - index};
    large_entries[index] =
        (simd_json_projection_entry){index, 0, index, 1};
  }
  status = simd_json_projection_plan_create(
      large_entries, LARGE_PLAN_ENTRIES, large_segments, LARGE_PLAN_ENTRIES,
      NULL, 0, &plan);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(simd_json_test_projection_summary_read(plan, &summary) == 1);
  CHECK(summary.output_slots == LARGE_PLAN_ENTRIES);
  CHECK(summary.nodes == LARGE_PLAN_ENTRIES + 1);
  CHECK(summary.array_edges == LARGE_PLAN_ENTRIES);
  CHECK(summary.terminals == LARGE_PLAN_ENTRIES);
  CHECK(summary.maximum_depth == 1);
  simd_json_projection_plan_destroy(plan);
  plan = NULL;

  CHECK(at_accounting_baseline());
  return 0;
}

static int expect_invalid(const simd_json_projection_entry *entries,
                          uint64_t entry_count,
                          const simd_json_projection_segment *segments,
                          uint64_t segment_count,
                          const uint8_t *key_bytes,
                          uint64_t key_bytes_length) {
  simd_json_projection_plan *plan =
      (simd_json_projection_plan *)(uintptr_t)UINTPTR_MAX;
  const simd_json_projection_status status = simd_json_projection_plan_create(
      entries, entry_count, segments, segment_count, key_bytes,
      key_bytes_length, &plan);

  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(status_metadata_is_safe(status));
  CHECK(plan == NULL);
  CHECK(at_accounting_baseline());
  return 0;
}

static int invalid_descriptor_matrix(void) {
  shared_fixture fixture;
  simd_json_projection_entry entries[3];
  simd_json_projection_segment segments[4];
  simd_json_projection_plan *plan = NULL;
  simd_json_projection_status status;

  initialize_shared_fixture(&fixture);
  status = simd_json_projection_plan_create(
      fixture.entries, 3, fixture.segments, 4, fixture.key_bytes,
      sizeof(fixture.key_bytes), NULL);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(status_metadata_is_safe(status));
  CHECK(at_accounting_baseline());

  CHECK(expect_invalid(NULL, 0, NULL, 0, NULL, 0) == 0);
  CHECK(expect_invalid(NULL, 1, fixture.segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);
  CHECK(expect_invalid(fixture.entries, 3, NULL, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);
  CHECK(expect_invalid(fixture.entries, 3, fixture.segments, 4, NULL,
                       sizeof(fixture.key_bytes)) == 0);
  CHECK(expect_invalid(fixture.entries, UINT64_MAX, fixture.segments, 4,
                       fixture.key_bytes, sizeof(fixture.key_bytes)) == 0);
  CHECK(expect_invalid(fixture.entries, 3, fixture.segments, UINT64_MAX,
                       fixture.key_bytes, sizeof(fixture.key_bytes)) == 0);

  memcpy(entries, fixture.entries, sizeof(entries));
  entries[0].reserved = 1;
  CHECK(expect_invalid(entries, 3, fixture.segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(entries, fixture.entries, sizeof(entries));
  entries[0].output_slot = 3;
  CHECK(expect_invalid(entries, 3, fixture.segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(entries, fixture.entries, sizeof(entries));
  entries[1].output_slot = entries[0].output_slot;
  CHECK(expect_invalid(entries, 3, fixture.segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(entries, fixture.entries, sizeof(entries));
  entries[0].segment_count = 0;
  CHECK(expect_invalid(entries, 3, fixture.segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(entries, fixture.entries, sizeof(entries));
  entries[0].segment_offset = UINT64_MAX;
  CHECK(expect_invalid(entries, 3, fixture.segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(entries, fixture.entries, sizeof(entries));
  entries[0].segment_offset = 1;
  entries[0].segment_count = UINT64_MAX;
  CHECK(expect_invalid(entries, 3, fixture.segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(segments, fixture.segments, sizeof(segments));
  segments[0].reserved = 1;
  CHECK(expect_invalid(fixture.entries, 3, segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(segments, fixture.segments, sizeof(segments));
  segments[0].tag = UINT32_MAX;
  CHECK(expect_invalid(fixture.entries, 3, segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(segments, fixture.segments, sizeof(segments));
  segments[0].key_offset = UINT64_MAX;
  CHECK(expect_invalid(fixture.entries, 3, segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(segments, fixture.segments, sizeof(segments));
  segments[0].key_offset = 12;
  segments[0].key_length = UINT64_MAX;
  CHECK(expect_invalid(fixture.entries, 3, segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(segments, fixture.segments, sizeof(segments));
  segments[0].array_index = 1;
  CHECK(expect_invalid(fixture.entries, 3, segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  memcpy(segments, fixture.segments, sizeof(segments));
  segments[0] = (simd_json_projection_segment){
      SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX, 0, 1, 0, 0};
  CHECK(expect_invalid(fixture.entries, 3, segments, 4, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  entries[0] = (simd_json_projection_entry){0, 0, 0, 1};
  segments[0] = fixture.segments[0];
  segments[1] = fixture.segments[1];
  CHECK(expect_invalid(entries, 1, segments, 2, fixture.key_bytes,
                       sizeof(fixture.key_bytes)) == 0);

  simd_json_projection_plan_destroy(plan);
  CHECK(at_accounting_baseline());
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

static int exception_and_allocation_matrix(void) {
  static const int32_t exception_kinds[] = {
      SIMD_JSON_TEST_FAILURE_SIMDJSON,
      SIMD_JSON_TEST_FAILURE_STANDARD,
      SIMD_JSON_TEST_FAILURE_UNKNOWN,
  };
  shared_fixture fixture;
  size_t kind_index;
  uint64_t checkpoint;
  int observed_success = 0;

  initialize_shared_fixture(&fixture);
  for (kind_index = 0;
       kind_index < sizeof(exception_kinds) / sizeof(exception_kinds[0]);
       ++kind_index) {
    simd_json_projection_plan *plan =
        (simd_json_projection_plan *)(uintptr_t)UINTPTR_MAX;
    simd_json_projection_status status;

    simd_json_test_projection_inject_failure(7, exception_kinds[kind_index]);
    status = create_shared_plan(&fixture, &plan);
    CHECK(status.code == expected_injected_status(exception_kinds[kind_index]));
    CHECK(status_metadata_is_safe(status));
    CHECK(plan == NULL);
    CHECK(at_accounting_baseline());
  }

  for (checkpoint = 0; checkpoint < 256; ++checkpoint) {
    simd_json_projection_plan *plan =
        (simd_json_projection_plan *)(uintptr_t)UINTPTR_MAX;
    simd_json_projection_status status;

    simd_json_test_projection_inject_failure(
        checkpoint, SIMD_JSON_TEST_FAILURE_BAD_ALLOC);
    status = create_shared_plan(&fixture, &plan);

    if (status.code == SIMD_JSON_STATUS_OK) {
      CHECK(plan != NULL);
      simd_json_test_projection_clear_failure();
      simd_json_projection_plan_destroy(plan);
      observed_success = 1;
      CHECK(checkpoint >= 10);
      CHECK(at_accounting_baseline());
      break;
    }

    CHECK(status.code == SIMD_JSON_STATUS_OUT_OF_MEMORY);
    CHECK(status_metadata_is_safe(status));
    CHECK(plan == NULL);
    CHECK(at_accounting_baseline());
  }

  simd_json_test_projection_clear_failure();
  CHECK(observed_success);
  CHECK(at_accounting_baseline());
  return 0;
}

int main(void) {
  simd_json_test_projection_clear_failure();
  CHECK(at_accounting_baseline());
  CHECK(status_and_result_contract_matrix() == 0);
  CHECK(shared_prefix_and_copy_matrix() == 0);
  CHECK(typed_edge_matrix() == 0);
  CHECK(boundary_and_scale_matrix() == 0);
  CHECK(invalid_descriptor_matrix() == 0);
  CHECK(exception_and_allocation_matrix() == 0);
  CHECK(at_accounting_baseline());
  printf("projection plan conformance passed abi=%" PRIu32 "\n",
         SIMD_JSON_ABI_VERSION);
  return 0;
}
