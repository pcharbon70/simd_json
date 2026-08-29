#include "../include/simd_json_nif_internal.h"
#include "../vendor/simdjson/simdjson.h"
#include "simd_json_native_internal.hpp"

/* covers: simd_json.native_build_and_abi.opaque_c_contract simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.partial_failure_cleanup simd_json.native_build_and_abi.symbol_visibility simd_json.document_resource.padded_owned_copy simd_json.document_resource.zero_copy_disabled simd_json.document_resource.input_lifetime simd_json.document_resource.partial_open_failure */

#include <cstddef>
#include <cstdint>
#include <atomic>
#include <exception>
#include <limits>
#include <memory>
#include <new>
#include <string_view>
#include <utility>

#ifdef SIMD_JSON_TESTING
#include "../test/include/simd_json_test_hooks.h"

#include <atomic>
#include <stdexcept>
#endif

static_assert(SIMD_JSON_REQUIRED_PADDING == simdjson::SIMDJSON_PADDING,
              "the C ABI padding constant must match the vendored simdjson");
static_assert(simdjson::NUM_ERROR_CODES <= std::numeric_limits<int32_t>::max(),
              "simdjson error codes must fit the diagnostic field");

/*
 * Zig links its bundled libc++ into the NIF. Its replaceable global allocation
 * operators are weak default-visible symbols even when every project source is
 * compiled with hidden visibility. On the qualified ELF target, mark those
 * references hidden so they cannot become accidental consumer ABI. The release
 * symbol allowlist fails if a future toolchain adds another exported operator.
 */
#if defined(__ELF__) && !defined(SIMD_JSON_ABI_BUILD_SHARED)
__asm__(".hidden blank_load\n"
        ".hidden blank_unload\n"
        ".hidden blank_upgrade\n"
        ".hidden sema\n"
        ".hidden _Znwm\n"
        ".hidden _Znam\n"
        ".hidden _ZdlPv\n"
        ".hidden _ZdaPv\n"
        ".hidden _ZdlPvm\n"
        ".hidden _ZdaPvm\n"
        ".hidden _ZnwmSt11align_val_t\n"
        ".hidden _ZnamSt11align_val_t\n"
        ".hidden _ZdlPvSt11align_val_t\n"
        ".hidden _ZdaPvSt11align_val_t\n"
        ".hidden _ZdlPvmSt11align_val_t\n"
        ".hidden _ZdaPvmSt11align_val_t\n");
#endif

