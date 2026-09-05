defmodule SimdJson.CIReliabilityContractTest do
  use ExUnit.Case, async: true

  @sanitizer_script "scripts/native/run_nif_sanitizer_tests.sh"
  @research ".spec/research/milestone_06_ci_failure_reproduction.md"
  @release_spec ".spec/specs/release.spec.md"

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
end
