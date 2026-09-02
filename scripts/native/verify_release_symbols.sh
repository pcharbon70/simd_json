#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.native_build_and_abi.release_symbol_surface simd_json.native_build_and_abi.symbol_visibility

repository_root="$(git rev-parse --show-toplevel)"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-symbols.XXXXXX")"
zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-${scratch_root}/zig-global-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-${scratch_root}/zig-local-cache}"
release_build_root="${scratch_root}/release-build"
nif_path="${SIMD_JSON_NIF_PATH:-${release_build_root}/lib/simd_json/priv/lib/Elixir.SimdJson.Native.BuildSmoke.so}"
abi_library="${scratch_root}/libsimd_json_abi.so"

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

if [[ -z "${SIMD_JSON_NIF_PATH:-}" ]]; then
  env \
    MIX_ENV=prod \
    MIX_BUILD_PATH="${release_build_root}" \
    ZIGLER_RELEASE_MODE=safe \
    ZIG_EXECUTABLE_PATH="${zig_executable}" \
    mix compile --force
fi

if [[ ! -f "${nif_path}" ]]; then
  printf 'release symbol check cannot find the NIF: %s\n' "${nif_path}" >&2
  exit 1
fi

"${zig_executable}" c++ \
  -std=c++17 \
  -O2 \
  -DNDEBUG \
  -DSIMDJSON_AVX512_ALLOWED=0 \
  -DSIMD_JSON_ABI_BUILD_SHARED=1 \
  -fvisibility=hidden \
  -fvisibility-inlines-hidden \
  -fPIC \
  -shared \
  "${repository_root}/native/src/simd_json_abi.cpp" \
  "${repository_root}/native/src/simd_json_projection.cpp" \
  "${repository_root}/native/src/simd_json_stream_cursor.cpp" \
  "${repository_root}/native/vendor/simdjson/simdjson.cpp" \
  -Wl,--version-script="${repository_root}/native/symbols/c_abi.version" \
  -o "${abi_library}"

defined_symbols() {
  nm -D --defined-only "$1" |
    awk '$2 != "A" {sub(/@@.*/, "", $3); print $3}' |
    LC_ALL=C sort -u
}

defined_symbols "${abi_library}" >"${scratch_root}/c_abi.actual"
defined_symbols "${nif_path}" >"${scratch_root}/nif.actual"

LC_ALL=C sort -u "${repository_root}/native/symbols/c_abi.allowlist" \
  >"${scratch_root}/c_abi.expected"
LC_ALL=C sort -u "${repository_root}/native/symbols/nif.allowlist" \
  >"${scratch_root}/nif.expected"

diff -u "${scratch_root}/c_abi.expected" "${scratch_root}/c_abi.actual"
diff -u "${scratch_root}/nif.expected" "${scratch_root}/nif.actual"

for artifact in "${abi_library}" "${nif_path}"; do
  if nm -D --defined-only "${artifact}" | grep -Eq '_Z|simdjson'; then
    printf 'release artifact exports C++ or simdjson implementation symbols: %s\n' \
      "${artifact}" >&2
    exit 1
  fi

  forbidden_strings="$(strings "${artifact}" | grep -E \
    'simd_json_test_|simd_json_test_standard_exception|simd_json_projection_standard_exception|after_buffer_allocation|live_padded_buffers|completed_destruction_events|openWithFailure|projection_operation_inject_failure|operation_configure_pause|operation_release_pause|execution_set_cleanup_rejection|execution_snapshot|live_projection_(operations|environments|plans|slots|temporary_document_graphs)|projection_(worker|boundary)_entries' || true)"

  if [[ -n "${forbidden_strings}" ]]; then
    printf 'release artifact contains native failure-injection controls: %s\n%s\n' \
      "${artifact}" "${forbidden_strings}" >&2
    exit 1
  fi
done

printf 'release symbol surfaces match their allowlists\n'
