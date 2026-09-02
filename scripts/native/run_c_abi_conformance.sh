#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.native_build_and_abi.c_abi_conformance simd_json.native_build_and_abi.cpp_exception_translation simd_json.native_build_and_abi.partial_failure_cleanup simd_json.projection_engine.abi_v2_conformance simd_json.projection_engine.exception_and_failure_cleanup simd_json.stream_cursor.abi_v3_conformance simd_json.stream_cursor.exception_and_failure_cleanup
# covers: simd_json.stream_cursor.single_target_lookup simd_json.stream_cursor.forward_only_rows simd_json.stream_cursor.projection_plan_reuse simd_json.stream_cursor.row_count_bound simd_json.stream_cursor.encoded_byte_bound simd_json.stream_cursor.transactional_batch simd_json.stream_cursor.copied_row_values simd_json.stream_cursor.exact_done_detection simd_json.stream_cursor.complete_consumption_validation simd_json.stream_cursor.indexed_status simd_json.stream_cursor.batch_boundary simd_json.stream_cursor.internal_diagnostics simd_json.stream_cursor.target_lookup_and_retention simd_json.stream_cursor.reused_row_projection simd_json.stream_cursor.row_and_byte_boundaries simd_json.stream_cursor.exact_end_and_trailing_validation simd_json.stream_cursor.indexed_row_failure simd_json.stream_cursor.cancellation_and_cleanup_matrix

repository_root="$(git rev-parse --show-toplevel)"
profile="${1:-ordinary}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-c-abi.XXXXXX")"
zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-${TMPDIR:-/tmp}/simd-json-zig-global-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-${scratch_root}/zig-local-cache}"

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
    profile_flags=(-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined)
    runtime_environment=(
      "ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:strict_string_checks=1"
      "UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
    )
    ;;
  *)
    printf 'unknown C ABI conformance profile: %s\n' "${profile}" >&2
    exit 1
    ;;
esac

common_c_flags=(
  -std=c11
  -Wall
  -Wextra
  -Werror
  -pedantic
  -DSIMD_JSON_TESTING=1
  -I "${repository_root}/native/include"
  -I "${repository_root}/native/test/include"
)
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

"${zig_executable}" cc "${common_c_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/test/c_abi_conformance.c" \
  -o "${scratch_root}/c_abi_conformance.o"

"${zig_executable}" cc "${common_c_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/test/projection_plan_conformance.c" \
  -o "${scratch_root}/projection_plan_conformance.o"

"${zig_executable}" cc "${common_c_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/test/projection_engine_conformance.c" \
  -o "${scratch_root}/projection_engine_conformance.o"

"${zig_executable}" cc "${common_c_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/test/stream_cursor_conformance.c" \
  -o "${scratch_root}/stream_cursor_conformance.o"

"${zig_executable}" c++ "${common_cxx_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/src/simd_json_abi.cpp" \
  -o "${scratch_root}/simd_json_abi.o"

"${zig_executable}" c++ "${common_cxx_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/src/simd_json_projection.cpp" \
  -o "${scratch_root}/simd_json_projection.o"

"${zig_executable}" c++ "${common_cxx_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/src/simd_json_stream_cursor.cpp" \
  -o "${scratch_root}/simd_json_stream_cursor.o"

"${zig_executable}" c++ "${common_cxx_flags[@]}" "${profile_flags[@]}" \
  -c "${repository_root}/native/vendor/simdjson/simdjson.cpp" \
  -o "${scratch_root}/simdjson.o"

"${zig_executable}" ar rcs "${scratch_root}/libsimd_json_abi_test.a" \
  "${scratch_root}/simd_json_abi.o" \
  "${scratch_root}/simd_json_projection.o" \
  "${scratch_root}/simd_json_stream_cursor.o" \
  "${scratch_root}/simdjson.o"

"${zig_executable}" c++ "${profile_flags[@]}" \
  "${scratch_root}/c_abi_conformance.o" \
  "${scratch_root}/libsimd_json_abi_test.a" \
  -o "${scratch_root}/c_abi_conformance"

env "${runtime_environment[@]}" "${scratch_root}/c_abi_conformance"

"${zig_executable}" c++ "${profile_flags[@]}" \
  "${scratch_root}/projection_plan_conformance.o" \
  "${scratch_root}/libsimd_json_abi_test.a" \
  -o "${scratch_root}/projection_plan_conformance"

env "${runtime_environment[@]}" "${scratch_root}/projection_plan_conformance"

"${zig_executable}" c++ "${profile_flags[@]}" \
  "${scratch_root}/projection_engine_conformance.o" \
  "${scratch_root}/libsimd_json_abi_test.a" \
  -o "${scratch_root}/projection_engine_conformance"

env "${runtime_environment[@]}" "${scratch_root}/projection_engine_conformance"

"${zig_executable}" c++ "${profile_flags[@]}" \
  "${scratch_root}/stream_cursor_conformance.o" \
  "${scratch_root}/libsimd_json_abi_test.a" \
  -o "${scratch_root}/stream_cursor_conformance"

env "${runtime_environment[@]}" "${scratch_root}/stream_cursor_conformance"
