#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.archive_integrity simd_json.release.consumer_documentation

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_PACKAGE_EVIDENCE_DIR:-${repository_root}/_build/qualification/package-documentation}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-package-docs.XXXXXX")"
archive_path="${scratch_root}/simd_json-0.1.0.tar"
package_root="${scratch_root}/simd_json-0.1.0"
docs_root="${scratch_root}/docs"
package_compressed_limit=$((8 * 1024 * 1024))
package_uncompressed_limit=$((64 * 1024 * 1024))
docs_compressed_limit=$((8 * 1024 * 1024))
docs_uncompressed_limit=$((64 * 1024 * 1024))

cleanup() {
  local original_status=$?

  chmod -R u+w "${scratch_root}" 2>/dev/null || true
  rm -rf -- "${scratch_root}"
  return "${original_status}"
}

trap cleanup EXIT
mkdir -p "${evidence_root}"
cd "${repository_root}"

run_step() {
  local name="$1"
  shift

  printf '%s\n' "$*" >"${evidence_root}/${name}.command"
  "$@" 2>&1 | tee "${evidence_root}/${name}.log"
}

# Hex 2.2.2 asks for authentication even during a dry run. A deliberately
# invalid placeholder makes the local package checks non-interactive and makes
# accidental publication impossible; no real credential is read or emitted.
run_step hex_dry_run \
  env HEX_API_KEY=unused-dry-run-placeholder \
  mix hex.publish package --dry-run --yes

run_step archive_build mix hex.build --output "${archive_path}"
run_step archive_unpack mix hex.build --unpack --output "${package_root}"
run_step exdoc mix docs --warnings-as-errors --formatter html --output "${docs_root}"
run_step exdoc_links elixir scripts/ci/validate_exdoc_links.exs "${docs_root}"

required_package_files=(
  .tool-versions
  CHANGELOG.md
  CONTRIBUTING.md
  LICENSE
  README.md
  SECURITY.md
  THIRD_PARTY_NOTICES.md
  docs/milestones/README.md
  docs/milestones/01-native-foundation.md
  docs/milestones/01-native-foundation-operations.md
  docs/milestones/01-native-foundation-acceptance.md
  docs/milestones/02-projection-api.md
  docs/milestones/02-projection-api-operations.md
  docs/milestones/02-projection-api-acceptance.md
  docs/milestones/03-batched-array-streaming.md
  docs/milestones/03-batched-array-streaming-operations.md
  docs/milestones/03-batched-array-streaming-acceptance.md
  docs/milestones/04-worker-pool-and-operations.md
  docs/milestones/05-compatible-decode-api.md
  docs/milestones/05-compatible-decode-api-acceptance.md
  docs/releases/ci-policy.md
  docs/releases/installation.md
  docs/releases/support.md
  lib/simd_json.ex
  lib/simd_json/application.ex
  lib/simd_json/decode_options.ex
  lib/simd_json/document.ex
  lib/simd_json/error.ex
  lib/simd_json/native/build_guard.ex
  lib/simd_json/native/build_smoke.ex
  lib/simd_json/native/diagnostics.ex
  lib/simd_json/native/operation_coordinator.ex
  lib/simd_json/native/pool_options.ex
  lib/simd_json/native/projection_operation.ex
  lib/simd_json/native/telemetry.ex
  lib/simd_json/native/threaded_operation.ex
  lib/simd_json/projection.ex
  lib/simd_json/stream.ex
  lib/simd_json/stream_options.ex
  mix.exs
  mix.lock
  native/README.md
  native/manifest.exs
  native/qualification/milestone_1.exs
  native/include/simd_json_abi.h
  native/include/simd_json_build_smoke.h
  native/include/simd_json_nif_internal.h
  native/include/simd_json_test_hooks.h
  native/src/build_smoke.cpp
  native/src/simd_json_abi.cpp
  native/src/simd_json_decode_materializer.cpp
  native/src/simd_json_native_internal.hpp
  native/src/simd_json_projection.cpp
  native/src/simd_json_stream_cursor.cpp
  native/symbols/c_abi.allowlist
  native/symbols/c_abi.version
  native/symbols/nif.allowlist
  native/vendor/simdjson/LICENSE
  native/vendor/simdjson/LICENSE-MIT
  native/vendor/simdjson/README.md
  native/vendor/simdjson/patches/series
  native/vendor/simdjson/simdjson.cpp
  native/vendor/simdjson/simdjson.h
  native/zig/build_smoke.zig
  native/zig/decode_materializer.zig
  native/zig/document_resource.zig
  native/zig/projection_plan.zig
  native/zig/stream_cursor.zig
  native/zig/worker_pool.zig
)

for relative_path in "${required_package_files[@]}"; do
  if [[ ! -f "${package_root}/${relative_path}" ]]; then
    printf 'package is missing required file: %s\n' "${relative_path}" >&2
    exit 1
  fi
done

for forbidden_directory in test bench scripts .spec .github lib/mix native/test; do
  if [[ -e "${package_root}/${forbidden_directory}" ]]; then
    printf 'package contains forbidden development directory: %s\n' \
      "${forbidden_directory}" >&2
    exit 1
  fi
done

for forbidden_file in .formatter.exs .env .env.production credentials secrets; do
  if [[ -e "${package_root}/${forbidden_file}" ]]; then
    printf 'package contains forbidden root file: %s\n' "${forbidden_file}" >&2
    exit 1
  fi
