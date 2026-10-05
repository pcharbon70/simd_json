%{
  schema_version: 1,
  frozen_on: ~D[2026-10-03],
  jason_version: "1.4.5",
  fixture_manifest: "bench/wide_projection_fixture/manifest.exs",
  selection_widths: [1, 2, 4, 8, 16],
  selected_row_index: 499_999,
  workflows: [:simd_json_select, :jason_decode_and_lookup],
  warmup_samples_per_workflow: 1,
  measured_samples_per_workflow: 3,
  isolation: :fresh_process_per_sample,
  order: :alternating_by_sample,
  memory_sampling_interval_milliseconds: 1,
  percentile_method: :nearest_rank,
  notes: [
    "The fixture has one million rows and sixteen numeric fields per row.",
    "Every width selects fields from the same middle row so document size and traversal position remain fixed.",
    "The timed region includes select or full Jason decode, identical lookups, result construction, and retention.",
    "Fixture decompression and digest verification occur outside the timed region.",
    "Latency and memory are host-specific measured context, not universal superiority claims."
  ]
}
