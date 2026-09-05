#include "../include/simd_json_abi.h"
#include "../vendor/simdjson/simdjson.h"
#include "simd_json_native_internal.hpp"

/* covers: simd_json.decode_api.complete_values simd_json.decode_api.iterative_limits simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.partial_failure_cleanup */

#include <atomic>
#include <cstdint>
#include <exception>
#include <memory>
#include <new>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace {
constexpr simd_json_status make_status(
    simd_json_status_code code,
    int32_t native_code = SIMD_JSON_NATIVE_CODE_UNAVAILABLE) noexcept {
  return {code, native_code, SIMD_JSON_BYTE_OFFSET_UNAVAILABLE};
}

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

simd_json_status status_from_simdjson(simdjson::error_code error) noexcept {
  simd_json_status_code code = SIMD_JSON_STATUS_INVALID_JSON;
  switch (error) {
    case simdjson::SUCCESS: return make_status(SIMD_JSON_STATUS_OK);
    case simdjson::UTF8_ERROR: code = SIMD_JSON_STATUS_INVALID_UTF8; break;
    case simdjson::EMPTY:
    case simdjson::UNCLOSED_STRING:
    case simdjson::INCOMPLETE_ARRAY_OR_OBJECT:
      code = SIMD_JSON_STATUS_UNEXPECTED_EOF;
      break;
    case simdjson::MEMALLOC:
    case simdjson::OUT_OF_CAPACITY:
      code = SIMD_JSON_STATUS_OUT_OF_MEMORY;
      break;
    case simdjson::BIGINT_ERROR:
    case simdjson::NUMBER_OUT_OF_RANGE:
      code = SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE;
      break;
    default: break;
  }
  return make_status(code, static_cast<int32_t>(error));
}

simd_json_status current_exception_status() noexcept {
  try { throw; }
  catch (const simdjson::simdjson_error &error) {
    return status_from_simdjson(error.error());
  } catch (const std::bad_alloc &) {
    return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY);
  } catch (...) {
    return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  }
}

struct object_frame {
  simdjson::ondemand::object_iterator position;
  simdjson::ondemand::object_iterator end;
  uint64_t node_index;
  uint64_t depth;
  bool awaiting_child = false;
  std::vector<simd_json_decode_edge> pending_edges;
};
struct array_frame {
  simdjson::ondemand::array_iterator position;
  simdjson::ondemand::array_iterator end;
  uint64_t node_index;
  uint64_t depth;
  bool awaiting_child = false;
  std::vector<simd_json_decode_edge> pending_edges;
};
using materializer_frame = std::variant<object_frame, array_frame>;
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

namespace {
bool cancellation_requested(const simd_json_cancellation_probe *probe) {
  return probe != nullptr && probe->check(probe->context) != 0;
}

simd_json_status append_node(simd_json_decode_result &result,
                             simd_json_decode_node node,
                             const simd_json_decode_config &config,
                             uint64_t &out_index) {
  const uint64_t count = static_cast<uint64_t>(result.nodes.size());
  if (count >= config.max_output_bytes / sizeof(node))
    return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY);
  result.nodes.push_back(node);
  out_index = count;
  return make_status(SIMD_JSON_STATUS_OK);
}

