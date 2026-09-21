defmodule SimdJson.PrecompiledDeliveryContractTest do
  use ExUnit.Case, async: true

  @phase ".spec/planning/milestone_06_publication_readiness/phase-05-precompiled-nif-delivery.md"

  # covers: simd_json.release.precompiled_delivery
  test "selects and verifies immutable supported-target artifacts" do
    loader = File.read!("lib/simd_json/native/precompiled.ex")
    bindings = File.read!("lib/simd_json/native/build_smoke.ex")
    project = File.read!("mix.exs")

    assert loader =~ ~S(simd_json-v#{version}-#{target}.so)
    assert loader =~ ~S(releases/download/v#{version})
    assert loader =~ "precompiled NIF checksum mismatch"
    assert loader =~ "no qualified precompiled NIF for target"
    assert loader =~ "SIMD_JSON_BUILD_FROM_SOURCE"
    assert project =~ ~s({:zigler, "== 0.16.0", runtime: false, optional: true})

    assert bindings =~ "@direct_nifs"
    assert bindings =~ "@marshalled_nifs"
    assert bindings =~ "@threaded_nifs"
    assert bindings =~ ":erlang.load_nif(path, 0)"
  end

  # covers: simd_json.release.precompiled_delivery
  test "closes the loader contract section" do
    phase = File.read!(@phase)
    [_, rest] = String.split(phase, "## 5.1 Section", parts: 2)
    section = rest |> String.split("## 5.2 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 5.1 Section"
  end
end
