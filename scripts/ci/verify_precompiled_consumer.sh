#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.precompiled_delivery simd_json.release.provenance

repository_root="$(git rev-parse --show-toplevel)"
version="$(sed -n 's/^  @version "\([^"]*\)"/\1/p' "${repository_root}/mix.exs")"
target="x86_64-linux-gnu"
asset_name="simd_json-v${version}-${target}.so"
candidate="${1:-${repository_root}/_build/precompiled/${asset_name}}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-consumer.XXXXXX")"
package_root="${scratch_root}/package/simd_json-${version}"
package_tar="${scratch_root}/package/simd_json-${version}.tar"
prepared_telemetry="${scratch_root}/prepared/telemetry"
consumer_root="${scratch_root}/consumer"
if asdf_mix="$(asdf which mix 2>/dev/null)"; then
  mix_executable="${asdf_mix}"
  default_mix_home="$(asdf where elixir)/.mix"
else
  mix_executable="$(command -v mix)"
  default_mix_home="${HOME}/.mix"
fi
elixir_bin="$(dirname "$(asdf which elixir 2>/dev/null || command -v elixir)")"
erl_bin="$(dirname "$(asdf which erl 2>/dev/null || command -v erl)")"
mix_home="${MIX_HOME:-${default_mix_home}}"
mix_archives="${MIX_ARCHIVES:-${mix_home}/archives}"
zig_free_path="${elixir_bin}:${erl_bin}:/usr/local/bin:/usr/bin:/bin"

cleanup() {
  local original_status=$?
  chmod -R u+w "${scratch_root}" 2>/dev/null || true
  rm -rf -- "${scratch_root}"
  return "${original_status}"
}

trap cleanup EXIT

if [[ ! -f "${candidate}" ]]; then
  "${repository_root}/scripts/release/build_precompiled_nif.sh"
fi

candidate_sha256="$(sha256sum "${candidate}" | cut -d ' ' -f 1)"
elixir "${repository_root}/scripts/release/verify_precompiled_checksum.exs" \
  "${candidate}" "${version}" "${target}" \
  "${repository_root}/native/precompiled/checksums.exs"

mkdir -p "$(dirname "${package_root}")" "${prepared_telemetry}" "${consumer_root}/lib"
cp -R "${repository_root}/deps/telemetry/." "${prepared_telemetry}/"
(
  cd "${repository_root}"
  mix hex.build --output "${package_tar}"
)
mkdir -p "${package_root}"
tar -xOf "${package_tar}" contents.tar.gz | tar -xzf - -C "${package_root}"

cat >"${consumer_root}/mix.exs" <<EOF
defmodule PrecompiledConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :precompiled_consumer,
      version: "0.1.0",
      elixir: "~> 1.18.4",
      deps: [
        {:simd_json, path: "${package_root}"},
        {:telemetry, path: "${prepared_telemetry}", override: true}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
EOF

cat >"${consumer_root}/lib/precompiled_consumer.ex" <<'EOF'
defmodule PrecompiledConsumer do
end
EOF

cat >"${consumer_root}/smoke.exs" <<'EOF'
{:ok, _} = Application.ensure_all_started(:telemetry)
Application.put_env(:simd_json, :native_workers, 1)
Application.put_env(:simd_json, :native_queue_size, 1)
{:ok, _} = Application.ensure_all_started(:simd_json)

handler = "precompiled-consumer-#{System.unique_integer([:positive])}"
parent = self()

:ok =
  :telemetry.attach_many(
    handler,
    [[:simd_json, :job, :start], [:simd_json, :job, :stop]],
    fn event, measurements, metadata, _config ->
      send(parent, {:telemetry, event, measurements, metadata})
    end,
    nil
  )

{:ok, %{"ready" => true, "rows" => [%{"id" => 1}, %{"id" => 2}]}} =
  SimdJson.decode(~s({"ready":true,"rows":[{"id":1},{"id":2}]}))

{:ok, %{id: 7}} = SimdJson.select(~s({"account":{"id":7}}), id: ["account", "id"])

[%{id: 1}, %{id: 2}] =
  SimdJson.stream(~s({"rows":[{"id":1},{"id":2}]}),
    path: ["rows"],
    fields: [id: ["id"]],
    batch_size: 1
  )
  |> Enum.to_list()

{:ok, document} = SimdJson.open(~s({"value":42}))
{:ok, %{value: 42}} = SimdJson.select(document, value: ["value"])
{:error, %{reason: :cursor_consumed}} = SimdJson.select(document, value: ["value"])
:ok = SimdJson.close(document)
:ok = SimdJson.close(document)

pool = SimdJson.Native.OperationCoordinator.pool_snapshot()
true = pool.worker_count in 1..64
true = pool.queue_capacity in 1..4096

await = fn predicate ->
  Enum.reduce_while(1..2_000, nil, fn _, _ ->
    if predicate.() do
      {:halt, :ok}
    else
      Process.sleep(1)
      {:cont, nil}
    end
  end) || raise "packaged consumer pool did not reach the expected state"
end

smoke = SimdJson.Native.BuildSmoke
payload_bytes = 16 * 1024 * 1024
large = ~s({"payload":") <> String.duplicate("x", payload_bytes) <> ~s("})
first = Task.async(fn -> SimdJson.decode(large) end)
:ok = await.(fn -> smoke.native_pool_snapshot().running_jobs == 1 end)
second = Task.async(fn -> SimdJson.decode(large) end)
:ok = await.(fn -> smoke.native_pool_snapshot().queued_jobs == 1 end)
%{worker_count: 1, queue_capacity: 1, running_jobs: 1, queued_jobs: 1} =
  smoke.native_pool_snapshot()
{:ok, %{"payload" => first_payload}} = Task.await(first, 60_000)
{:ok, %{"payload" => second_payload}} = Task.await(second, 60_000)
^payload_bytes = byte_size(first_payload)
^payload_bytes = byte_size(second_payload)

receive do
  {:telemetry, [:simd_json, :job, :start], measurements, %{operation: operation}}
  when is_integer(measurements.input_bytes) and operation in [:decode, :select, :stream_setup, :open] ->
    :ok
after
  1_000 -> raise "precompiled consumer did not receive start telemetry"
end

diagnostics = SimdJson.Native.Diagnostics.build()
"x86_64-linux-gnu" = diagnostics.target
true = diagnostics.runtime_implementation in ["haswell", "westmere", "fallback"]
true = is_integer(diagnostics.simdjson_version)

runtime_applications = Application.spec(:simd_json, :applications)
true = :telemetry in runtime_applications
false = Enum.any?([:jason, :spec_led_ex, :ex_doc, :zigler], &(&1 in runtime_applications))

:ok = :telemetry.detach(handler)
IO.puts("precompiled consumer smoke passed")
EOF

run_consumer() {
  local build_path="$1"
  shift

  (
    cd "${consumer_root}"
    env \
      PATH="${zig_free_path}" \
      MIX_ENV=prod \
      MIX_BUILD_PATH="${build_path}" \
      MIX_HOME="${mix_home}" \
      MIX_ARCHIVES="${mix_archives}" \
      HEX_OFFLINE=1 \
      ZIG_EXECUTABLE_PATH=/definitely-unavailable/zig \
      "$@"
  )
}

if PATH="${zig_free_path}" command -v zig >/dev/null 2>&1; then
  printf 'Zig unexpectedly remains available in consumer PATH\n' >&2
  exit 1
fi

run_consumer "${scratch_root}/positive-build" \
  SIMD_JSON_PRECOMPILED_PATH="${candidate}" \
  SIMD_JSON_PRECOMPILED_SHA256="${candidate_sha256}" \
  "${mix_executable}" compile

dependency_tree="$({
  run_consumer "${scratch_root}/positive-build" \
    SIMD_JSON_PRECOMPILED_PATH="${candidate}" \
    SIMD_JSON_PRECOMPILED_SHA256="${candidate_sha256}" \
    "${mix_executable}" deps.tree
} 2>&1)"

