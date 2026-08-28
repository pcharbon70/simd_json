#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.padded_owned_copy simd_json.document_resource.zero_copy_disabled simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction simd_json.document_resource.parent_retention simd_json.document_resource.test_accounting simd_json.document_resource.input_lifetime simd_json.document_resource.partial_open_failure

repository_root="$(git rev-parse --show-toplevel)"
profile="${1:-ordinary}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-zig-resource.XXXXXX")"
zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"

cleanup() {
  local original_status=$?

  chmod -R u+w "${scratch_root}" 2>/dev/null || true
  rm -rf -- "${scratch_root}"
  return "${original_status}"
}

trap cleanup EXIT

if [[ ! -x "${zig_executable}" ]]; then
  printf 'qualified Zig executable is unavailable: %s\n' "${zig_executable}" >&2
  exit 1
fi

case "${profile}" in
  ordinary)
    profile_flags=(-O1 -g)
    runtime_environment=()
    ;;
  sanitizer)
    profile_flags=(
      -O1
      -g
      -fno-omit-frame-pointer
      -fsanitize=address,undefined
      -DSIMD_JSON_SANITIZER_TESTING=1
    )
    asan_library="$("${zig_executable}" c++ -print-file-name=libasan.so)"
    asan_preinit="$("${zig_executable}" c++ -print-file-name=libasan_preinit.o)"
    sanitizer_runtime_dir="$(dirname "${asan_library}")"
    asan_preload="$(readlink -f "${asan_library}")"
    runtime_environment=(
      "ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:strict_string_checks=1"
      "UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
      "LD_PRELOAD=${asan_preload}"
    )
    ;;
  *)
    printf 'unknown Zig resource test profile: %s\n' "${profile}" >&2
    exit 1
    ;;
esac

common_cxx_flags=(
  -std=c++17
  -Wall
  -Wextra
  -Werror
  -pedantic
  -DSIMDJSON_AVX512_ALLOWED=0
  -DSIMD_JSON_TESTING=1
  -fvisibility=hidden
  -fvisibility-inlines-hidden
  -I "${repository_root}/native/include"
)

"${zig_executable}" c++ "${common_cxx_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/src/simd_json_abi.cpp" \
  -o "${scratch_root}/simd_json_abi.o"

"${zig_executable}" c++ "${common_cxx_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/vendor/simdjson/simdjson.cpp" \
  -o "${scratch_root}/simdjson.o"

"${zig_executable}" ar rcs "${scratch_root}/libsimd_json_abi_test.a" \
  "${scratch_root}/simd_json_abi.o" "${scratch_root}/simdjson.o"

test_command=("${zig_executable}" test \
  -I "${repository_root}/native/include" \
  -I "${repository_root}/native/test/include" \
  --dep document_resource \
  -Mroot="${repository_root}/native/test/document_resource_test.zig" \
  -Mdocument_resource="${repository_root}/native/zig/document_resource.zig" \
  -L "${scratch_root}" \
  -lsimd_json_abi_test \
  -lc++ \
  -lc \
  -O Debug)

if [[ "${profile}" == "sanitizer" ]]; then
  test_command+=(
    "${asan_preinit}"
    -L "${sanitizer_runtime_dir}"
    -lasan
    -lubsan
    -lpthread
    -ldl
    -lrt
    -lm
  )
fi

env "${runtime_environment[@]}" "${test_command[@]}"
