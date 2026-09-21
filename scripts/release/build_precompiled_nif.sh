#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.precompiled_delivery simd_json.release.provenance

repository_root="$(git rev-parse --show-toplevel)"
version="$(sed -n 's/^  @version "\([^"]*\)"/\1/p' "${repository_root}/mix.exs")"
target="x86_64-linux-gnu"
asset_name="simd_json-v${version}-${target}.so"
default_output_root="${repository_root}/_build/precompiled"
output_root="${1:-${default_output_root}}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-precompiled.XXXXXX")"
first_source="${scratch_root}/source-one"
second_source="${scratch_root}/source-two"
first_build="${scratch_root}/build-one"
second_build="${scratch_root}/build-two"
first_artifact="${first_build}/lib/simd_json/priv/lib/Elixir.SimdJson.Native.BuildSmoke.so"
second_artifact="${second_build}/lib/simd_json/priv/lib/Elixir.SimdJson.Native.BuildSmoke.so"
first_normalized="${scratch_root}/normalized-one.so"
second_normalized="${scratch_root}/normalized-two.so"
candidate="${output_root}/${asset_name}"
manifest="${repository_root}/native/precompiled/checksums.exs"
zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"

cleanup() {
  local original_status=$?
  chmod -R u+w "${scratch_root}" 2>/dev/null || true
  rm -rf -- "${scratch_root}"
  return "${original_status}"
}

trap cleanup EXIT

if [[ -z "${version}" ]]; then
  printf 'cannot read package version from mix.exs\n' >&2
  exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  printf 'precompiled NIF builder requires x86_64, got %s\n' "$(uname -m)" >&2
  exit 1
fi

if [[ ! -x "${zig_executable}" ]]; then
  printf 'qualified Zig executable is unavailable: %s\n' "${zig_executable}" >&2
  exit 1
fi

mkdir -p "${first_source}" "${second_source}" "${output_root}"
git -C "${repository_root}" archive --format=tar HEAD | tar -xf - -C "${first_source}"
git -C "${repository_root}" archive --format=tar HEAD | tar -xf - -C "${second_source}"

build_one() {
  local source_root="$1"
  local build_root="$2"
  local cache_root="$3"

  mkdir -p "${build_root}" "${cache_root}/global" "${cache_root}/local" \
    "${cache_root}/zigler"

  (
    cd "${source_root}"
    env \
      MIX_ENV=prod \
      MIX_BUILD_PATH="${build_root}" \
      MIX_DEPS_PATH="${repository_root}/deps" \
      ZIG_EXECUTABLE_PATH="${zig_executable}" \
      ZIG_GLOBAL_CACHE_DIR="${cache_root}/global" \
      ZIG_LOCAL_CACHE_DIR="${cache_root}/local" \
      ZIGLER_STAGING_ROOT="${cache_root}/zigler" \
      ZIGLER_RELEASE_MODE=safe \
      SIMD_JSON_BUILD_FROM_SOURCE=1 \
      mix do deps.compile, compile --force
  )
}

build_one "${first_source}" "${first_build}" "${scratch_root}/cache-one"
build_one "${second_source}" "${second_build}" "${scratch_root}/cache-two"

for artifact in "${first_artifact}" "${second_artifact}"; do
  if [[ ! -f "${artifact}" ]]; then
    printf 'release build did not produce the expected NIF: %s\n' "${artifact}" >&2
    exit 1
  fi
done

cp "${first_artifact}" "${first_normalized}"
cp "${second_artifact}" "${second_normalized}"
strip --strip-unneeded "${first_normalized}" "${second_normalized}"

if ! cmp --silent "${first_normalized}" "${second_normalized}"; then
  printf 'independent release-safe NIF builds are not byte-identical\n' >&2
  sha256sum "${first_normalized}" "${second_normalized}" >&2
  exit 1
fi

dynamic_dependencies="$(ldd "${second_normalized}")"
case "${dynamic_dependencies}" in
  *simdjson*|*libstdc++*|*libc++*)
    printf 'precompiled NIF links an unexpected simdjson or C++ library\n%s\n' \
      "${dynamic_dependencies}" >&2
    exit 1
    ;;
esac

exported_symbols="$(nm -D --defined-only "${second_normalized}" | awk '{print $3}' | sort -u)"
if [[ "${exported_symbols}" != "nif_init" ]]; then
  printf 'precompiled NIF exports an unexpected symbol surface:\n%s\n' \
    "${exported_symbols}" >&2
  exit 1
fi

cp "${second_normalized}" "${candidate}"
candidate_sha256="$(sha256sum "${candidate}" | cut -d ' ' -f 1)"

if [[ "${SIMD_JSON_ALLOW_UNRECORDED:-0}" != "1" ]]; then
  elixir "${repository_root}/scripts/release/verify_precompiled_checksum.exs" \
    "${candidate}" "${version}" "${target}" "${manifest}"
fi

diagnostic_path="${output_root}/runtime.env"
cp "${second_normalized}" "${second_artifact}"
(
  cd "${second_source}"
  env \
    MIX_ENV=prod \
    MIX_BUILD_PATH="${second_build}" \
    MIX_DEPS_PATH="${repository_root}/deps" \
    SIMD_JSON_DIAGNOSTIC_PATH="${diagnostic_path}" \
    mix run --no-compile --no-start -e '
      info = SimdJson.Native.Diagnostics.build()
      File.write!(System.fetch_env!("SIMD_JSON_DIAGNOSTIC_PATH"), "target=#{info.target}\nruntime_implementation=#{info.runtime_implementation}\nsimdjson_version=#{info.simdjson_version}\nnative_fingerprint=#{info.native_fingerprint}\n")
    '
)

if ! grep -Fqx "target=${target}" "${diagnostic_path}"; then
  printf 'precompiled NIF diagnostic target does not match %s\n' "${target}" >&2
  exit 1
fi

source_commit="$(git -C "${repository_root}" rev-parse HEAD)"
source_tree="$(git -C "${repository_root}" rev-parse HEAD^{tree})"

{
  printf 'schema_version=1\n'
  printf 'version=%s\n' "${version}"
  printf 'target=%s\n' "${target}"
  printf 'asset=%s\n' "${asset_name}"
  printf 'asset_sha256=%s\n' "${candidate_sha256}"
  printf 'source_commit=%s\n' "${source_commit}"
  printf 'source_tree=%s\n' "${source_tree}"
  printf 'zig_version=%s\n' "$("${zig_executable}" version)"
  printf 'strip_version=%s\n' "$(strip --version | head -n 1)"
  printf 'reproducible=true\n'
  printf 'dynamic_dependency_policy=passed\n'
  printf 'exported_symbols=nif_init\n'
} >"${output_root}/provenance.env"

(
  cd "${output_root}"
  sha256sum "${asset_name}" provenance.env runtime.env >SHA256SUMS
)

printf 'precompiled NIF reproduced: %s\n' "${candidate}"
printf 'sha256=%s\n' "${candidate_sha256}"
