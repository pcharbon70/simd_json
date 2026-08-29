#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.document_api.milestone_scope simd_json.document_api.no_future_surface simd_json.native_build_and_abi.release_symbol_surface simd_json.native_execution.preproduction_boundary

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/scope}"
nif_path="${repository_root}/_build/test/lib/simd_json/priv/lib/Elixir.SimdJson.Native.BuildSmoke.so"

mkdir -p "${evidence_root}"

env MIX_ENV=test mix compile --force 2>&1 | tee "${evidence_root}/compile.log"
env MIX_ENV=test mix test test/simd_json/public_surface_test.exs --seed 0 2>&1 \
  | tee "${evidence_root}/public-surface.log"
bash scripts/native/verify_release_symbols.sh 2>&1 \
  | tee "${evidence_root}/release-symbols.log"

env MIX_ENV=test mix run --no-compile -e '
  modules = [SimdJson, SimdJson.Document, SimdJson.Error]

  Enum.each(modules, fn module ->
    IO.puts("module=#{inspect(module)}")
    IO.puts("functions=#{inspect(module.__info__(:functions))}")
    IO.puts("types=#{inspect(Code.Typespec.fetch_types(module))}")
    IO.puts("documented=#{match?({:docs_v1, _, _, _, %{} = docs, _, _} when map_size(docs) > 0, Code.fetch_docs(module))}")
  end)

  IO.puts("native_functions=#{inspect(SimdJson.Native.BuildSmoke.__info__(:functions))}")
' >"${evidence_root}/elixir-surface.txt"

nm -D --defined-only "${nif_path}" | LC_ALL=C sort \
  >"${evidence_root}/nif-dynamic-symbols.txt"

cp native/symbols/nif.allowlist "${evidence_root}/nif-symbol-allowlist.txt"
cp native/symbols/c_abi.allowlist "${evidence_root}/c-abi-symbol-allowlist.txt"

printf 'Milestone 1 release surface matches its allowlists\n' \
  | tee "${evidence_root}/summary.txt"
