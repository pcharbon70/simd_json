defmodule SimdJson.Phase6ReleaseCandidateContractTest do
  use ExUnit.Case, async: true

  @phase ".spec/planning/milestone_06_publication_readiness/phase-06-release-candidate-qualification-and-go-no-go.md"
  @qualification "scripts/ci/qualify_release_candidate.sh"

  # covers: simd_json.release.green_ci simd_json.release.candidate_preflight
  test "qualifies the exact supported-target candidate and retains bounded proof" do
    script = File.read!(@qualification)
    workflow = File.read!(".github/workflows/ci.yml")

    assert script =~ "Ubuntu 24.04"
    assert script =~ "qualify_milestone_5.sh"
    assert script =~ "independent_native_build_roots=2"
    assert script =~ "archive_build_roots=2"
    assert script =~ "source_revision="
    assert script =~ "source_tree="
    assert script =~ "publication_authorized=false"
    assert script =~ "xargs -0 sha256sum >SHA256SUMS"
    assert workflow =~ "qualify_release_candidate.sh"
    assert workflow =~ "cache-mode: [cold, restored]"

    refute script =~ "mix hex.publish"
    refute script =~ "git tag "
    refute script =~ "gh release create"

    assert {_output, 0} =
             System.cmd("bash", ["-n", @qualification], stderr_to_stdout: true)
  end

  test "closes supported-target clean qualification" do
    phase = File.read!(@phase)
    [_, rest] = String.split(phase, "## 6.1 Section", parts: 2)
    section = rest |> String.split("## 6.2 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 6.1 Section"
  end

  # covers: simd_json.release.archive_integrity simd_json.release.precompiled_delivery
  test "installs the archive into an offline Zig-free consumer and fails closed" do
    consumer = File.read!("scripts/ci/verify_precompiled_consumer.sh")

    assert consumer =~ "mix hex.build --output \"${package_tar}\""
    assert consumer =~ "tar -xOf \"${package_tar}\" contents.tar.gz"
    assert consumer =~ "prepared_telemetry"
    assert consumer =~ "HEX_OFFLINE=1"
    assert consumer =~ "ZIG_EXECUTABLE_PATH=/definitely-unavailable/zig"
    assert consumer =~ "SimdJson.decode"
    assert consumer =~ "SimdJson.select"
    assert consumer =~ "SimdJson.stream"
    assert consumer =~ "cursor_consumed"
    assert consumer =~ ":telemetry.attach_many"
    assert consumer =~ "pool.queue_capacity"
    assert consumer =~ "running_jobs: 1, queued_jobs: 1"
    assert consumer =~ "16 * 1024 * 1024"
    assert consumer =~ "precompiled NIF does not exist"
    assert consumer =~ "precompiled NIF checksum mismatch"
    assert consumer =~ "aarch64-linux-gnu"
    assert consumer =~ "failed consumer compilation left a partial native artifact"
    assert consumer =~ "[:jason, :spec_led_ex, :ex_doc, :zigler]"

    refute consumer =~ ~S|path: "${repository_root}/deps/telemetry"|

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/ci/verify_precompiled_consumer.sh"],
               stderr_to_stdout: true
             )
  end

  test "closes fresh consumer archive qualification" do
    phase = File.read!(@phase)
    [_, rest] = String.split(phase, "## 6.2 Section", parts: 2)
    section = rest |> String.split("## 6.3 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 6.2 Section"
  end
end
