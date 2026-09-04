#include "../include/simd_json_abi.h"

/* covers: simd_json.decode_api.iterative_limits simd_json.native_build_and_abi.opaque_c_contract simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.partial_failure_cleanup */

#include <atomic>
#include <cstdint>
#include <exception>
#include <memory>
#include <new>
#include <vector>

namespace {

constexpr simd_json_status make_status(simd_json_status_code code) noexcept {
  return {code, SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
          SIMD_JSON_BYTE_OFFSET_UNAVAILABLE};
}

enum class frame_kind : uint32_t { object, array };

struct materializer_frame {
  frame_kind kind;
  uint32_t reserved;
  uint64_t depth;
  uint64_t edge_offset;
  uint64_t pending_key_offset;
};

bool config_is_valid(const simd_json_decode_config &config) noexcept {
  return config.max_depth != 0 && config.max_depth <= SIMD_JSON_MAX_DEPTH &&
         config.max_container_entries != 0 &&
         config.max_container_entries <= SIMD_JSON_DECODE_MAX_CONTAINER_ENTRIES &&
         config.max_string_bytes != 0 &&
         config.max_string_bytes <= SIMD_JSON_DECODE_MAX_STRING_BYTES &&
         config.max_output_bytes != 0 &&
         config.max_output_bytes <= SIMD_JSON_DECODE_MAX_OUTPUT_BYTES &&
         config.reserved == 0;
}

simd_json_status current_exception_status() noexcept {
  try {
    throw;
  } catch (const std::bad_alloc &) {
    return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY);
  } catch (const std::exception &) {
    return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  } catch (...) {
    return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  }
}

}  // namespace

struct simd_json_decode_result {
  std::vector<simd_json_decode_node> nodes;
  std::vector<simd_json_decode_edge> edges;
  std::vector<uint8_t> copied_bytes;
  uint64_t root_node = UINT64_MAX;
};

struct simd_json_decode_materializer {
  simd_json_document *document = nullptr;
  simd_json_decode_config config{};
  std::vector<materializer_frame> frames;
  std::atomic<bool> consumed{false};
};

extern "C" simd_json_status simd_json_decode_materializer_create(
    simd_json_document *document, const simd_json_decode_config *config,
    simd_json_decode_materializer **out_materializer) noexcept {
  if (out_materializer == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }
  *out_materializer = nullptr;
  if (document == nullptr || config == nullptr || !config_is_valid(*config)) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  try {
    auto owner = std::make_unique<simd_json_decode_materializer>();
    owner->document = document;
    owner->config = *config;
    owner->frames.reserve(static_cast<size_t>(config->max_depth));
    *out_materializer = owner.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    return current_exception_status();
  }
}

extern "C" void simd_json_decode_materializer_destroy(
    simd_json_decode_materializer *materializer) noexcept {
  try {
    delete materializer;
  } catch (...) {
  }
}

extern "C" simd_json_status simd_json_decode_materializer_execute(
    simd_json_decode_materializer *materializer,
    const simd_json_cancellation_probe *cancellation,
    simd_json_decode_result **out_result) noexcept {
  if (out_result == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }
  *out_result = nullptr;
  if (materializer == nullptr ||
      (cancellation != nullptr && cancellation->check == nullptr)) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }
  if (cancellation != nullptr) {
    try {
      if (cancellation->check(cancellation->context) != 0) {
        return make_status(SIMD_JSON_STATUS_CANCELLED);
      }
    } catch (...) {
      return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
    }
  }

  bool expected = false;
  if (!materializer->consumed.compare_exchange_strong(
          expected, true, std::memory_order_acq_rel,
          std::memory_order_acquire)) {
    return make_status(SIMD_JSON_STATUS_CURSOR_CONSUMED);
  }

  try {
    /* Phase 2 publishes the empty owner; Phase 3 fills it transactionally. */
    auto result = std::make_unique<simd_json_decode_result>();
    *out_result = result.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    return current_exception_status();
  }
}

extern "C" simd_json_status simd_json_decode_result_read(
    const simd_json_decode_result *result,
    simd_json_decode_result_view *out_view) noexcept {
  if (out_view == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }
  *out_view = {};
  out_view->root_node = UINT64_MAX;
  if (result == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }
  try {
    out_view->nodes = result->nodes.empty() ? nullptr : result->nodes.data();
    out_view->node_count = static_cast<uint64_t>(result->nodes.size());
    out_view->edges = result->edges.empty() ? nullptr : result->edges.data();
    out_view->edge_count = static_cast<uint64_t>(result->edges.size());
    out_view->copied_bytes =
        result->copied_bytes.empty() ? nullptr : result->copied_bytes.data();
    out_view->copied_byte_count =
        static_cast<uint64_t>(result->copied_bytes.size());
    out_view->root_node = result->root_node;
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    *out_view = {};
    out_view->root_node = UINT64_MAX;
    return current_exception_status();
  }
}

extern "C" void simd_json_decode_result_destroy(
    simd_json_decode_result *result) noexcept {
  try {
    delete result;
  } catch (...) {
  }
}
