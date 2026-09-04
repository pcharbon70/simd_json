#include "simd_json_abi.h"
#include "simd_json_test_hooks.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* covers: simd_json.stream_cursor.private_abi_v3 simd_json.stream_cursor.opaque_cursor simd_json.stream_cursor.parent_retention simd_json.stream_cursor.projection_plan_reuse simd_json.stream_cursor.exception_and_failure_cleanup simd_json.stream_cursor.abi_v3_conformance */
/* covers: simd_json.stream_cursor.single_target_lookup simd_json.stream_cursor.forward_only_rows simd_json.stream_cursor.row_count_bound simd_json.stream_cursor.encoded_byte_bound simd_json.stream_cursor.transactional_batch simd_json.stream_cursor.copied_row_values simd_json.stream_cursor.exact_done_detection simd_json.stream_cursor.complete_consumption_validation simd_json.stream_cursor.indexed_status simd_json.stream_cursor.batch_boundary simd_json.stream_cursor.internal_diagnostics simd_json.stream_cursor.target_lookup_and_retention simd_json.stream_cursor.reused_row_projection simd_json.stream_cursor.row_and_byte_boundaries simd_json.stream_cursor.exact_end_and_trailing_validation simd_json.stream_cursor.indexed_row_failure simd_json.stream_cursor.cancellation_and_cleanup_matrix */

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "stream cursor conformance failure at line %d\n",      \
              __LINE__);                                                       \
      return 1;                                                                \
    }                                                                          \
  } while (0)

typedef struct document_fixture {
  uint8_t *storage;
  uint64_t logical_length;
  simd_json_parser *parser;
  simd_json_document *document;
} document_fixture;

static int stream_is_quiescent(void) {
  const simd_json_test_stream_accounting value =
      simd_json_test_stream_accounting_snapshot();
  return value.live_cursors == 0 && value.live_frames == 0 &&
         value.live_key_bytes == 0 && value.live_owned_plans == 0;
}

static int projection_is_quiescent(void) {
  const simd_json_test_projection_accounting value =
      simd_json_test_projection_accounting_snapshot();
  return value.live_plans == 0 && value.live_nodes == 0 &&
         value.live_key_bytes == 0;
}

static int status_is_safe(simd_json_stream_status status) {
  return status.native_code == SIMD_JSON_NATIVE_CODE_UNAVAILABLE &&
         status.byte_offset == SIMD_JSON_BYTE_OFFSET_UNAVAILABLE &&
         status.output_slot == SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE &&
         status.reserved == 0 &&
         status.array_index == SIMD_JSON_ARRAY_INDEX_UNAVAILABLE;
}

static int open_document(document_fixture *fixture) {
  static const uint8_t source[] = "{\"rows\":[{\"value\":1}]}";
  simd_json_status status;

  memset(fixture, 0, sizeof(*fixture));
  fixture->logical_length = sizeof(source) - 1;
  fixture->storage =
      (uint8_t *)calloc((size_t)(fixture->logical_length +
                                SIMD_JSON_REQUIRED_PADDING),
                       sizeof(uint8_t));
  CHECK(fixture->storage != NULL);
  memcpy(fixture->storage, source, (size_t)fixture->logical_length);
  status = simd_json_parser_create(&fixture->parser);
  CHECK(status.code == SIMD_JSON_STATUS_OK && fixture->parser != NULL);
  status = simd_json_document_open(
      fixture->parser, fixture->storage, fixture->logical_length,
      fixture->logical_length + SIMD_JSON_REQUIRED_PADDING,
      &fixture->document);
  CHECK(status.code == SIMD_JSON_STATUS_OK && fixture->document != NULL);
  return 0;
}

static void close_document(document_fixture *fixture) {
  simd_json_document_destroy(fixture->document);
  simd_json_parser_destroy(fixture->parser);
  free(fixture->storage);
  memset(fixture, 0, sizeof(*fixture));
}

static simd_json_projection_plan *create_plan(void) {
  static const uint8_t key[] = "value";
  const simd_json_projection_segment segment = {
      SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0, sizeof(key) - 1, 0};
  const simd_json_projection_entry entry = {0, 0, 0, 1};
  simd_json_projection_plan *plan = NULL;
  const simd_json_projection_status status =
      simd_json_projection_plan_create(&entry, 1, &segment, 1, key,
                                       sizeof(key) - 1, &plan);
  if (status.code != SIMD_JSON_STATUS_OK) {
    return NULL;
  }
  return plan;
}

static simd_json_stream_cursor_config config_for(
    simd_json_projection_plan *plan, uint64_t rows, uint64_t bytes) {
  const simd_json_stream_cursor_config config = {plan, rows, bytes, 17, 0};
  return config;
}