namespace {

constexpr int32_t point_before_parser_allocation = 1;
constexpr int32_t point_after_parser_allocation = 2;
constexpr int32_t point_during_document_construction = 3;
constexpr int32_t point_before_document_publication = 4;

#ifdef SIMD_JSON_TESTING
std::atomic<uint64_t> injected_failure{0};
std::atomic<uint64_t> live_parsers{0};
std::atomic<uint64_t> live_documents{0};

constexpr uint64_t pack_failure(int32_t point, int32_t kind) noexcept {
  return (static_cast<uint64_t>(static_cast<uint32_t>(point)) << 32U) |
         static_cast<uint32_t>(kind);
}

void maybe_inject(int32_t point) {
  uint64_t configured = injected_failure.load(std::memory_order_acquire);

  if (static_cast<int32_t>(configured >> 32U) != point || configured == 0) {
    return;
  }

  if (!injected_failure.compare_exchange_strong(
          configured, 0, std::memory_order_acq_rel,
          std::memory_order_acquire)) {
    return;
  }

  switch (static_cast<int32_t>(configured & UINT32_MAX)) {
    case SIMD_JSON_TEST_FAILURE_SIMDJSON:
      throw simdjson::simdjson_error(simdjson::TAPE_ERROR);
    case SIMD_JSON_TEST_FAILURE_BAD_ALLOC:
      throw std::bad_alloc{};
    case SIMD_JSON_TEST_FAILURE_STANDARD:
      throw std::runtime_error{"simd_json_test_standard_exception"};
    case SIMD_JSON_TEST_FAILURE_UNKNOWN:
      throw 1;
    default:
      return;
  }
}
#else
void maybe_inject(int32_t) noexcept {}
#endif

constexpr simd_json_status make_status(
    simd_json_status_code code,
    int32_t native_code = SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
    uint64_t byte_offset = SIMD_JSON_BYTE_OFFSET_UNAVAILABLE) noexcept {
  return {code, native_code, byte_offset};
}

simd_json_status status_from_simdjson(
    simdjson::error_code error,
    uint64_t byte_offset = SIMD_JSON_BYTE_OFFSET_UNAVAILABLE) noexcept {
  simd_json_status_code code = SIMD_JSON_STATUS_INVALID_JSON;

  switch (error) {
    case simdjson::SUCCESS:
      code = SIMD_JSON_STATUS_OK;
      byte_offset = SIMD_JSON_BYTE_OFFSET_UNAVAILABLE;
      break;
    case simdjson::UTF8_ERROR:
      code = SIMD_JSON_STATUS_INVALID_UTF8;
      break;
    case simdjson::EMPTY:
    case simdjson::UNCLOSED_STRING:
    case simdjson::INCOMPLETE_ARRAY_OR_OBJECT:
      code = SIMD_JSON_STATUS_UNEXPECTED_EOF;
      break;
    case simdjson::MEMALLOC:
    case simdjson::OUT_OF_CAPACITY:
      code = SIMD_JSON_STATUS_OUT_OF_MEMORY;
      break;
    case simdjson::CAPACITY:
    case simdjson::INSUFFICIENT_PADDING:
      code = SIMD_JSON_STATUS_INVALID_ARGUMENT;
      break;
    case simdjson::UNINITIALIZED:
    case simdjson::UNSUPPORTED_ARCHITECTURE:
    case simdjson::UNEXPECTED_ERROR:
    case simdjson::PARSER_IN_USE:
    case simdjson::OUT_OF_ORDER_ITERATION:
    case simdjson::OUT_OF_BOUNDS:
      code = SIMD_JSON_STATUS_INTERNAL_FAILURE;
      break;
    default:
      code = SIMD_JSON_STATUS_INVALID_JSON;
      break;
  }

  return make_status(code, static_cast<int32_t>(error), byte_offset);
}

constexpr bool exceeds_size_t(uint64_t value) noexcept {
  if constexpr (sizeof(size_t) >= sizeof(uint64_t)) {
    (void)value;
    return false;
  } else {
    return value > std::numeric_limits<size_t>::max();
  }
}

simdjson::error_code validate_value(simdjson::ondemand::value &value,
                                    uint64_t depth) noexcept;

simdjson::error_code validate_array(simdjson::ondemand::array &array,
                                    uint64_t depth) noexcept {
  for (auto child_result : array) {
    simdjson::ondemand::value child;
    simdjson::error_code error = child_result.get(child);

    if (error != simdjson::SUCCESS) {
      return error;
    }

    error = validate_value(child, depth + 1);

    if (error != simdjson::SUCCESS) {
      return error;
    }
  }

  return simdjson::SUCCESS;
}

simdjson::error_code validate_object(
    simdjson::ondemand::object &object,
    uint64_t depth) noexcept {
  for (auto field_result : object) {
    simdjson::ondemand::field field;
    simdjson::error_code error = std::move(field_result).get(field);

    if (error != simdjson::SUCCESS) {
      return error;
    }

    std::string_view key;
    error = field.unescaped_key().get(key);

    if (error != simdjson::SUCCESS) {
      return error;
    }

    (void)key;
    error = validate_value(field.value(), depth + 1);

    if (error != simdjson::SUCCESS) {
      return error;
    }
  }

  return simdjson::SUCCESS;
}

simdjson::error_code validate_value(simdjson::ondemand::value &value,
                                    uint64_t depth) noexcept {
  if (depth > SIMD_JSON_MAX_DEPTH) {
    return simdjson::DEPTH_ERROR;
  }

  simdjson::ondemand::json_type type;
  simdjson::error_code error = value.type().get(type);

  if (error != simdjson::SUCCESS) {
    return error;
  }

  switch (type) {
    case simdjson::ondemand::json_type::array: {
      simdjson::ondemand::array array;
      error = value.get_array().get(array);
      return error == simdjson::SUCCESS ? validate_array(array, depth) : error;
    }
    case simdjson::ondemand::json_type::object: {
      simdjson::ondemand::object object;
      error = value.get_object().get(object);
      return error == simdjson::SUCCESS ? validate_object(object, depth) : error;
    }
    case simdjson::ondemand::json_type::number: {
      simdjson::ondemand::number number;
      error = value.get_number().get(number);
      (void)number;
      return error;
    }
    case simdjson::ondemand::json_type::string: {
      std::string_view string;
      error = value.get_string().get(string);
      (void)string;
      return error;
    }
    case simdjson::ondemand::json_type::boolean: {
      bool boolean = false;
      error = value.get_bool().get(boolean);
      (void)boolean;
      return error;
    }
    case simdjson::ondemand::json_type::null: {
      bool is_null = false;
      error = value.is_null().get(is_null);
      return error == simdjson::SUCCESS && !is_null ? simdjson::TAPE_ERROR
                                                    : error;
    }
    case simdjson::ondemand::json_type::unknown:
      return simdjson::TAPE_ERROR;
  }

  return simdjson::UNEXPECTED_ERROR;
}

simdjson::error_code validate_document(
    simdjson::ondemand::document &document) noexcept {
  simdjson::ondemand::json_type type;
  simdjson::error_code error = document.type().get(type);

  if (error != simdjson::SUCCESS) {
    return error;
  }

  switch (type) {
    case simdjson::ondemand::json_type::array: {
      simdjson::ondemand::array array;
      error = document.get_array().get(array);
      error = error == simdjson::SUCCESS ? validate_array(array, 1) : error;
      break;
    }
    case simdjson::ondemand::json_type::object: {
      simdjson::ondemand::object object;
      error = document.get_object().get(object);
      error = error == simdjson::SUCCESS ? validate_object(object, 1) : error;
      break;
    }
    case simdjson::ondemand::json_type::number: {
      simdjson::ondemand::number number;
      error = document.get_number().get(number);
      (void)number;
      break;
    }
    case simdjson::ondemand::json_type::string: {
      std::string_view string;
      error = document.get_string().get(string);
      (void)string;
      break;
    }
    case simdjson::ondemand::json_type::boolean: {
      bool boolean = false;
      error = document.get_bool().get(boolean);
      (void)boolean;
      break;
    }
    case simdjson::ondemand::json_type::null: {
      bool is_null = false;
      error = document.is_null().get(is_null);

      if (error == simdjson::SUCCESS && !is_null) {
        error = simdjson::TAPE_ERROR;
      }
      break;
    }
    case simdjson::ondemand::json_type::unknown:
      error = simdjson::TAPE_ERROR;
      break;
  }

  if (error == simdjson::SUCCESS) {
    document.rewind();
  }

  return error;
}

uint64_t current_byte_offset(simdjson::ondemand::document &document,
                             const uint8_t *data,
                             uint64_t logical_length) noexcept {
  const char *location = nullptr;

  if (document.current_location().get(location) != simdjson::SUCCESS ||
      location == nullptr) {
    return SIMD_JSON_BYTE_OFFSET_UNAVAILABLE;
  }

  const uintptr_t start = reinterpret_cast<uintptr_t>(data);
  const uintptr_t current = reinterpret_cast<uintptr_t>(location);

  if (current < start || current - start > logical_length) {
    return SIMD_JSON_BYTE_OFFSET_UNAVAILABLE;
  }

  return static_cast<uint64_t>(current - start);
}

simd_json_status status_from_current_exception() noexcept {
  try {
    throw;
  } catch (const simdjson::simdjson_error &error) {
    return status_from_simdjson(error.error());
  } catch (const std::bad_alloc &) {
    return make_status(SIMD_JSON_STATUS_OUT_OF_MEMORY);
  } catch (const std::exception &) {
    return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  } catch (...) {
    return make_status(SIMD_JSON_STATUS_INTERNAL_FAILURE);
  }
}

}  // namespace

