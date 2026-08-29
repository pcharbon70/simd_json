#ifndef SIMD_JSON_NIF_INTERNAL_H
#define SIMD_JSON_NIF_INTERNAL_H

/* covers: simd_json.native_build_and_abi.layered_boundary simd_json.native_build_and_abi.opaque_c_contract simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.symbol_visibility simd_json.document_resource.input_lifetime */

/*
 * Private declarations used only inside the Zigler NIF. They are deliberately
 * absent from simd_json_abi.h and have hidden visibility in the linked object.
 */
#include "simd_json_abi.h"

#if defined(__GNUC__)
#define SIMD_JSON_NIF_INTERNAL_VISIBILITY __attribute__((visibility("hidden")))
#else
#define SIMD_JSON_NIF_INTERNAL_VISIBILITY
#endif

#ifdef __cplusplus
extern "C" {
#define SIMD_JSON_NIF_INTERNAL_NOEXCEPT noexcept
#else
#define SIMD_JSON_NIF_INTERNAL_NOEXCEPT
#endif

SIMD_JSON_NIF_INTERNAL_VISIBILITY uint32_t
simd_json_nif_document_uses_owned_input(
    simd_json_document *document,
    const uint8_t *data,
    uint64_t logical_length) SIMD_JSON_NIF_INTERNAL_NOEXCEPT;

SIMD_JSON_NIF_INTERNAL_VISIBILITY simd_json_status
simd_json_nif_document_revalidate(
    simd_json_document *document) SIMD_JSON_NIF_INTERNAL_NOEXCEPT;

/*
 * The projection worker installs one operation-owned probe before cursor
 * access and clears it after execution. The callback performs the atomic read
 * appropriate to the owning runtime; the C++ traversal invokes it only at
 * bounded safe points between simdjson calls.
 */
typedef uint32_t (*simd_json_nif_cancellation_probe)(void *context);

SIMD_JSON_NIF_INTERNAL_VISIBILITY void
simd_json_nif_projection_set_cancellation(
    simd_json_document *document,
    void *context,
    simd_json_nif_cancellation_probe probe) SIMD_JSON_NIF_INTERNAL_NOEXCEPT;

SIMD_JSON_NIF_INTERNAL_VISIBILITY void
simd_json_nif_projection_clear_cancellation(
    simd_json_document *document) SIMD_JSON_NIF_INTERNAL_NOEXCEPT;

#undef SIMD_JSON_NIF_INTERNAL_NOEXCEPT
#undef SIMD_JSON_NIF_INTERNAL_VISIBILITY

#ifdef __cplusplus
}
#endif

#endif
