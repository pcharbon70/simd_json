#include "../include/simd_json_build_smoke.h"
#include "../vendor/simdjson/simdjson.h"

extern "C" uint32_t simd_json_build_smoke_version(void) {
  try {
    return (simdjson::SIMDJSON_VERSION_MAJOR * 1'000'000U) +
           (simdjson::SIMDJSON_VERSION_MINOR * 1'000U) +
           simdjson::SIMDJSON_VERSION_REVISION;
  } catch (...) {
    return 0;
  }
}

extern "C" uint32_t simd_json_build_smoke_padding(void) {
  try {
    return static_cast<uint32_t>(simdjson::SIMDJSON_PADDING);
  } catch (...) {
    return 0;
  }
}

extern "C" const char *simd_json_build_smoke_runtime_implementation(void) {
  try {
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
  } catch (...) {
    return "unknown";
  }
}
