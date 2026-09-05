defmodule SimdJson.CIReliabilityContractTest do
  use ExUnit.Case, async: true

  @sanitizer_script "scripts/native/run_nif_sanitizer_tests.sh"
  @research ".spec/research/milestone_06_ci_failure_reproduction.md"
  @release_spec ".spec/specs/release.spec.md"
  @bootstrap_script "scripts/ci/bootstrap_release_tools.sh"
  @aggregate_script "scripts/ci/qualify_milestone_5.sh"
  @workflow ".github/workflows/ci.yml"
  @native_source "native/zig/build_smoke.zig"

  # covers: simd_json.release.green_ci simd_json.release.ci_native_reliability
  test "preserves a deterministic sanitizer failure seed and optional trace mode" do
    script = File.read!(@sanitizer_script)

    assert script =~ ~s(SIMD_JSON_NIF_SANITIZER_SEED:-935088)
    assert script =~ ~s(SIMD_JSON_NIF_SANITIZER_TRACE:-0)
    assert script =~ ~S|test_options=(--seed "${sanitizer_seed}")|
    assert script =~ ~S|test_options=(--seed "${sanitizer_seed}" --trace)|
    assert script =~ ~S|mix test --no-compile "${test_options[@]}"|
  end

  # covers: simd_json.release.green_ci simd_json.release.ci_cache_equivalence simd_json.release.ci_native_reliability
  test "records exact cold-cache and native failure evidence" do
    research = File.read!(@research)
    release_spec = File.read!(@release_spec)

    assert research =~ "33985428541"
    assert research =~ "33986146760"
    assert research =~ "ethr_mutex_lock(): Invalid argument (22)"
    assert research =~ "seed `935088`"
    assert research =~ "seed `661703`"
    assert research =~ "empty build/cache path and a restored path"
    assert release_spec =~ "simd_json.release.ci_cache_equivalence"
    assert release_spec =~ "simd_json.release.ci_native_reliability"
  end

  # covers: simd_json.release.green_ci simd_json.release.ci_cache_equivalence
  test "bootstraps the exact release tools before the strict formatting gate" do
    bootstrap = File.read!(@bootstrap_script)
    aggregate = File.read!(@aggregate_script)
    workflow = File.read!(@workflow)

    assert bootstrap =~ ~s(release_mix_env="${SIMD_JSON_RELEASE_MIX_ENV:-test}")
    assert bootstrap =~ ~s(expected Zig 0.16.0)
    assert bootstrap =~ ~s(mix deps.compile zigler --force)
    assert bootstrap =~ ~s(Elixir.Zig.Formatter.beam)
    assert bootstrap =~ ~s(hex_archive=)
    assert bootstrap =~ ~s(rebar=)
    assert bootstrap =~ ~s(mix zig.get --version 0.16.0)

    {bootstrap_offset, _} = :binary.match(aggregate, "run_step release_tool_bootstrap")
    {format_offset, _} = :binary.match(aggregate, "run_step formatting")
    assert bootstrap_offset < format_offset
    assert workflow =~ "bash scripts/ci/bootstrap_release_tools.sh"

    assert {_output, 0} = System.cmd("bash", ["-n", @bootstrap_script])
  end

  # covers: simd_json.release.ci_cache_equivalence
  test "isolates alternate native builds from canonical build inputs" do
    for script <- [
          @sanitizer_script,
          "scripts/native/verify_release_symbols.sh",
          "scripts/ci/verify_offline_native_build.sh"
        ] do
      contents = File.read!(script)
      assert contents =~ "mktemp -d"
      assert contents =~ "MIX_BUILD_PATH="
      assert contents =~ "ZIG_LOCAL_CACHE_DIR="
    end
  end

  # covers: simd_json.native_pool.shutdown simd_json.release.ci_native_reliability
  test "serializes public shared-pool access with pool retirement" do
    source = File.read!(@native_source)
    guarded_functions = Regex.scan(~r/const guard = PoolLifecycleGuard\.acquire\(\)/, source)

    assert source =~ "pool_lifecycle_mutex"
    assert source =~ "enif_mutex_destroy(lifecycle_mutex)"
    assert source =~ "pool_lifecycle_mutex.swap(null, .acq_rel)"
    assert length(guarded_functions) == 17
  end

  # covers: simd_json.release.green_ci simd_json.release.provenance
  test "cancels only superseded pull requests and bounds qualification time" do
    workflow = File.read!(@workflow)

    assert workflow =~ "group: ci-${{ github.workflow }}-"
    assert workflow =~ "cancel-in-progress: ${{ github.event_name == 'pull_request' }}"
    assert workflow =~ "timeout-minutes: 60"
    assert workflow =~ "timeout-minutes: 45"
    assert workflow =~ "permissions:\n  contents: read"

    action_references = Regex.scan(~r/^\s*uses:\s+[^@\s]+@([^\s]+)/m, workflow)
    assert action_references != []

    for [_, reference] <- action_references do
      assert reference =~ ~r/^[0-9a-f]{40}$/
    end
  end

  # covers: simd_json.release.green_ci simd_json.release.provenance
  test "retains partial failure evidence and checksums complete evidence" do
    aggregate = File.read!(@aggregate_script)
    workflow = File.read!(@workflow)

    assert aggregate =~ "trap finalize_qualification EXIT"
    assert aggregate =~ "failed_gate=%s"
    assert aggregate =~ "source_revision=%s"
    assert aggregate =~ "source_tree=%s"
    assert aggregate =~ "evidence_path=%s"
    assert aggregate =~ "git restore --source=HEAD -- .spec/state.json"
    assert aggregate =~ "qualification_status=passed"
    assert aggregate =~ "xargs -0 sha256sum >SHA256SUMS"

    assert workflow =~ "if: always()"
    assert workflow =~ "GITHUB_STEP_SUMMARY"
    assert workflow =~ "milestone-6-release-qualification-${{ github.sha }}"
    assert workflow =~ "if-no-files-found: warn"
  end
end
