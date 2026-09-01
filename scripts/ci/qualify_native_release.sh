#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.native_build_and_abi.clean_supported_build simd_json.native_build_and_abi.cpp_exception_translation simd_json.native_build_and_abi.c_abi_conformance simd_json.native_build_and_abi.release_symbol_surface simd_json.native_build_and_abi.unsupported_target_rejection simd_json.native_build_and_abi.dependency_upgrade_gate simd_json.projection_engine.prefix_sharing_plan simd_json.projection_engine.declaration_order_independence simd_json.projection_engine.single_guided_traversal simd_json.projection_engine.complete_source_validation simd_json.projection_engine.duplicate_json_key_policy simd_json.projection_engine.scalar_only_materialization simd_json.projection_engine.typed_result_slots simd_json.projection_engine.transactional_conversion simd_json.projection_engine.private_abi_v2 simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_engine.single_beam_boundary simd_json.projection_engine.internal_phase_timing simd_json.projection_engine.shared_prefix_and_order simd_json.projection_engine.object_array_walk simd_json.projection_engine.invalid_unselected_content simd_json.projection_engine.duplicate_object_keys simd_json.projection_engine.transactional_slot_failure simd_json.projection_engine.abi_v2_conformance simd_json.projection_engine.one_boundary_with_timing

repository_root="$(git rev-parse --show-toplevel)"
qualification_record="${repository_root}/native/qualification/milestone_1.exs"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/native}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-release-package.XXXXXX")"
package_root="${scratch_root}/simd_json-0.1.0"
seed="${SIMD_JSON_QUALIFICATION_SEED:-$(sed -n 's/.*randomized_seed: \([0-9_]*\).*/\1/p' "${qualification_record}" | tr -d '_')}"
zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"

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
  README.md
  docs/milestones/README.md
  docs/milestones/01-native-foundation.md
  docs/milestones/01-native-foundation-operations.md
  docs/milestones/01-native-foundation-acceptance.md
  docs/milestones/02-projection-api.md
  docs/milestones/02-projection-api-operations.md
  docs/milestones/02-projection-api-acceptance.md
  docs/milestones/03-batched-array-streaming.md
  lib/simd_json.ex
  lib/simd_json/projection.ex
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
  native/symbols/c_abi.allowlist
  native/symbols/c_abi.version
  native/symbols/nif.allowlist
  native/test/include/simd_json_test_hooks.h
  native/test/projection_engine_conformance.c
  native/test/projection_plan_conformance.c
  native/test/projection_plan_test.zig
  native/test/stream_cursor_conformance.c
  native/test/stream_cursor_test.zig
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

printf 'Milestone 1 release-native qualification passed\n' | tee "${evidence_root}/summary.txt"
