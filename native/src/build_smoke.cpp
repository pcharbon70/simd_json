#include "../include/simd_json_build_smoke.h"
#include "../vendor/simdjson/simdjson.h"

extern "C" uint32_t simd_json_build_smoke_version(void) {
  return (simdjson::SIMDJSON_VERSION_MAJOR * 1'000'000U) +
         (simdjson::SIMDJSON_VERSION_MINOR * 1'000U) +
         simdjson::SIMDJSON_VERSION_REVISION;
}

extern "C" uint32_t simd_json_build_smoke_padding(void) {
  return static_cast<uint32_t>(simdjson::SIMDJSON_PADDING);
}

extern "C" const char *simd_json_build_smoke_runtime_implementation(void) {
  const simdjson::implementation *implementation =
      simdjson::get_active_implementation();

  if (implementation == nullptr) {
    return "unknown";
  }

  const std::string name = implementation->name();

  if (name == "haswell") {
    return "haswell";
  }

  if (name == "westmere") {
    return "westmere";
  }

  if (name == "fallback") {
    return "fallback";
  }

  return "unknown";
}
