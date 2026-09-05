#include "simd_json_abi.h"

/*
 * This translation unit is compiled as strict C11 with no C++ include path.
 * Merely assigning the exported functions proves that the complete ABI surface
 * has C-compatible declarations.
 */
int main(void) {
  simd_json_status (*parser_create)(simd_json_parser **) =
      simd_json_parser_create;
  void (*parser_destroy)(simd_json_parser *) = simd_json_parser_destroy;
  simd_json_status (*document_open)(simd_json_parser *, const uint8_t *,
                                    uint64_t, uint64_t,
                                    simd_json_document **) =
      simd_json_document_open;
  void (*document_destroy)(simd_json_document *) = simd_json_document_destroy;
  simd_json_projection_status (*plan_create)(
      const simd_json_projection_entry *, uint64_t,
      const simd_json_projection_segment *, uint64_t, const uint8_t *, uint64_t,
      simd_json_projection_plan **) = simd_json_projection_plan_create;
  void (*plan_destroy)(simd_json_projection_plan *) =
      simd_json_projection_plan_destroy;
  simd_json_projection_status (*projection_execute)(
      simd_json_document *, const simd_json_projection_plan *,
      simd_json_result_slot *, uint64_t) = simd_json_projection_execute;
  simd_json_stream_status (*cursor_create)(
      simd_json_document *, const simd_json_stream_target *,
      simd_json_stream_cursor_config *, simd_json_stream_cursor **) =
      simd_json_stream_cursor_create;
  void (*cursor_destroy)(simd_json_stream_cursor *) =
      simd_json_stream_cursor_destroy;
  simd_json_stream_status (*next_batch)(
      simd_json_stream_cursor *, const simd_json_cancellation_probe *,
      simd_json_stream_batch_storage *) = simd_json_stream_next_batch;
  simd_json_status (*materializer_create)(
      simd_json_document *, const simd_json_decode_config *,
      simd_json_decode_materializer **) = simd_json_decode_materializer_create;
  void (*materializer_destroy)(simd_json_decode_materializer *) =
      simd_json_decode_materializer_destroy;
  simd_json_status (*materializer_execute)(
      simd_json_decode_materializer *, const simd_json_cancellation_probe *,
      simd_json_decode_result **) = simd_json_decode_materializer_execute;
  simd_json_status (*result_read)(const simd_json_decode_result *,
                                  simd_json_decode_result_view *) =
      simd_json_decode_result_read;
  void (*result_destroy)(simd_json_decode_result *) =
      simd_json_decode_result_destroy;

  (void)parser_create;
  (void)parser_destroy;
  (void)document_open;
  (void)document_destroy;
  (void)plan_create;
  (void)plan_destroy;
  (void)projection_execute;
  (void)cursor_create;
  (void)cursor_destroy;
  (void)next_batch;
  (void)materializer_create;
  (void)materializer_destroy;
  (void)materializer_execute;
  (void)result_read;
  (void)result_destroy;

  return (SIMD_JSON_ABI_VERSION == UINT32_C(4) &&
          SIMD_JSON_REQUIRED_PADDING == UINT64_C(64) &&
          SIMD_JSON_MAX_DEPTH == UINT64_C(1024) &&
          SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE == UINT32_MAX &&
          SIMD_JSON_ARRAY_INDEX_UNAVAILABLE == UINT64_MAX &&
          SIMD_JSON_STATUS_CURSOR_STATE == INT32_C(14) &&
          SIMD_JSON_STATUS_MAX_OUTPUT_BYTES_EXCEEDED == INT32_C(18) &&
          SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY == UINT32_C(1) &&
          SIMD_JSON_RESULT_STRING == UINT32_C(6) &&
          SIMD_JSON_STREAM_CURSOR_CLOSED == UINT32_C(4) &&
          SIMD_JSON_DECODE_NODE_OBJECT == UINT32_C(1) &&
          SIMD_JSON_DECODE_NODE_NULL == UINT32_C(9))
             ? 0
             : 1;
}