static int construction_and_copy_matrix(document_fixture *fixture) {
  static uint8_t key_bytes[] = {'r', 'o', 'w', 's', 0xe9, 0x9b, 0xaa};
  const simd_json_projection_segment nested_segments[] = {
      {SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0, 4, 0},
      {SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX, 0, 0, 0, UINT64_MAX},
      {SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 4, 3, 0},
  };
  const simd_json_stream_target targets[] = {
      {NULL, 0, NULL, 0},
      {nested_segments, 3, key_bytes, sizeof(key_bytes)},
  };
  size_t index;

  for (index = 0; index < sizeof(targets) / sizeof(targets[0]); ++index) {
    simd_json_projection_plan *plan = create_plan();
    simd_json_stream_cursor_config config = config_for(
        plan, index == 0 ? 1 : SIMD_JSON_STREAM_MAX_BATCH_SIZE,
        index == 0 ? 1 : SIMD_JSON_STREAM_MAX_BATCH_BYTES);
    simd_json_stream_cursor *cursor = NULL;
    simd_json_test_stream_summary before;
    simd_json_test_stream_summary after;
    const simd_json_stream_status status = simd_json_stream_cursor_create(
        fixture->document, &targets[index], &config, &cursor);

    CHECK(plan != NULL);
    CHECK(status.code == SIMD_JSON_STATUS_OK && status_is_safe(status));
    CHECK(cursor != NULL && config.projection_plan == NULL);
    CHECK(simd_json_test_stream_summary_read(cursor, &before) == 1);
    CHECK(before.target_segments == (index == 0 ? 0 : 3));
    CHECK(before.object_segments == (index == 0 ? 0 : 2));
    CHECK(before.array_segments == (index == 0 ? 0 : 1));
    CHECK(before.key_bytes == (index == 0 ? 0 : sizeof(key_bytes)));
    CHECK(before.parent_generation == 17);
    CHECK(before.state == SIMD_JSON_STREAM_CURSOR_READY);
    CHECK(before.owns_projection_plan == 1);
    memset(key_bytes, 'x', sizeof(key_bytes));
    CHECK(simd_json_test_stream_summary_read(cursor, &after) == 1);
    CHECK(memcmp(&before, &after, sizeof(before)) == 0);
    simd_json_stream_cursor_destroy(cursor);
    cursor = NULL;
    simd_json_stream_cursor_destroy(cursor);
    CHECK(stream_is_quiescent() && projection_is_quiescent());
  }
  return 0;
}

static int expect_invalid(document_fixture *fixture,
                          const simd_json_stream_target *target,
                          simd_json_stream_cursor_config *config) {
  simd_json_stream_cursor *cursor =
      (simd_json_stream_cursor *)(uintptr_t)UINTPTR_MAX;
  simd_json_projection_plan *plan = config == NULL ? NULL : config->projection_plan;
  const simd_json_stream_status status = simd_json_stream_cursor_create(
      fixture->document, target, config, &cursor);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(status_is_safe(status));
  CHECK(cursor == NULL);
  if (config != NULL) CHECK(config->projection_plan == plan);
  simd_json_projection_plan_destroy(plan);
  CHECK(stream_is_quiescent() && projection_is_quiescent());
  return 0;
}

static int invalid_matrix(document_fixture *fixture) {
  static const uint8_t key[] = "x";
  simd_json_projection_segment segment = {
      SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0, 1, 0};
  simd_json_stream_target target = {&segment, 1, key, 1};
  simd_json_stream_cursor_config config;
  simd_json_stream_cursor *cursor = NULL;
  simd_json_stream_status status;

  config = config_for(create_plan(), 1, 1);
  CHECK(expect_invalid(fixture, NULL, &config) == 0);
  config = config_for(create_plan(), 0, 1);
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  config = config_for(create_plan(), SIMD_JSON_STREAM_MAX_BATCH_SIZE + 1, 1);
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  config = config_for(create_plan(), 1, 0);
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  config = config_for(create_plan(), 1, SIMD_JSON_STREAM_MAX_BATCH_BYTES + 1);
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  config = config_for(create_plan(), 1, 1);
  config.parent_generation = 0;
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  config = config_for(create_plan(), 1, 1);
  config.reserved = 1;
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  config = config_for(create_plan(), 1, 1);
  target.segments = NULL;
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  target.segments = &segment;
  segment.reserved = 1;
  config = config_for(create_plan(), 1, 1);
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  segment.reserved = 0;
  segment.tag = UINT32_MAX;
  config = config_for(create_plan(), 1, 1);
  CHECK(expect_invalid(fixture, &target, &config) == 0);
  segment.tag = SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY;
  segment.key_length = 2;
  config = config_for(create_plan(), 1, 1);
  CHECK(expect_invalid(fixture, &target, &config) == 0);

  target = (simd_json_stream_target){NULL, 0, NULL, 0};
  config = config_for(create_plan(), 1, 1);
  status = simd_json_stream_cursor_create(fixture->document, &target, &config,
                                          NULL);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT);
  simd_json_projection_plan_destroy(config.projection_plan);
  status = simd_json_stream_cursor_create(NULL, &target, NULL, &cursor);
  CHECK(status.code == SIMD_JSON_STATUS_INVALID_ARGUMENT && cursor == NULL);
  return 0;
}

