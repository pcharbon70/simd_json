#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership

repository_root="$(git rev-parse --show-toplevel)"
zig_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
zig_executable="${ZIG_EXECUTABLE_PATH:-${zig_cache_root}/zigler/zig-x86_64-linux-0.16.0/zig}"

if [[ ! -x "${zig_executable}" ]]; then
  printf 'qualified Zig executable is unavailable: %s\n' "${zig_executable}" >&2
  exit 1
fi

"${zig_executable}" test \
  -I "${repository_root}/native/include" \
  --dep document_resource \
  -Mroot="${repository_root}/native/test/document_resource_test.zig" \
  -Mdocument_resource="${repository_root}/native/zig/document_resource.zig" \
  -O Debug
