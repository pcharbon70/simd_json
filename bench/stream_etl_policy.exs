%{
  schema_version: 1,
  frozen_on: ~D[2026-09-02],
  seed: 260_902_003,
  jason_version: "1.4.5",
  fixture_manifest: "bench/stream_fixtures/manifest.exs",
  workflows: [:simd_json_stream_reduce, :jason_decode_lookup_reduce],
  batch_sizes: [128, 1_000],
  max_batch_bytes: 8_388_608,
  warmup_samples: 1,
  measured_samples: %{small: 3, medium: 3, million: 1},
  percentile_method: :nearest_rank,
  isolation: :fresh_process_per_sample,
  memory_sampling_interval_milliseconds: 1,
  acceptance: %{
    million_stream_peak_fraction_of_jason: 0.60,
    million_stream_process_peak_bytes: 134_217_728
  },
  notes: [
    "Both workflows perform the same id/value lookup and integer sum reduction.",
    "The timed region includes validation, setup/decode, lookup, reduction, and cleanup.",
    "The million-row stream must remain within a fixed 128 MiB process-peak envelope and use at most 60 percent of Jason's process peak.",
    "Latency and throughput are measured context, not a universal superiority claim.",
    "Compressed fixtures are committed; decompression is outside the timed region."
  ]
}