static uint32_t cancellation(void *context) {
  return *(const uint32_t *)context;
}

typedef struct counted_cancellation {
  uint32_t calls;
  uint32_t cancel_after;
} counted_cancellation;

static uint32_t cancel_after_count(void *context) {
  counted_cancellation *counted = (counted_cancellation *)context;
  counted->calls += 1;
  return counted->calls >= counted->cancel_after ? 1 : 0;
}

static int cancellation_matrix(void) {
  document_fixture fixture;
  static const uint8_t target_key[] = "rows";
  const simd_json_projection_segment target_segment = {
      SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0,
      sizeof(target_key) - 1, 0};
  const simd_json_stream_target target = {
      &target_segment, 1, target_key, sizeof(target_key) - 1};
  simd_json_stream_cursor_config config = config_for(create_plan(), 2, 1024);
  simd_json_stream_cursor *cursor = NULL;
  simd_json_stream_row rows[2];
  simd_json_result_slot slots[2];
  uint8_t bytes[32];
  simd_json_stream_batch_storage batch = {
      rows, 2, slots, 2, bytes, sizeof(bytes), 0, 0, 0, 0, 0};
  counted_cancellation counted = {0, 5};
  simd_json_cancellation_probe probe = {&counted, cancel_after_count};

  CHECK(open_document(&fixture) == 0);
  CHECK(simd_json_stream_cursor_create(fixture.document, &target, &config,
                                       &cursor)
            .code == SIMD_JSON_STATUS_OK);
  const simd_json_stream_status status =
      simd_json_stream_next_batch(cursor, &probe, &batch);
  CHECK(status.code == SIMD_JSON_STATUS_CANCELLED && status.array_index == 1);
  CHECK(batch.produced_rows == 0 && batch.produced_slots == 0 &&
        batch.encoded_bytes == 0 && batch.done == SIMD_JSON_STREAM_NOT_DONE);
  CHECK(simd_json_stream_next_batch(cursor, NULL, &batch).code ==
        SIMD_JSON_STATUS_CANCELLED);
  simd_json_stream_cursor_destroy(cursor);
  close_document(&fixture);
  CHECK(stream_is_quiescent() && projection_is_quiescent());
  return 0;
}

static int state_and_storage_matrix(document_fixture *fixture) {
  static const uint8_t target_key[] = "rows";
  const simd_json_projection_segment target_segment = {
      SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY, 0, 0,
      sizeof(target_key) - 1, 0};
  const simd_json_stream_target target = {
      &target_segment, 1, target_key, sizeof(target_key) - 1};
  simd_json_stream_cursor_config config = config_for(create_plan(), 2, 1024);
  simd_json_stream_cursor *cursor = NULL;
  simd_json_stream_row rows[2];
  simd_json_result_slot slots[2];
  uint8_t bytes[16];
  simd_json_stream_batch_storage batch = {
      rows, 2, slots, 2, bytes, sizeof(bytes), 99, 99, 99, 1, 0};
  simd_json_stream_status status;
  uint32_t cancelled = 0;
  simd_json_cancellation_probe probe = {&cancelled, cancellation};

  CHECK(config.projection_plan != NULL);
  status = simd_json_stream_cursor_create(fixture->document, &target, &config,
                                          &cursor);
  CHECK(status.code == SIMD_JSON_STATUS_OK && cursor != NULL);
  status = simd_json_stream_next_batch(cursor, NULL, &batch);
  CHECK(status.code == SIMD_JSON_STATUS_OK);
  CHECK(batch.produced_rows == 1 && batch.produced_slots == 1 &&
        batch.encoded_bytes == sizeof(simd_json_stream_row) +
                                   sizeof(simd_json_result_slot) &&
        batch.done == SIMD_JSON_STREAM_DONE);
  CHECK(rows[0].array_index == 0 && rows[0].slot_offset == 0 &&
        rows[0].slot_count == 1);
  CHECK(slots[0].tag == SIMD_JSON_RESULT_SIGNED_INTEGER &&
        slots[0].value.signed_integer == 1);
  cancelled = 2;
  CHECK(simd_json_stream_next_batch(cursor, &probe, &batch).code ==
        SIMD_JSON_STATUS_INVALID_ARGUMENT);
  cancelled = 1;
  CHECK(simd_json_stream_next_batch(cursor, &probe, &batch).code ==
        SIMD_JSON_STATUS_CANCELLED);
  CHECK(simd_json_stream_next_batch(cursor, NULL, &batch).code ==
        SIMD_JSON_STATUS_OK);
  CHECK(simd_json_test_stream_state_set(cursor, SIMD_JSON_STREAM_CURSOR_DONE));
  CHECK(simd_json_stream_next_batch(cursor, NULL, &batch).code ==
        SIMD_JSON_STATUS_OK);
  CHECK(batch.done == SIMD_JSON_STREAM_DONE);
  CHECK(simd_json_test_stream_state_set(cursor,
                                        SIMD_JSON_STREAM_CURSOR_RUNNING));
  CHECK(simd_json_stream_next_batch(cursor, NULL, &batch).code ==
        SIMD_JSON_STATUS_CURSOR_STATE);
  CHECK(simd_json_test_stream_state_set(cursor, SIMD_JSON_STREAM_CURSOR_CLOSED));
  CHECK(simd_json_stream_next_batch(cursor, NULL, &batch).code ==
        SIMD_JSON_STATUS_CURSOR_STATE);
  batch.reserved = 1;
  CHECK(simd_json_stream_next_batch(cursor, NULL, &batch).code ==
        SIMD_JSON_STATUS_INVALID_ARGUMENT);
  simd_json_stream_cursor_destroy(cursor);
  CHECK(stream_is_quiescent() && projection_is_quiescent());
  return 0;
}

