# This historically named record binds cumulative Milestone 1, Milestone 2,
# and the implemented Milestone 3 and Milestone 4 phases
# qualification to every ABI-, runtime-, test-, benchmark-, and
# evidence-relevant input. It is intentionally outside the fingerprint so the
# expected digest can be updated after (and only after) the matrix passes.
# covers: simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.dependency_upgrade_gate
[
  schema_version: 1,
  qualified_on: ~D[2026-09-04],
  input_sha256: "b6c4dee4d62320cbe239f8e3b1cfb8989b5daa7e3d39f709da9d1f206a0af2cc",
  randomized_seed: 260_831_006,
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
    "mix test test/native/pool_queue_test.exs",
    "mix test test/native/pool_cancellation_test.exs test/native/pool_delivery_test.exs test/native/pool_resource_serialization_test.exs",
    "mix test test/native/pool_public_operations_test.exs test/native/pool_public_stream_test.exs test/native/pool_telemetry_test.exs",
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
    "bash scripts/ci/qualify_projection_runtime.sh",
    "bash scripts/ci/qualify_projection_benchmark.sh",
    "bash scripts/ci/qualify_projection_execution.sh",
    "mix simd_json.verify_traceability",
    "bash scripts/ci/qualify_milestone_1.sh",
    "bash scripts/ci/qualify_milestone_2.sh",
    "bash scripts/ci/qualify_native_release.sh",
    "bash scripts/ci/qualify_stream_runtime.sh",
    "bash scripts/ci/qualify_stream_benchmark.sh",
    "bash scripts/ci/qualify_stream_execution.sh",
    "bash scripts/ci/qualify_milestone_3.sh"
  ]
]
