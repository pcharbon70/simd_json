#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.native_build_and_abi.c_abi_conformance simd_json.native_build_and_abi.cpp_exception_translation simd_json.document_resource.input_lifetime simd_json.document_resource.repeated_close simd_json.document_resource.gc_cleanup simd_json.native_execution.threaded_parse simd_json.native_execution.threaded_cleanup simd_json.document_api.open_and_close simd_json.document_api.invalid_input_errors simd_json.projection_api.select_contract simd_json.projection_api.scalar_results simd_json.projection_api.atomic_result simd_json.projection_api.projection_error_reasons simd_json.projection_engine.transactional_conversion simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_engine.single_beam_boundary simd_json.projection_execution.threaded_projection simd_json.projection_execution.binary_temporary_document simd_json.projection_execution.close_interlock simd_json.projection_execution.cancellation_boundaries simd_json.projection_execution.native_memory_baseline

repository_root="$(git rev-parse --show-toplevel)"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-nif-sanitizer.XXXXXX")"
build_root="${scratch_root}/build"
zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"
sanitizer_seed="${SIMD_JSON_NIF_SANITIZER_SEED:-935088}"
sanitizer_trace="${SIMD_JSON_NIF_SANITIZER_TRACE:-0}"
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

if [[ ! "${sanitizer_seed}" =~ ^[0-9]+$ ]]; then
  printf 'SIMD_JSON_NIF_SANITIZER_SEED must be a non-negative integer\n' >&2
  exit 1
fi

case "${sanitizer_trace}" in
  0) test_options=(--seed "${sanitizer_seed}") ;;
  1) test_options=(--seed "${sanitizer_seed}" --trace) ;;
  *)
    printf 'SIMD_JSON_NIF_SANITIZER_TRACE must be 0 or 1\n' >&2
    exit 1
    ;;
esac

asan_library="$("${zig_executable}" c++ -print-file-name=libasan.so)"
ubsan_library="$("${zig_executable}" c++ -print-file-name=libubsan.so)"
asan_preload="$(readlink -f "${asan_library}")"
ubsan_runtime="$(readlink -f "${ubsan_library}")"

if [[ ! -f "${asan_preload}" ]]; then
  printf 'AddressSanitizer runtime is unavailable: %s\n' "${asan_preload}" >&2
  exit 1
fi

if [[ ! -f "${ubsan_runtime}" ]]; then
  printf 'UndefinedBehaviorSanitizer runtime is unavailable: %s\n' "${ubsan_runtime}" >&2
  exit 1
fi

env \
  MIX_ENV=test \
  MIX_BUILD_PATH="${build_root}" \
  SIMD_JSON_SANITIZER=1 \
  SIMD_JSON_ASAN_LIBRARY="${asan_preload}" \
  SIMD_JSON_UBSAN_LIBRARY="${ubsan_runtime}" \
  ZIG_EXECUTABLE_PATH="${zig_executable}" \
  LD_PRELOAD="${asan_preload}" \
  ASAN_OPTIONS="detect_leaks=0:halt_on_error=1:strict_string_checks=1" \
  UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
  ERL_FLAGS="+S 4:4 +SDcpu 4 +SDio 2" \
  mix compile --force

env \
  MIX_ENV=test \
  MIX_BUILD_PATH="${build_root}" \
  SIMD_JSON_SANITIZER=1 \
  SIMD_JSON_ASAN_LIBRARY="${asan_preload}" \
  SIMD_JSON_UBSAN_LIBRARY="${ubsan_runtime}" \
  ZIG_EXECUTABLE_PATH="${zig_executable}" \
  LD_PRELOAD="${asan_preload}" \
  ASAN_OPTIONS="detect_leaks=0:halt_on_error=1:strict_string_checks=1" \
  UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
  ERL_FLAGS="+S 4:4 +SDcpu 4 +SDio 2" \
  mix test --no-compile "${test_options[@]}" \
    test/native/threaded_document_open_test.exs \
    test/native/threaded_teardown_test.exs \
    test/native/threaded_projection_operation_test.exs \
    test/native/projection_binary_lifetime_test.exs \
    test/native/projection_document_lifecycle_test.exs \
    test/native/threaded_projection_integration_test.exs \
    test/native/stream_document_lifecycle_test.exs \
    test/native/threaded_stream_lifecycle_test.exs \
    test/simd_json/document_api_test.exs \
    test/simd_json/error_test.exs \
    test/simd_json/phase_5_integration_test.exs \
    test/simd_json/select_test.exs \
    test/simd_json/stream_constructor_test.exs \
    test/simd_json/stream_enumerable_test.exs

printf 'threaded and public NIF sanitizer corpus passed\n'
