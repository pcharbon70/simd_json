defmodule SimdJson.ReleaseToolingContractTest do
  use ExUnit.Case, async: true

  @preflight "scripts/release/preflight.sh"
  @preflight_guide "docs/releases/preflight.md"
  @provenance_guide "docs/releases/provenance.md"
  @publishing_guide "docs/releases/publishing.md"
  @recovery_guide "docs/releases/recovery.md"
  @phase ".spec/planning/milestone_06_publication_readiness/phase-04-release-tooling-provenance-and-recovery.md"

  # covers: simd_json.release.read_only_preflight simd_json.release.candidate_preflight
  test "defines a credential-free read-only release preflight" do
    script = File.read!(@preflight)
    guide = File.read!(@preflight_guide)

    assert script =~ "release preflight refuses to run while HEX_API_KEY is set"
    assert script =~ "git symbolic-ref --quiet --short HEAD"
    assert script =~ "git status --porcelain=v1 --untracked-files=all"
    assert script =~ "git ls-remote --heads origin refs/heads/main"
    assert script =~ "git ls-remote --exit-code --tags origin"
    assert script =~ "https://hex.pm/api/packages/simd_json/releases/"
    assert script =~ "mix format --check-formatted"
    assert script =~ "mix docs --warnings-as-errors"
    assert script =~ "verify_package_documentation.sh"
    assert script =~ "mix simd_json.verify_qualification"
    assert script =~ "mix spec.check --no-run-commands"
    assert script =~ "preflight.env"
    assert script =~ "SHA256SUMS"

    refute script =~ "mix hex.publish --yes"
    refute script =~ "git tag "
    refute script =~ "git push "
    refute script =~ "gh release create"

    assert guide =~ "clean `main` checkout"
    assert guide =~ ~r/deliberately does\s+not fetch/
    assert guide =~ "unset HEX_API_KEY"
    assert guide =~ "never reads Hex ownership or key data"
    assert guide =~ "Full release-candidate qualification remains a separate Phase 5 gate"

    assert {_output, 0} =
             System.cmd("bash", ["-n", @preflight], stderr_to_stdout: true)
  end

  # covers: simd_json.release.read_only_preflight
  test "rejects ambiguous identity and inherited publication credentials before IO" do
    {usage, 64} = System.cmd("/bin/bash", [@preflight], stderr_to_stdout: true)
    assert usage =~ "usage: preflight.sh VERSION TAG"

    {invalid_version, 64} =
      System.cmd("/bin/bash", [@preflight, "01.0.0", "v01.0.0"], stderr_to_stdout: true)

    assert invalid_version =~ "not a plain semantic version"

    {credential_guard, 64} =
      System.cmd("/bin/bash", [@preflight, "0.1.0", "v0.1.0"],
        env: [{"HEX_API_KEY", "must-not-be-printed"}],
        stderr_to_stdout: true
      )

    assert credential_guard =~ "refuses to run while HEX_API_KEY is set"
    refute credential_guard =~ "must-not-be-printed"
  end

  # covers: simd_json.release.read_only_preflight
  test "closes every read-only preflight planning task" do
    phase = File.read!(@phase)
    [_, phase_sections] = String.split(phase, "## 4.1 Section", parts: 2)
    section = phase_sections |> String.split("## 4.2 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 4.1 Section"
  end

  # covers: simd_json.release.archive_integrity simd_json.release.provenance
  test "binds an exactly reproducible archive to retained provenance" do
    verifier = File.read!("scripts/ci/verify_package_documentation.sh")
    aggregate = File.read!("scripts/ci/qualify_milestone_5.sh")
    inventory = File.read!("scripts/ci/generate_dependency_inventory.exs")
    workflow = File.read!(".github/workflows/ci.yml")
    guide = File.read!(@provenance_guide)

    assert verifier =~ "archive_build_first"
    assert verifier =~ "archive_build_second"
    assert verifier =~ "package-files.normalized.tsv"
    assert verifier =~ "cmp -s"
    assert verifier =~ "repeated_archive_sha256"
    assert verifier =~ "simd_json-0.1.0.tar"
    assert verifier =~ "dependency-licenses.tsv"
    assert verifier =~ "provenance.env"
    assert verifier =~ "qualification_input_sha256"
    assert verifier =~ "archive_reproducible=true"
    assert verifier =~ "nondeterministic_fields=none"
    assert verifier =~ "SHA256SUMS"

    assert inventory =~ "hex_metadata.config"
    assert inventory =~ "Apache-2.0 OR MIT"
    assert inventory =~ "optional"

    assert aggregate =~ "SIMD_JSON_REQUIRE_CLEAN_CANDIDATE=1"
    assert aggregate =~ ~s(${qualification_root}/release-candidate)
    assert workflow =~ "milestone-6-release-qualification-${{ matrix.cache-mode }}-"
    assert workflow =~ "path: _build/qualification"
    assert workflow =~ "retention-days: 30"

    assert guide =~ ~r/both complete archive SHA-256\s+digests to match/
    assert guide =~ "nondeterministic_fields=none"
    assert guide =~ "fixed 30-day"

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/ci/verify_package_documentation.sh"],
               stderr_to_stdout: true
             )
  end

  # covers: simd_json.release.provenance
  test "closes every archive provenance planning task" do
    phase = File.read!(@phase)
    [_, phase_sections] = String.split(phase, "## 4.2 Section", parts: 2)
    section = phase_sections |> String.split("## 4.3 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 4.2 Section"
  end

  # covers: simd_json.release.publisher_boundary simd_json.release.explicit_authorization
  test "keeps first-publication authentication interactive and credential-free" do
    policy = File.read!("release/publisher-policy.env")
    verifier = File.read!("scripts/release/verify_publisher.sh")
    guide = File.read!(@publishing_guide)
    workflows = Path.wildcard(".github/workflows/*.yml") |> Enum.map_join(&File.read!/1)

    assert policy =~ "publisher=pcharbon70"
    assert policy =~ "recovery_owner=pcharbon70"
    assert policy =~ "execution_model=interactive_reviewed"
    assert policy =~ "ci_publication=disabled"

    assert verifier =~ "mix hex.user whoami"
    assert verifier =~ "refuses to run while HEX_API_KEY is set"
    assert verifier =~ "credential_loaded=false"
    refute verifier =~ "hex.user key"
    refute verifier =~ "hex.publish"

    assert guide =~ "interactive, reviewed maintainer"
    assert guide =~ "CI publication is disabled"
    assert guide =~ "manual dispatch with an exact"
    assert guide =~ "no pull-request trigger or secret"
    assert guide =~ "short-lived and limited"
    assert guide =~ "credentials must never appear"

    refute workflows =~ "HEX_API_KEY"
    refute workflows =~ "mix hex.publish"

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/release/verify_publisher.sh"],
               stderr_to_stdout: true
             )

    {credential_guard, 64} =
      System.cmd("/bin/bash", ["scripts/release/verify_publisher.sh"],
        env: [{"HEX_API_KEY", "must-not-be-printed"}],
        stderr_to_stdout: true
      )

    assert credential_guard =~ "refuses to run while HEX_API_KEY is set"
    refute credential_guard =~ "must-not-be-printed"
  end

  # covers: simd_json.release.publisher_boundary
  test "closes every publisher boundary planning task" do
    phase = File.read!(@phase)
    [_, phase_sections] = String.split(phase, "## 4.3 Section", parts: 2)
    section = phase_sections |> String.split("## 4.4 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 4.3 Section"
  end

  # covers: simd_json.release.recovery_readiness simd_json.release.explicit_authorization
  test "rehearses every recovery evidence failure without external mutation" do
    verifier = File.read!("scripts/release/verify_candidate_evidence.sh")
    rehearsal = File.read!("scripts/release/rehearse_recovery.sh")
    package_verifier = File.read!("scripts/ci/verify_package_documentation.sh")
    aggregate = File.read!("scripts/ci/qualify_milestone_5.sh")
    guide = File.read!(@recovery_guide)

    assert verifier =~ "candidate documentation does not contain index.html"
    assert verifier =~ "candidate native compilation did not pass"
    assert verifier =~ "candidate evidence checksum verification failed"
    assert verifier =~ "candidate secret scan reports a possible credential"

    for scenario <- [
          "missing_docs",
          "broken_native_compile",
          "checksum_mismatch",
          "leaked_secret"
        ] do
      assert rehearsal =~ "expect_failure #{scenario}"
    end

    assert rehearsal =~ "external_mutation=none"
    refute rehearsal =~ "mix hex.publish"
    refute rehearsal =~ "mix hex.retire"
    refute rehearsal =~ ~r/^gh release/m

    for portable_script <- [verifier, rehearsal, package_verifier, aggregate] do
      refute portable_script =~ ~r/(^|[;&|]\s*|\s)rg\s/m
    end

    assert guide =~ "2026-09-08"
    assert guide =~ "24 hours"
    assert guide =~ "one\n  hour"
    assert guide =~ "Revert removes"
    assert guide =~ "A patch preserves"
    assert guide =~ "Retirement is the"
    assert guide =~ "explicit confirmation for the exact version"
    assert guide =~ "mix hex.publish --revert \"$VERSION\""
    assert guide =~ "mix hex.user key revoke KEY_NAME"
    assert guide =~ "GitHub Security Advisory"
    assert guide =~ "gh release edit \"$TAG\""
    assert guide =~ "never contacts Hex or GitHub"

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/release/verify_candidate_evidence.sh"],
               stderr_to_stdout: true
             )

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/release/rehearse_recovery.sh"],
               stderr_to_stdout: true
             )

    evidence_root =
      Path.join(System.tmp_dir!(), "simd-json-recovery-#{System.unique_integer([:positive])}")

    assert {output, 0} =
             System.cmd("bash", ["scripts/release/rehearse_recovery.sh"],
               env: [{"SIMD_JSON_RECOVERY_EVIDENCE_DIR", evidence_root}],
               stderr_to_stdout: true
             )

    assert output =~ "Recovery rehearsal passed without mutating Hex or GitHub"
    evidence = File.read!(Path.join(evidence_root, "rehearsal.env"))

    for scenario <- [
          "missing_docs",
          "broken_native_compile",
          "checksum_mismatch",
          "leaked_secret"
        ] do
      assert evidence =~ "#{scenario}=detected"
    end

    assert evidence =~ "external_mutation=none"
    File.rm_rf!(evidence_root)
  end

  # covers: simd_json.release.recovery_readiness
  test "closes every recovery task and Phase 4" do
    phase = File.read!(@phase)
    [_, section] = String.split(phase, "## 4.4 Section", parts: 2)

    refute section =~ "- [ ]"
    assert section =~ "- [x] 4.4 Section"
    assert phase =~ "- [x] 4 Phase"
  end
end
