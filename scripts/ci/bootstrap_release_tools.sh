#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.green_ci simd_json.release.ci_cache_equivalence

repository_root="$(git rev-parse --show-toplevel)"
release_mix_env="${SIMD_JSON_RELEASE_MIX_ENV:-test}"
active_mix_env="${MIX_ENV:-${release_mix_env}}"
zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"

cd "${repository_root}"

if [[ "${active_mix_env}" != "${release_mix_env}" ]]; then
  printf 'release tool bootstrap requires MIX_ENV=%s; received MIX_ENV=%s\n' \
    "${release_mix_env}" "${active_mix_env}" >&2
  exit 1
fi
export MIX_ENV="${release_mix_env}"

if [[ ! -x "${zig_executable}" ]]; then
  printf 'missing qualified Zig 0.16.0 at %s; recover with: mix zig.get --version 0.16.0\n' \
    "${zig_executable}" >&2
  exit 1
fi

zig_version="$("${zig_executable}" version)"
if [[ "${zig_version}" != "0.16.0" ]]; then
  printf 'expected Zig 0.16.0 at %s, found %s; recover with: mix zig.get --version 0.16.0\n' \
    "${zig_executable}" "${zig_version}" >&2
  exit 1
fi

hex_archive="$(mix archive | sed -n 's/^\* \(hex-[^[:space:]]*\).*/\1/p' | head -n 1)"
if [[ -z "${hex_archive}" ]]; then
  printf 'Hex archive is unavailable; recover with: mix local.hex --force\n' >&2
  exit 1
fi

mix_home="$(elixir -e 'IO.write(Mix.Utils.mix_home())')"
rebar_executable="${MIX_REBAR3:-$(find "${mix_home}" -type f -name rebar3 -print -quit)}"
if [[ -z "${rebar_executable}" || ! -x "${rebar_executable}" ]]; then
  printf 'Rebar3 is unavailable under %s; recover with: mix local.rebar --force\n' \
    "${mix_home}" >&2
  exit 1
fi
rebar_version="$("${rebar_executable}" version)"

mix deps.compile zigler --force

formatter_beam="${MIX_BUILD_PATH:-_build}/${MIX_ENV}/lib/zigler/ebin/Elixir.Zig.Formatter.beam"
if [[ ! -f "${formatter_beam}" ]]; then
  printf 'Zig formatter plugin was not produced at %s; recover with: MIX_ENV=%s mix deps.compile zigler --force\n' \
    "${formatter_beam}" "${MIX_ENV}" >&2
  exit 1
fi

printf 'mix_env=%s\n' "${MIX_ENV}"
printf 'zig=%s (%s)\n' "${zig_version}" "${zig_executable}"
printf 'hex_archive=%s\n' "${hex_archive}"
printf 'rebar=%s (%s)\n' "${rebar_version}" "${rebar_executable}"
printf 'formatter=%s\n' "${formatter_beam}"
