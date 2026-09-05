#include "simd_json_abi.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) { \
  fprintf(stderr, "decode materializer failure at line %d\n", __LINE__); \
  return 1; } } while (0)

static uint32_t cancel(void *context) { return *(uint32_t *)context; }

int main(void) {
  static const uint8_t source[] = "{\"a\":[],\"b\":[{},null]}";
  const uint64_t length = sizeof(source) - 1;
  uint8_t *storage = calloc((size_t)(length + SIMD_JSON_REQUIRED_PADDING), 1);
  simd_json_parser *parser = NULL;
  simd_json_document *document = NULL;
  simd_json_decode_materializer *materializer = NULL;
  simd_json_decode_result *result = NULL;
  simd_json_decode_result_view view;
  simd_json_decode_config config = {32, 100, 1024, 4096, 0};
  simd_json_status status;
  uint32_t cancelled = 0;
  simd_json_cancellation_probe probe = {&cancelled, cancel};

  CHECK(storage != NULL);
  memcpy(storage, source, (size_t)length);
  CHECK(simd_json_parser_create(&parser).code == SIMD_JSON_STATUS_OK);
  CHECK(simd_json_document_open(parser, storage, length,
                                length + SIMD_JSON_REQUIRED_PADDING,
                                &document).code == SIMD_JSON_STATUS_OK);

  status = simd_json_decode_materializer_create(document, &config, &materializer);
  CHECK(status.code == SIMD_JSON_STATUS_OK && materializer != NULL);
  status = simd_json_decode_materializer_execute(materializer, &probe, &result);
  CHECK(status.code == SIMD_JSON_STATUS_OK && result != NULL);
  memset(&view, 0xff, sizeof(view));
  CHECK(simd_json_decode_result_read(result, &view).code == SIMD_JSON_STATUS_OK);
  CHECK(view.nodes != NULL && view.node_count == 5 && view.edges != NULL &&
        view.edge_count == 4 && view.copied_bytes != NULL &&
        view.copied_byte_count == 2 && view.root_node == 0 && view.reserved == 0);
  CHECK(view.nodes[0].tag == SIMD_JSON_DECODE_NODE_OBJECT &&
        view.nodes[0].edge_offset == 2 && view.nodes[0].edge_count == 2);
  CHECK(view.nodes[1].tag == SIMD_JSON_DECODE_NODE_ARRAY &&
        view.nodes[1].edge_count == 0);
  CHECK(view.nodes[2].tag == SIMD_JSON_DECODE_NODE_ARRAY &&
        view.nodes[2].edge_offset == 0 && view.nodes[2].edge_count == 2);
  CHECK(view.nodes[3].tag == SIMD_JSON_DECODE_NODE_OBJECT &&
        view.nodes[4].tag == SIMD_JSON_DECODE_NODE_NULL);
  CHECK(view.edges[0].value_node == 3 && view.edges[1].value_node == 4 &&
        view.edges[2].value_node == 1 && view.edges[3].value_node == 2);
  CHECK(view.copied_bytes[0] == 'a' && view.copied_bytes[1] == 'b');
  simd_json_decode_result_destroy(result);
  result = (simd_json_decode_result *)(uintptr_t)UINTPTR_MAX;
  CHECK(simd_json_decode_materializer_execute(materializer, NULL, &result).code ==
        SIMD_JSON_STATUS_CURSOR_CONSUMED);
  CHECK(result == NULL);
  simd_json_decode_result_destroy(NULL);
  simd_json_decode_materializer_destroy(materializer);

  materializer = NULL;
  CHECK(simd_json_decode_materializer_create(document, &config, &materializer).code ==
        SIMD_JSON_STATUS_OK);
  cancelled = 1;
  CHECK(simd_json_decode_materializer_execute(materializer, &probe, &result).code ==
        SIMD_JSON_STATUS_CANCELLED);
  CHECK(result == NULL);
  simd_json_decode_materializer_destroy(materializer);

  simd_json_document_destroy(document);
  simd_json_parser_destroy(parser);
  parser = NULL;
  document = NULL;
  CHECK(simd_json_parser_create(&parser).code == SIMD_JSON_STATUS_OK);
  CHECK(simd_json_document_open(parser, storage, length,
                                length + SIMD_JSON_REQUIRED_PADDING,
                                &document).code == SIMD_JSON_STATUS_OK);
  config.max_depth = 2;
  materializer = NULL;
  CHECK(simd_json_decode_materializer_create(document, &config, &materializer).code ==
        SIMD_JSON_STATUS_OK);
  CHECK(simd_json_decode_materializer_execute(materializer, NULL, &result).code ==
        SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(result == NULL);
  simd_json_decode_materializer_destroy(materializer);

  config.max_depth = 32;
  config.reserved = 1;
  materializer = (simd_json_decode_materializer *)(uintptr_t)UINTPTR_MAX;
  CHECK(simd_json_decode_materializer_create(document, &config, &materializer).code ==
        SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(materializer == NULL);
  CHECK(simd_json_decode_result_read(NULL, &view).code ==
        SIMD_JSON_STATUS_INVALID_ARGUMENT);
  CHECK(view.root_node == UINT64_MAX);

  simd_json_document_destroy(document);
  simd_json_parser_destroy(parser);
  free(storage);
  return 0;
}