struct simd_json_parser {
  simdjson::ondemand::parser value;

#ifdef SIMD_JSON_TESTING
  simd_json_parser() noexcept { live_parsers.fetch_add(1); }
  ~simd_json_parser() { live_parsers.fetch_sub(1); }
#endif
};

struct simd_json_document {
  simd_json_parser *parser;
  simdjson::ondemand::document value;
  const uint8_t *data;
  uint64_t logical_length;
  std::atomic<bool> projection_cursor_claimed;
  void *projection_cancellation_context;
  simd_json_nif_cancellation_probe projection_cancellation_probe;

  simd_json_document(simd_json_parser *owner,
                     simdjson::ondemand::document &&document,
                     const uint8_t *input,
                     uint64_t length) noexcept
      : parser(owner),
        value(std::move(document)),
        data(input),
        logical_length(length),
        projection_cursor_claimed(false),
        projection_cancellation_context(nullptr),
        projection_cancellation_probe(nullptr) {
#ifdef SIMD_JSON_TESTING
    live_documents.fetch_add(1);
#endif
  }

#ifdef SIMD_JSON_TESTING
  ~simd_json_document() { live_documents.fetch_sub(1); }
#endif
};

namespace simd_json_native {

simdjson::ondemand::document *document_value(
    simd_json_document *document) noexcept {
  return document == nullptr ? nullptr : &document->value;
}

const uint8_t *document_data(const simd_json_document *document) noexcept {
  return document == nullptr ? nullptr : document->data;
}

uint64_t document_logical_length(
    const simd_json_document *document) noexcept {
  return document == nullptr ? 0 : document->logical_length;
}

bool claim_projection_cursor(simd_json_document *document) noexcept {
  return document != nullptr &&
         !document->projection_cursor_claimed.exchange(
             true, std::memory_order_acq_rel);
}

bool projection_cancelled(simd_json_document *document) noexcept {
  if (document == nullptr || document->projection_cancellation_probe == nullptr) {
    return false;
  }

  try {
    return document->projection_cancellation_probe(
               document->projection_cancellation_context) != UINT32_C(0);
  } catch (...) {
    return true;
  }
}

}  // namespace simd_json_native

