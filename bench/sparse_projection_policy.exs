%{
  schema_version: 1,
  frozen_on: ~D[2026-08-31],
  fixture_manifest: "bench/fixtures/manifest.json",
  fixture_generator_seed: 260_831_006,
  workflows: [:simd_json_select, :jason_decode_and_lookup],
  isolation: :fresh_process_per_sample,
  order: :alternating_by_sample,
  warmup_samples_per_workflow_and_fixture: 3,
  measured_samples_per_workflow_and_fixture: 15,
  garbage_collection: :fullsweep_before_each_sample,
  memory_sampling_interval_milliseconds: 1,
  percentile_method: :nearest_rank,
  retained_result: true,
  required_fixtures: [:small, :medium, :large],
  allocation_acceptance: %{
    fixtures: [:medium, :large],
    metric: :median_estimated_beam_allocated_bytes,
    maximum_simd_json_fraction_of_jason: 0.30,
    required_reduction_percent: 70.0
  },
  latency_and_throughput: :context_only,
  notes: [
    "The timed region includes projection validation, scheduling, source copying, plan compilation, full traversal, term construction, delivery, and result retention.",
    "The Jason region includes full decode, equivalent path lookups, result-map construction, and retention.",
    "Estimated allocated words equal garbage-collection reclaimed words plus the retained live-word delta in the isolated caller; process/binary peaks and native gauges are recorded separately.",
    "The threshold is a sparse BEAM-allocation claim, not a universal latency or throughput claim."
  ]
}
