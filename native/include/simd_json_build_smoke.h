#ifndef SIMD_JSON_BUILD_SMOKE_H
#define SIMD_JSON_BUILD_SMOKE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t simd_json_build_smoke_version(void);
uint32_t simd_json_build_smoke_padding(void);
const char *simd_json_build_smoke_runtime_implementation(void);

#ifdef __cplusplus
}
#endif

#endif