extern "C" simd_json_status
simd_json_parser_create(simd_json_parser **out_parser) noexcept {
  if (out_parser == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  *out_parser = nullptr;

  try {
    maybe_inject(point_before_parser_allocation);
    auto parser = std::make_unique<simd_json_parser>();
    maybe_inject(point_after_parser_allocation);
    *out_parser = parser.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    return status_from_current_exception();
  }
}

extern "C" void simd_json_parser_destroy(simd_json_parser *parser) noexcept {
  try {
    delete parser;
  } catch (...) {
  }
}

extern "C" simd_json_status simd_json_document_open(
    simd_json_parser *parser,
    const uint8_t *data,
    uint64_t logical_length,
    uint64_t capacity,
    simd_json_document **out_document) noexcept {
  if (out_document == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  *out_document = nullptr;

  if (parser == nullptr || data == nullptr ||
      logical_length > simdjson::SIMDJSON_MAXSIZE_BYTES ||
      exceeds_size_t(logical_length) || exceeds_size_t(capacity) ||
      logical_length > UINT64_MAX - SIMD_JSON_REQUIRED_PADDING ||
      capacity < logical_length + SIMD_JSON_REQUIRED_PADDING) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  try {
    simdjson::ondemand::document parsed_document;
    simdjson::error_code error =
        parser->value
            .iterate(data, static_cast<size_t>(logical_length),
                     static_cast<size_t>(capacity))
            .get(parsed_document);

    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(error);
    }

    error = validate_document(parsed_document);

    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(
          error, current_byte_offset(parsed_document, data, logical_length));
    }

    maybe_inject(point_during_document_construction);
    auto document = std::make_unique<simd_json_document>(
        parser, std::move(parsed_document), data, logical_length);
    maybe_inject(point_before_document_publication);
    *out_document = document.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    return status_from_current_exception();
  }
}

extern "C" void
simd_json_document_destroy(simd_json_document *document) noexcept {
  try {
    delete document;
  } catch (...) {
  }
}

extern "C" uint32_t simd_json_nif_document_uses_owned_input(
    simd_json_document *document,
    const uint8_t *data,
    uint64_t logical_length) noexcept {
  try {
    return document != nullptr && document->data == data &&
                   document->logical_length == logical_length
               ? UINT32_C(1)
               : UINT32_C(0);
  } catch (...) {
    return UINT32_C(0);
  }
}

