#ifndef SIMD_JSON_NATIVE_INTERNAL_HPP
#define SIMD_JSON_NATIVE_INTERNAL_HPP

#include "../include/simd_json_abi.h"
#include "../vendor/simdjson/simdjson.h"

#include <cstdint>

/*
 * C++-only coordination between the opaque document owner and the projection
 * engine. These declarations are implementation details, use C++ linkage, and
 * are compiled with hidden visibility.
 */
namespace simd_json_native {

simdjson::ondemand::document *document_value(
    simd_json_document *document) noexcept;
const uint8_t *document_data(const simd_json_document *document) noexcept;
uint64_t document_logical_length(
    const simd_json_document *document) noexcept;
bool claim_projection_cursor(simd_json_document *document) noexcept;
bool projection_cancelled(simd_json_document *document) noexcept;

}  // namespace simd_json_native

#endif