done

generated_files="$(
  find "${package_root}" -type f \
    \( -name '*.so' -o -name '*.beam' -o -name '*.o' -o -name '.Elixir.*.zig' \
    -o -name '*.swp' -o -name '*.swo' -o -name '.DS_Store' -o -name '*~' \) \
    -printf '%P\n'
)"

if [[ -n "${generated_files}" ]]; then
  printf 'package contains generated, cache, or editor files:\n%s\n' "${generated_files}" >&2
  exit 1
fi

metadata_path="${evidence_root}/package-metadata.config"
tar -xOf "${archive_path}" metadata.config >"${metadata_path}"

for required_metadata in \
  '{<<"name">>,<<"simd_json">>}' \
  '{<<"version">>,<<"0.1.0">>}' \
  '<<"zigler">>' \
  '<<"telemetry">>' \
  '<<"MIT">>' \
  '<<"~> 1.18.4">>'; do
  if ! grep -Fq "${required_metadata}" "${metadata_path}"; then
    printf 'package metadata is missing: %s\n' "${required_metadata}" >&2
    exit 1
  fi
done

for forbidden_dependency in jason spec_led_ex; do
  if grep -Fq "${forbidden_dependency}" "${metadata_path}"; then
    printf 'development-only dependency entered package metadata: %s\n' \
      "${forbidden_dependency}" >&2
    exit 1
  fi
done

secret_pattern_names=(
  private_key
  aws_access_key
  github_legacy_token
  github_fine_grained_token
  stripe_secret_key
  assigned_high_entropy_secret
)

secret_patterns=(
  '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
  '(AKIA|ASIA)[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9]{30,}'
  'github_pat_[A-Za-z0-9_]{50,}'
  'sk_(live|test)_[0-9A-Za-z]{20,}'
  "(HEX_API_KEY|AWS_SECRET_ACCESS_KEY|GITHUB_TOKEN|PASSWORD)[[:space:]]*[:=][[:space:]]*['\"]?[^[:space:]'\"]{16,}"
)

printf 'hex_dry_run=passed\n' >"${evidence_root}/secret-scan.txt"

for index in "${!secret_patterns[@]}"; do
  set +e
  matches="$(rg -l -I --hidden --pcre2 --regexp "${secret_patterns[index]}" "${package_root}")"
  scan_status=$?
  set -e

  if ((scan_status == 0)); then
    printf 'secret pattern %s matched packaged file(s):\n%s\n' \
      "${secret_pattern_names[index]}" "${matches}" >&2
    exit 1
  fi

  if ((scan_status != 1)); then
    printf 'secret scanner failed for pattern %s with status %s\n' \
      "${secret_pattern_names[index]}" "${scan_status}" >&2
    exit 1
  fi

  printf '%s=clear\n' "${secret_pattern_names[index]}" >>"${evidence_root}/secret-scan.txt"
done

package_compressed_bytes="$(stat -c '%s' "${archive_path}")"
package_uncompressed_bytes="$(du -sb "${package_root}" | cut -f1)"
docs_uncompressed_bytes="$(du -sb "${docs_root}" | cut -f1)"
tar -czf "${scratch_root}/docs.tar.gz" -C "${docs_root}" .
docs_compressed_bytes="$(stat -c '%s' "${scratch_root}/docs.tar.gz")"

if ((package_compressed_bytes > package_compressed_limit)); then
  printf 'compressed package exceeds Hex 8 MiB limit: %s bytes\n' \
    "${package_compressed_bytes}" >&2
  exit 1
fi

if ((package_uncompressed_bytes > package_uncompressed_limit)); then
  printf 'unpacked package exceeds Hex 64 MiB limit: %s bytes\n' \
    "${package_uncompressed_bytes}" >&2
  exit 1
fi

if ((docs_compressed_bytes > docs_compressed_limit)); then
  printf 'compressed documentation exceeds Hex 8 MiB limit: %s bytes\n' \
    "${docs_compressed_bytes}" >&2
  exit 1
fi

if ((docs_uncompressed_bytes > docs_uncompressed_limit)); then
  printf 'documentation exceeds Hex 64 MiB limit: %s bytes\n' \
    "${docs_uncompressed_bytes}" >&2
  exit 1
fi

{
  printf 'package_compressed_bytes=%s\n' "${package_compressed_bytes}"
  printf 'package_uncompressed_bytes=%s\n' "${package_uncompressed_bytes}"
  printf 'docs_compressed_bytes=%s\n' "${docs_compressed_bytes}"
  printf 'docs_uncompressed_bytes=%s\n' "${docs_uncompressed_bytes}"
} >"${evidence_root}/sizes.txt"

sha256sum "${archive_path}" | sed "s#${archive_path}#simd_json-0.1.0.tar#" \
  >"${evidence_root}/package.sha256"

(
  cd "${package_root}"
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
) >"${evidence_root}/package-files.sha256"

find "${package_root}" -type f -printf '%P\n' | LC_ALL=C sort \
  >"${evidence_root}/package-contents.txt"
find "${docs_root}" -type f -printf '%P\n' | LC_ALL=C sort \
  >"${evidence_root}/documentation-contents.txt"

printf 'Package archive and documentation verification passed\n' \
  | tee "${evidence_root}/summary.txt"
