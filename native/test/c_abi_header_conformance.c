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

  (void)parser_create;
  (void)parser_destroy;
  (void)document_open;
  (void)document_destroy;

  return (SIMD_JSON_ABI_VERSION == UINT32_C(1) &&
          SIMD_JSON_REQUIRED_PADDING == UINT64_C(64) &&
          SIMD_JSON_STATUS_INTERNAL_FAILURE == INT32_C(6))
             ? 0
             : 1;
}