extern "C" simd_json_status simd_json_nif_document_revalidate(
    simd_json_document *document) noexcept {
  if (document == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  try {
    simdjson::error_code error = validate_document(document->value);
    return error == simdjson::SUCCESS
               ? make_status(SIMD_JSON_STATUS_OK)
               : status_from_simdjson(
                     error, current_byte_offset(document->value, document->data,
                                                document->logical_length));
  } catch (...) {
    return status_from_current_exception();
  }
}

extern "C" simd_json_status simd_json_nif_document_open_unvalidated(
    simd_json_parser *parser,
    const uint8_t *data,
    uint64_t logical_length,
    uint64_t capacity,
    simd_json_document **out_document) noexcept {
  if (out_document == nullptr) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }
  *out_document = nullptr;

  if (parser == nullptr || data == nullptr ||
      logical_length > simdjson::SIMDJSON_MAXSIZE_BYTES ||
      exceeds_size_t(logical_length) || exceeds_size_t(capacity) ||
      logical_length > UINT64_MAX - SIMD_JSON_REQUIRED_PADDING ||
      capacity < logical_length + SIMD_JSON_REQUIRED_PADDING) {
    return make_status(SIMD_JSON_STATUS_INVALID_ARGUMENT);
  }

  try {
    simdjson::ondemand::document parsed_document;
    const simdjson::error_code error =
        parser->value
            .iterate(data, static_cast<size_t>(logical_length),
                     static_cast<size_t>(capacity))
            .get(parsed_document);
    if (error != simdjson::SUCCESS) {
      return status_from_simdjson(error);
    }

    auto document = std::make_unique<simd_json_document>(
        parser, std::move(parsed_document), data, logical_length);
    *out_document = document.release();
    return make_status(SIMD_JSON_STATUS_OK);
  } catch (...) {
    return status_from_current_exception();
  }
}

extern "C" void simd_json_nif_projection_set_cancellation(
    simd_json_document *document,
    void *context,
    simd_json_nif_cancellation_probe probe) noexcept {
  if (document == nullptr) {
    return;
  }

  try {
    document->projection_cancellation_context = context;
    document->projection_cancellation_probe = probe;
  } catch (...) {
    document->projection_cancellation_context = nullptr;
    document->projection_cancellation_probe = nullptr;
  }
}

extern "C" void simd_json_nif_projection_clear_cancellation(
    simd_json_document *document) noexcept {
  if (document == nullptr) {
    return;
  }

  try {
    document->projection_cancellation_probe = nullptr;
    document->projection_cancellation_context = nullptr;
  } catch (...) {
  }
}

#ifdef SIMD_JSON_TESTING
extern "C" void simd_json_test_inject_failure(int32_t point,
                                                int32_t kind) noexcept {
  try {
    injected_failure.store(pack_failure(point, kind),
                           std::memory_order_release);
  } catch (...) {
    injected_failure.store(0, std::memory_order_release);
  }
}

extern "C" void simd_json_test_clear_failure(void) noexcept {
  try {
    injected_failure.store(0, std::memory_order_release);
  } catch (...) {
  }
}

extern "C" uint64_t simd_json_test_live_parser_count(void) noexcept {
  try {
    return live_parsers.load(std::memory_order_acquire);
  } catch (...) {
    return 0;
  }
}

extern "C" uint64_t simd_json_test_live_document_count(void) noexcept {
  try {
    return live_documents.load(std::memory_order_acquire);
  } catch (...) {
    return 0;
  }
}

extern "C" uint32_t simd_json_test_document_uses_input(
    simd_json_document *document,
    const uint8_t *data,
    uint64_t logical_length) noexcept {
  return simd_json_nif_document_uses_owned_input(document, data,
                                                  logical_length);
}

extern "C" simd_json_status simd_json_test_document_revalidate(
    simd_json_document *document) noexcept {
  return simd_json_nif_document_revalidate(document);
}

extern "C" simd_json_status simd_json_test_document_open_unvalidated(
    simd_json_parser *parser,
    const uint8_t *data,
    uint64_t logical_length,
    uint64_t capacity,
    simd_json_document **out_document) noexcept {
  return simd_json_nif_document_open_unvalidated(
      parser, data, logical_length, capacity, out_document);
}

extern "C" uint32_t simd_json_test_sanitizer_build(void) noexcept {
#if defined(SIMD_JSON_SANITIZER_TESTING)
  return UINT32_C(1);
#else
#if defined(__has_feature)
#if __has_feature(address_sanitizer)
  return UINT32_C(1);
#endif
#endif
#if defined(__SANITIZE_ADDRESS__)
  return UINT32_C(1);
#else
  return UINT32_C(0);
#endif
#endif
}
#endif