for development_dependency in zigler jason spec_led_ex ex_doc; do
  if grep -Fqi "${development_dependency}" <<<"${dependency_tree}"; then
    printf '%s entered the supported consumer dependency graph:\n%s\n' \
      "${development_dependency}" "${dependency_tree}" >&2
    exit 1
  fi
done

run_consumer "${scratch_root}/positive-build" \
  SIMD_JSON_PRECOMPILED_PATH="${candidate}" \
  SIMD_JSON_PRECOMPILED_SHA256="${candidate_sha256}" \
  "${mix_executable}" run --no-start --no-compile smoke.exs

corrupt_candidate="${scratch_root}/corrupt-${asset_name}"
cp "${candidate}" "${corrupt_candidate}"
printf '\000' >>"${corrupt_candidate}"

set +e
corrupt_output="$({
  run_consumer "${scratch_root}/corrupt-build" \
    SIMD_JSON_PRECOMPILED_PATH="${corrupt_candidate}" \
    SIMD_JSON_PRECOMPILED_SHA256="${candidate_sha256}" \
    "${mix_executable}" deps.compile simd_json --force
} 2>&1)"
corrupt_status=$?
set -e

if ((corrupt_status == 0)) || ! grep -Fq 'precompiled NIF checksum mismatch' <<<"${corrupt_output}"; then
  printf 'corrupt artifact did not fail closed:\n%s\n' "${corrupt_output}" >&2
  exit 1
