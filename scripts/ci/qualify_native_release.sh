#!/usr/bin/env bash
set -euo pipefail

# This is the cumulative ABI v1/v2/v3 release gate. Streaming additions must
# extend it; they must never replace the earlier document and projection proof.

repository_root="$(git rev-parse --show-toplevel)"
qualification_record="${repository_root}/native/qualification/milestone_1.exs"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/native}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-release-package.XXXXXX")"
package_root="${scratch_root}/simd_json-0.1.0"
seed="${SIMD_JSON_QUALIFICATION_SEED:-$(sed -n 's/.*randomized_seed: \([0-9_]*\).*/\1/p' "${qualification_record}" | tr -d '_')}"
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
mkdir -p "${evidence_root}"

run_step() {
  local name="$1"
  shift

  printf '%s\n' "$*" >"${evidence_root}/${name}.command"
  "$@" 2>&1 | tee "${evidence_root}/${name}.log"
}

if [[ -z "${seed}" ]]; then
  printf 'qualification seed is missing from %s\n' "${qualification_record}" >&2
  exit 1
fi

if [[ ! -x "${zig_executable}" ]]; then
  printf 'qualified Zig executable is unavailable: %s\n' "${zig_executable}" >&2
  exit 1
fi

{
  printf 'source_revision=%s\n' "$(git -C "${repository_root}" rev-parse HEAD)"
  printf 'source_tree=%s\n' "$(git -C "${repository_root}" rev-parse HEAD^{tree})"
  printf 'target=%s\n' "$(uname -m)-$(uname -s)"
  printf 'kernel=%s\n' "$(uname -srvo)"
  printf 'seed=%s\n' "${seed}"
  printf 'mix=%s\n' "$(mix --version | tr '\n' ' ')"
  printf 'zig=%s\n' "$("${zig_executable}" version)"
  printf 'cxx=%s\n' "$("${zig_executable}" c++ --version | head -n 1)"
  printf 'qualification_input_sha256=%s\n' "$(mix run --no-start -e 'IO.write(SimdJson.Native.BuildGuard.qualification_fingerprint())')"
} >"${evidence_root}/environment.txt"

run_step package_build mix hex.build --unpack --output "${package_root}"

required_package_files=(
  .tool-versions
  LICENSE
  README.md
  THIRD_PARTY_NOTICES.md
  docs/milestones/README.md
  docs/milestones/01-native-foundation.md
  docs/milestones/01-native-foundation-operations.md
  docs/milestones/01-native-foundation-acceptance.md
  docs/milestones/02-projection-api.md
  docs/milestones/02-projection-api-operations.md
  docs/milestones/02-projection-api-acceptance.md
  docs/milestones/03-batched-array-streaming.md
  docs/milestones/05-compatible-decode-api.md
  docs/milestones/05-compatible-decode-api-acceptance.md
  docs/releases/support.md
  docs/releases/ci-policy.md
  lib/simd_json.ex
  lib/simd_json/decode_options.ex
  lib/simd_json/document.ex
  lib/simd_json/error.ex
  lib/simd_json/projection.ex
  lib/simd_json/stream.ex
  lib/simd_json/stream_options.ex
  lib/simd_json/native/projection_operation.ex
  lib/simd_json/native/threaded_operation.ex
  mix.exs
  mix.lock
  native/README.md
  native/manifest.exs
  native/qualification/milestone_1.exs
  native/include/simd_json_abi.h
  native/include/simd_json_nif_internal.h
  native/src/simd_json_abi.cpp
  native/src/simd_json_native_internal.hpp
  native/src/simd_json_projection.cpp
  native/src/simd_json_stream_cursor.cpp
  native/src/simd_json_decode_materializer.cpp
  native/symbols/c_abi.allowlist
  native/symbols/c_abi.version
  native/symbols/nif.allowlist
  native/test/include/simd_json_test_hooks.h
  native/test/projection_engine_conformance.c
  native/test/projection_plan_conformance.c
  native/test/projection_plan_test.zig
  native/test/stream_cursor_conformance.c
  native/test/stream_cursor_test.zig
  native/test/decode_materializer_conformance.c
  native/test/decode_materializer_test.zig
  native/vendor/simdjson/simdjson.cpp
  native/vendor/simdjson/simdjson.h
  native/vendor/simdjson/README.md
  native/vendor/simdjson/LICENSE
  native/vendor/simdjson/LICENSE-MIT
  native/vendor/simdjson/patches/series
  native/zig/build_smoke.zig
  native/zig/document_resource.zig
  native/zig/projection_plan.zig
  native/zig/stream_cursor.zig
  native/zig/decode_materializer.zig
)

for relative_path in "${required_package_files[@]}"; do
  if [[ ! -f "${package_root}/${relative_path}" ]]; then
    printf 'release package is missing required input: %s\n' "${relative_path}" >&2
    exit 1
  fi
done

if find "${package_root}" -type f \( -name '*.so' -o -name '.Elixir.*.zig' \) | grep -q .; then
  printf 'release package contains a generated native artifact or Zigler intermediate\n' >&2
  exit 1
fi

printf '%s\n' "${required_package_files[@]}" >"${evidence_root}/package-required-files.txt"
find "${package_root}" -type f -printf '%P\n' | LC_ALL=C sort \
  >"${evidence_root}/package-contents.txt"

run_step vendor mix simd_json.verify_vendor
run_step qualification_freshness mix simd_json.verify_qualification
run_step compile env MIX_ENV=test ZIGLER_RELEASE_MODE=safe mix compile --force
run_step diagnostics env MIX_ENV=test mix run --no-compile -e 'IO.inspect(SimdJson.Native.Diagnostics.build())'
run_step native_tests env MIX_ENV=test mix test test/native test/qualification/native_release_qualification_test.exs
run_step c_abi_ordinary env SIMD_JSON_QUALIFICATION_SEED="${seed}" bash scripts/native/run_c_abi_conformance.sh ordinary
run_step c_abi_sanitizer env SIMD_JSON_QUALIFICATION_SEED="${seed}" bash scripts/native/run_c_abi_conformance.sh sanitizer
run_step zig_resource_ordinary bash scripts/native/run_zig_resource_tests.sh ordinary
run_step zig_resource_sanitizer bash scripts/native/run_zig_resource_tests.sh sanitizer
run_step nif_sanitizer bash scripts/native/run_nif_sanitizer_tests.sh
run_step release_symbols bash scripts/native/verify_release_symbols.sh
run_step offline_package_build \
  env SIMD_JSON_SOURCE_DIRECTORY="${package_root}" \
  bash scripts/ci/verify_offline_native_build.sh

printf 'Cumulative ABI v1/v2/v3 release-native qualification passed\n' \
  | tee "${evidence_root}/summary.txt"