simd_json_status open_value(simd_json_decode_materializer &materializer,
                            simd_json_decode_result &result,
                            simdjson::ondemand::value value,
                            uint64_t depth,
                            uint64_t &out_node) {
  if (depth > materializer.config.max_depth)
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  simdjson::ondemand::json_type type;
  simdjson::error_code error = value.type().get(type);
  if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  simd_json_decode_node node{};

  if (type == simdjson::ondemand::json_type::object) {
    node.tag = SIMD_JSON_DECODE_NODE_OBJECT;
    simd_json_status status = append_node(result, node, materializer.config, out_node);
    if (status.code != SIMD_JSON_STATUS_OK) return status;
    simdjson::ondemand::object object;
    if ((error = value.get_object().get(object)) != simdjson::SUCCESS)
      return status_from_simdjson(error);
    simdjson::ondemand::object_iterator position, end;
    if ((error = object.begin().get(position)) != simdjson::SUCCESS ||
        (error = object.end().get(end)) != simdjson::SUCCESS)
      return status_from_simdjson(error);
    materializer.frames.emplace_back(
        object_frame{position, end, out_node, depth, false, {}});
    return make_status(SIMD_JSON_STATUS_OK);
  }
  if (type == simdjson::ondemand::json_type::array) {
    node.tag = SIMD_JSON_DECODE_NODE_ARRAY;
    simd_json_status status = append_node(result, node, materializer.config, out_node);
    if (status.code != SIMD_JSON_STATUS_OK) return status;
    simdjson::ondemand::array array;
    if ((error = value.get_array().get(array)) != simdjson::SUCCESS)
      return status_from_simdjson(error);
    simdjson::ondemand::array_iterator position, end;
    if ((error = array.begin().get(position)) != simdjson::SUCCESS ||
        (error = array.end().get(end)) != simdjson::SUCCESS)
      return status_from_simdjson(error);
    materializer.frames.emplace_back(
        array_frame{position, end, out_node, depth, false, {}});
    return make_status(SIMD_JSON_STATUS_OK);
  }
  if (type == simdjson::ondemand::json_type::null) {
    bool is_null = false;
    error = value.is_null().get(is_null);
    if (error != simdjson::SUCCESS || !is_null)
      return status_from_simdjson(error == simdjson::SUCCESS ? simdjson::TAPE_ERROR : error);
    node.tag = SIMD_JSON_DECODE_NODE_NULL;
    return append_node(result, node, materializer.config, out_node);
  }
  return make_status(SIMD_JSON_STATUS_INCORRECT_TYPE);
}

simd_json_status finalize_frame(simd_json_decode_result &result,
                                materializer_frame &frame,
                                const simd_json_decode_config &config) {
  return std::visit([&](auto &typed) -> simd_json_status {
    const uint64_t offset = static_cast<uint64_t>(result.edges.size());
    const uint64_t count = static_cast<uint64_t>(typed.pending_edges.size());
    if (count > config.max_container_entries ||
        count > config.max_output_bytes / sizeof(simd_json_decode_edge))
      return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY);
    result.edges.insert(result.edges.end(), typed.pending_edges.begin(),
                        typed.pending_edges.end());
    result.nodes[typed.node_index].edge_offset = offset;
    result.nodes[typed.node_index].edge_count = count;
    return make_status(SIMD_JSON_STATUS_OK);
  }, frame);
}

simd_json_status traverse(simd_json_decode_materializer &materializer,
                          simd_json_decode_result &result,
                          const simd_json_cancellation_probe *cancellation) {
  simdjson::ondemand::document *document = simd_json_native::document_value(materializer.document);
  if (document == nullptr) return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  simdjson::ondemand::value root;
  simdjson::error_code error = document->get_value().get(root);
  if (error != simdjson::SUCCESS) return status_from_simdjson(error);
  simd_json_status status = open_value(materializer, result, root, 1, result.root_node);
  if (status.code != SIMD_JSON_STATUS_OK) return status;

  while (!materializer.frames.empty()) {
    if (cancellation_requested(cancellation)) return make_status(SIMD_JSON_STATUS_CANCELLED);
    bool complete = false;
    std::visit([&](auto &frame) {
      if (frame.awaiting_child) { ++frame.position; frame.awaiting_child = false; }
      complete = frame.position == frame.end;
    }, materializer.frames.back());
    if (complete) {
      status = finalize_frame(result, materializer.frames.back(), materializer.config);
      if (status.code != SIMD_JSON_STATUS_OK) return status;
      materializer.frames.pop_back();
      continue;
    }

    const size_t parent_index = materializer.frames.size() - 1;
    uint64_t child_node = UINT64_MAX;
    if (auto *parent = std::get_if<object_frame>(&materializer.frames[parent_index])) {
      if (parent->pending_edges.size() >= materializer.config.max_container_entries)
        return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY);
      simdjson::ondemand::field field;
      if ((error = std::move(*parent->position).get(field)) != simdjson::SUCCESS)
        return status_from_simdjson(error);
      std::string_view key;
      if ((error = field.unescaped_key().get(key)) != simdjson::SUCCESS)
        return status_from_simdjson(error);
      const uint64_t key_offset = static_cast<uint64_t>(result.copied_bytes.size());
      result.copied_bytes.insert(result.copied_bytes.end(), key.begin(), key.end());
      const uint64_t depth = parent->depth + 1;
      parent->awaiting_child = true;
      simdjson::ondemand::value child = field.value();
      status = open_value(materializer, result, child, depth, child_node);
      if (status.code != SIMD_JSON_STATUS_OK) return status;
      std::get<object_frame>(materializer.frames[parent_index]).pending_edges.push_back(
          {key_offset, static_cast<uint64_t>(key.size()), child_node, 0});
    } else {
      auto &array_parent = std::get<array_frame>(materializer.frames[parent_index]);
      if (array_parent.pending_edges.size() >= materializer.config.max_container_entries)
        return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY);
      simdjson::ondemand::value child;
      if ((error = (*array_parent.position).get(child)) != simdjson::SUCCESS)
        return status_from_simdjson(error);
      const uint64_t depth = array_parent.depth + 1;
      array_parent.awaiting_child = true;
      status = open_value(materializer, result, child, depth, child_node);
      if (status.code != SIMD_JSON_STATUS_OK) return status;
      std::get<array_frame>(materializer.frames[parent_index]).pending_edges.push_back(
          {SIMD_JSON_DECODE_BYTE_RANGE_UNAVAILABLE,
           SIMD_JSON_DECODE_BYTE_RANGE_UNAVAILABLE, child_node, 0});
    }
  }
  return make_status(SIMD_JSON_STATUS_OK);
}
}  // namespace