fi

set +e
checksum_output="$({
  run_consumer "${scratch_root}/checksum-build" \
    SIMD_JSON_PRECOMPILED_PATH="${candidate}" \
    SIMD_JSON_PRECOMPILED_SHA256="$(printf '0%.0s' {1..64})" \
    "${mix_executable}" deps.compile simd_json --force
} 2>&1)"
checksum_status=$?
set -e

if ((checksum_status == 0)) || ! grep -Fq 'precompiled NIF checksum mismatch' <<<"${checksum_output}"; then
  printf 'incorrect checksum did not fail closed:\n%s\n' "${checksum_output}" >&2
  exit 1
fi

set +e
missing_output="$({
  run_consumer "${scratch_root}/missing-build" \
    SIMD_JSON_PRECOMPILED_PATH="${scratch_root}/missing-${asset_name}" \
    SIMD_JSON_PRECOMPILED_SHA256="${candidate_sha256}" \
    "${mix_executable}" deps.compile simd_json --force
} 2>&1)"
missing_status=$?
set -e

if ((missing_status == 0)) || ! grep -Fq 'precompiled NIF does not exist' <<<"${missing_output}"; then
  printf 'missing artifact did not fail closed:\n%s\n' "${missing_output}" >&2
  exit 1
fi

if find "${scratch_root}/corrupt-build" "${scratch_root}/checksum-build" \
  "${scratch_root}/missing-build" -type f -name '*.so' -print -quit | grep -q .; then
  printf 'failed consumer compilation left a partial native artifact\n' >&2
  exit 1
fi

set +e
unsupported_output="$({
  run_consumer "${scratch_root}/positive-build" \
    SIMD_JSON_PRECOMPILED_PATH="${candidate}" \
    SIMD_JSON_PRECOMPILED_SHA256="${candidate_sha256}" \
    "${mix_executable}" run --no-start --no-compile -e \
    'SimdJson.Native.Precompiled.resolve!(target: "aarch64-linux-gnu", mix_env: :prod, source_checkout: false)'
} 2>&1)"
unsupported_status=$?
set -e

if ((unsupported_status == 0)) ||
  ! grep -Fq 'no qualified precompiled NIF for target aarch64-linux-gnu' \
    <<<"${unsupported_output}"; then
  printf 'unsupported target did not fail early and actionably:\n%s\n' \
    "${unsupported_output}" >&2
  exit 1
fi

printf 'Zig-free packaged consumer verification passed\n'
