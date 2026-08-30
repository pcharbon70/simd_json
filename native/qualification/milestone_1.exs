# This record binds Milestone 1 qualification to every ABI-, runtime-, test-,
# and evidence-relevant input. It is intentionally outside the fingerprint so
# the expected digest can be updated after (and only after) the matrix passes.
# covers: simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.dependency_upgrade_gate
[
  schema_version: 1,
  qualified_on: ~D[2026-08-30],
  input_sha256: "b888fd79bda5b081acc639ded3dc59f9596a3d4cf2bd186a4cecea7bdcda7943",
  randomized_seed: 260_829_001,
  supported_targets: [
    [
      triple: "x86_64-linux-gnu",
      operating_system: "Ubuntu 24.04 LTS",
      architecture: "x86_64",
      runtime: "OTP 27.3 / Elixir 1.18.4",
      expected_simdjson_implementations: ["haswell", "westmere", "fallback"]
    ]
  ],
  evidence_commands: [
    "mix simd_json.verify_vendor",
    "mix simd_json.verify_qualification",
    "mix hex.build --unpack",
    "mix compile --force",
    "mix test test/native",
    "bash scripts/ci/verify_offline_native_build.sh",
    "bash scripts/native/run_c_abi_conformance.sh ordinary",
    "bash scripts/native/run_c_abi_conformance.sh sanitizer",
    "bash scripts/native/run_zig_resource_tests.sh ordinary",
    "bash scripts/native/run_zig_resource_tests.sh sanitizer",
    "bash scripts/native/run_nif_sanitizer_tests.sh",
    "bash scripts/native/verify_release_symbols.sh",
    "bash scripts/ci/qualify_document_resource.sh",
    "bash scripts/ci/qualify_runtime.sh",
    "bash scripts/ci/qualify_document_api.sh",
    "mix simd_json.verify_traceability",
    "bash scripts/ci/qualify_milestone_1.sh"
  ]
]
