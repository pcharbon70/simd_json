#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.native_build_and_abi.clean_checkout_build simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.clean_supported_build

repository_root="$(git rev-parse --show-toplevel)"
source_tree="${SIMD_JSON_SOURCE_TREE:-HEAD}"
source_directory="${SIMD_JSON_SOURCE_DIRECTORY:-}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd_json-offline.XXXXXX")"
source_root="${scratch_root}/source"
first_build_root="${scratch_root}/build-one"
second_build_root="${scratch_root}/build-two"
first_diagnostic="${scratch_root}/diagnostic-one"
second_diagnostic="${scratch_root}/diagnostic-two"
namespace_uses_sudo=false
diagnostic_expression='
  info = SimdJson.Native.Diagnostics.build()

  diagnostic =
    [
      info.target,
      info.runtime_implementation,
      Integer.to_string(info.simdjson_version),
      Integer.to_string(info.simdjson_padding),
      info.native_fingerprint
    ]
    |> Enum.join("\n")

  File.write!(System.fetch_env!("SIMD_JSON_DIAGNOSTIC_PATH"), diagnostic)
'

cleanup() {
  local original_status=$?

  set +e

  if [[ "${namespace_uses_sudo}" == true ]]; then
    sudo -n chown -R "${UID}:$(id -g)" "${scratch_root}"
  fi

  chmod -R u+w "${scratch_root}" 2>/dev/null || true
  rm -rf -- "${scratch_root}"

  return "${original_status}"
}

trap cleanup EXIT

mkdir -p "${source_root}"

if [[ -n "${source_directory}" ]]; then
  source_directory="$(realpath "${source_directory}")"

  if [[ ! -f "${source_directory}/mix.exs" ]]; then
    printf 'offline source directory is not an unpacked Mix package: %s\n' \
      "${source_directory}" >&2
    exit 1
  fi

  cp -a "${source_directory}/." "${source_root}/"
else
  git -C "${repository_root}" archive --format=tar "${source_tree}" \
    | tar -xf - -C "${source_root}"
fi

zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-${scratch_root}/zig-global-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-${scratch_root}/zig-local-cache}"

if [[ ! -x "${zig_executable}" ]]; then
  printf 'qualified Zig executable is unavailable: %s\n' "${zig_executable}" >&2
  exit 1
fi

if unshare --user --map-root-user --net true 2>/dev/null; then
  namespace_command=(unshare --user --map-root-user --net --)
elif sudo -n unshare --net true 2>/dev/null; then
  namespace_command=(sudo -n unshare --net --)
  namespace_uses_sudo=true
else
  printf 'cannot create the network namespace required for the offline build test\n' >&2
  exit 1
fi

offline_build() {
  local build_root="$1"
  local diagnostic_path="$2"
  local zigler_staging_root="${build_root}/zigler-staging"

  mkdir -p "${build_root}" "${zigler_staging_root}"

  "${namespace_command[@]}" env \
    "HOME=${HOME}" \
    "PATH=${PATH}" \
    "MIX_ENV=test" \
    "MIX_BUILD_PATH=${build_root}" \
    "MIX_DEPS_PATH=${repository_root}/deps" \
    "ZIG_EXECUTABLE_PATH=${zig_executable}" \
    "ZIGLER_STAGING_ROOT=${zigler_staging_root}" \
    "ZIGLER_RELEASE_MODE=safe" \
    "HEX_OFFLINE=1" \
    "SIMD_JSON_DIAGNOSTIC_PATH=${diagnostic_path}" \
    "SIMD_JSON_DIAGNOSTIC_EXPRESSION=${diagnostic_expression}" \
    "SIMD_JSON_OFFLINE_SOURCE=${source_root}" \
    bash --noprofile --norc -c '
      set -euo pipefail
      cd "${SIMD_JSON_OFFLINE_SOURCE}"
      mix deps.compile
      mix compile --force
      mix run --no-compile -e "${SIMD_JSON_DIAGNOSTIC_EXPRESSION}"
    '
}

offline_build "${first_build_root}" "${first_diagnostic}"
offline_build "${second_build_root}" "${second_diagnostic}"

if ! cmp --silent "${first_diagnostic}" "${second_diagnostic}"; then
  printf 'repeated clean builds reported different native inputs or runtime diagnostics\n' >&2
  exit 1
fi

nif_path="${second_build_root}/lib/simd_json/priv/lib/Elixir.SimdJson.Native.BuildSmoke.so"

if [[ ! -f "${nif_path}" ]]; then
  printf 'clean build did not produce the smoke NIF: %s\n' "${nif_path}" >&2
  exit 1
fi

dynamic_dependencies="$(ldd "${nif_path}")"

case "${dynamic_dependencies}" in
  *simdjson*|*libstdc++*|*libc++*)
    printf 'smoke NIF unexpectedly links an ambient simdjson or C++ library\n%s\n' \
      "${dynamic_dependencies}" >&2
    exit 1
    ;;
esac

printf 'offline native build repeated successfully\n'
sed -n '1,5p' "${second_diagnostic}"