static int exception_matrix(document_fixture *fixture) {
  static const int32_t kinds[] = {
      SIMD_JSON_TEST_FAILURE_SIMDJSON, SIMD_JSON_TEST_FAILURE_BAD_ALLOC,
      SIMD_JSON_TEST_FAILURE_STANDARD, SIMD_JSON_TEST_FAILURE_UNKNOWN};
  const simd_json_stream_target target = {NULL, 0, NULL, 0};
  size_t kind_index;

  for (kind_index = 0; kind_index < sizeof(kinds) / sizeof(kinds[0]);
       ++kind_index) {
    uint64_t checkpoint;
    for (checkpoint = 0; checkpoint <= 4; ++checkpoint) {
      simd_json_stream_cursor_config config =
          config_for(create_plan(), 1, 1);
      simd_json_stream_cursor *cursor = NULL;
      simd_json_stream_status status;
      CHECK(config.projection_plan != NULL);
      simd_json_test_stream_inject_failure(checkpoint, kinds[kind_index]);
      status = simd_json_stream_cursor_create(fixture->document, &target,
                                              &config, &cursor);
      simd_json_test_stream_clear_failure();
      if (checkpoint == 4) {
        CHECK(status.code == SIMD_JSON_STATUS_OK && cursor != NULL);
        CHECK(config.projection_plan == NULL);
        simd_json_stream_cursor_destroy(cursor);
      } else {
        CHECK(cursor == NULL);
        if (kinds[kind_index] == SIMD_JSON_TEST_FAILURE_SIMDJSON)
          CHECK(status.code == SIMD_JSON_STATUS_INVALID_JSON);
        else if (kinds[kind_index] == SIMD_JSON_TEST_FAILURE_BAD_ALLOC)
          CHECK(status.code == SIMD_JSON_STATUS_OUT_OF_MEMORY);
        else
          CHECK(status.code == SIMD_JSON_STATUS_INTERNAL_FAILURE);
        simd_json_projection_plan_destroy(config.projection_plan);
      }
      CHECK(stream_is_quiescent() && projection_is_quiescent());
    }
  }
  return 0;
}

int main(void) {
  document_fixture fixture;
  CHECK(SIMD_JSON_ABI_VERSION == 4);
  CHECK(SIMD_JSON_STREAM_MAX_BATCH_SIZE == 10000);
  CHECK(SIMD_JSON_STREAM_MAX_BATCH_BYTES == 67108864);
  CHECK(stream_is_quiescent() && projection_is_quiescent());
  CHECK(open_document(&fixture) == 0);
  CHECK(construction_and_copy_matrix(&fixture) == 0);
  CHECK(invalid_matrix(&fixture) == 0);
  CHECK(state_and_storage_matrix(&fixture) == 0);
  CHECK(exception_matrix(&fixture) == 0);
  close_document(&fixture);
  CHECK(cancellation_matrix() == 0);
  simd_json_stream_cursor_destroy(NULL);
  CHECK(stream_is_quiescent() && projection_is_quiescent());
  puts("stream cursor conformance passed abi=4");
  return 0;
}