extern "C" simd_json_status simd_json_decode_materializer_create(
    simd_json_document *document, const simd_json_decode_config *config,
    simd_json_decode_materializer **out_materializer) noexcept {
  if (out_materializer == nullptr) return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  *out_materializer = nullptr;
  if (document == nullptr || config == nullptr || !config_is_valid(*config))
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  try {
    auto owner = std::make_unique<simd_json_decode_materializer>();
    owner->document = document;
    owner->config = *config;
    owner->frames.reserve(static_cast<size_t>(config->max_depth));
    *out_materializer = owner.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) { return current_exception_status(); }
}

extern "C" void simd_json_decode_materializer_destroy(
    simd_json_decode_materializer *materializer) noexcept {
  try { delete materializer; } catch (...) {}
}

extern "C" simd_json_status simd_json_decode_materializer_execute(
    simd_json_decode_materializer *materializer,
    const simd_json_cancellation_probe *cancellation,
    simd_json_decode_result **out_result) noexcept {
  if (out_result == nullptr) return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  *out_result = nullptr;
  if (materializer == nullptr || (cancellation != nullptr && cancellation->check == nullptr))
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  try {
    if (cancellation_requested(cancellation)) return make_status(SIMD_JSON_STATUS_CANCELLED);
  } catch (...) { return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE); }
  bool expected = false;
  if (!materializer->consumed.compare_exchange_strong(expected, true,
          std::memory_order_acq_rel, std::memory_order_acquire))
    return make_status(SIMD_JSON_STATUS_CURSOR_CONSUMED);
  try {
    auto result = std::make_unique<simd_json_decode_result>();
    simd_json_status status = traverse(*materializer, *result, cancellation);
    materializer->frames.clear();
    if (status.code != SIMD_JSON_STATUS_OK) return status;
    *out_result = result.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    materializer->frames.clear();
    return current_exception_status();
  }
}

extern "C" simd_json_status simd_json_decode_result_read(
    const simd_json_decode_result *result, simd_json_decode_result_view *out_view) noexcept {
  if (out_view == nullptr) return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  *out_view = {};
  out_view->root_node = UINT64_MAX;
  if (result == nullptr) return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  try {
    out_view->nodes = result->nodes.empty() ? nullptr : result->nodes.data();
    out_view->node_count = static_cast<uint64_t>(result->nodes.size());
    out_view->edges = result->edges.empty() ? nullptr : result->edges.data();
    out_view->edge_count = static_cast<uint64_t>(result->edges.size());
    out_view->copied_bytes = result->copied_bytes.empty() ? nullptr : result->copied_bytes.data();
    out_view->copied_byte_count = static_cast<uint64_t>(result->copied_bytes.size());
    out_view->root_node = result->root_node;
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    *out_view = {};
    out_view->root_node = UINT64_MAX;
    return current_exception_status();
  }
}

extern "C" void simd_json_decode_result_destroy(simd_json_decode_result *result) noexcept {
  try { delete result; } catch (...) {}
}
