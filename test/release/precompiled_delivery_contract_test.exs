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

  # covers: simd_json.release.precompiled_delivery simd_json.release.provenance
  test "defines reproducible artifact and checksum provenance gates" do
    builder = File.read!("scripts/release/build_precompiled_nif.sh")
    verifier = File.read!("scripts/release/verify_precompiled_checksum.exs")

    assert builder =~ "build-one"
    assert builder =~ "build-two"
    assert builder =~ "cmp --silent"
    assert builder =~ "ldd"
    assert builder =~ "nm -D --defined-only"
    assert builder =~ "exported_symbols=nif_init"
    assert builder =~ "source_commit="
    assert builder =~ "source_tree="
    assert builder =~ "SHA256SUMS"
    assert verifier =~ "precompiled checksum mismatch"

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/release/build_precompiled_nif.sh"],
               stderr_to_stdout: true
             )
  end

  # covers: simd_json.release.precompiled_delivery simd_json.release.provenance
  test "defines a Zig-free packaged consumer and non-publishing artifact workflow" do
    consumer = File.read!("scripts/ci/verify_precompiled_consumer.sh")
    workflow = File.read!(".github/workflows/precompiled-nif.yml")
    qualification = File.read!("scripts/ci/qualify_milestone_5.sh")

    assert consumer =~ "ZIG_EXECUTABLE_PATH=/definitely-unavailable/zig"
    assert consumer =~ "deps.tree"
    assert consumer =~ "precompiled NIF checksum mismatch"
    assert consumer =~ "SimdJson.Native.Diagnostics.build()"
    assert workflow =~ "workflow_dispatch"
    assert workflow =~ "actions/upload-artifact@"
    refute workflow =~ "gh release"
    refute workflow =~ "mix hex.publish"
    assert qualification =~ "verify_precompiled_consumer.sh"

    phase = File.read!(@phase)
    [_, rest] = String.split(phase, "## 5.3 Section", parts: 2)
    section = rest |> String.split("## 5.4 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 5.3 Section"

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/ci/verify_precompiled_consumer.sh"],
               stderr_to_stdout: true
             )
  end

  # covers: simd_json.release.precompiled_delivery simd_json.release.recovery_readiness
  test "documents asset-first publication and closes Phase 5" do
    readme = File.read!("README.md")
    installation = File.read!("docs/releases/installation.md")
    publishing = File.read!("docs/releases/publishing.md")

    phase_seven =
      File.read!(
        ".spec/planning/milestone_06_publication_readiness/phase-07-version-tag-publish-and-post-publish-verification.md"
      )

    phase = File.read!(@phase)
    [_, section] = String.split(phase, "## 5.4 Section", parts: 2)

    assert readme =~ "Ordinary package consumers do not need Zig"
    assert installation =~ "SIMD_JSON_PRECOMPILED_PATH"
    assert publishing =~ "Hex publication is forbidden until"
    assert phase_seven =~ "GitHub Release and Precompiled Asset"
    assert phase_seven =~ "before Hex"
    refute section =~ "- [ ]"
    assert section =~ "- [x] 5.4 Section"
    assert phase =~ "- [x] 5 Phase"
  end
end
