# Benchmark reports

This directory is the canonical home for reproducible SimdJson performance reports. Run
all benchmark families from the repository root with:

```console
bash scripts/benchmarks/run_all_reports.sh
```

The command runs each family in a separate Erlang VM and overwrites the corresponding
Markdown and JSON files under `docs/benchmarks/reports`. Set
`SIMD_JSON_BENCHMARK_REPORT_DIR` to write an untracked comparison run elsewhere.

## Report index

| Family | Workload | Human-readable report | Raw measurements |
| --- | --- | --- | --- |
| Sparse projection | Select five nested values from small, medium, and large documents; compare `SimdJson.select/2` with Jason full decode and lookup | [Markdown](reports/sparse-projection/projection-benchmark.md) | [JSON](https://github.com/pcharbon70/simd_json/blob/v1.0.0/docs/benchmarks/reports/sparse-projection/projection-benchmark.json) |
| Stream ETL | Project and reduce `id` and `value` from every narrow row, including the one-million-row fixture; compare bounded batches with Jason full decode | [Markdown](reports/stream-etl/stream-etl.md) | [JSON](https://github.com/pcharbon70/simd_json/blob/v1.0.0/docs/benchmarks/reports/stream-etl/stream-etl.json) |
| Eager decode | Fully materialize seven representative valid and malformed documents; compare `SimdJson.decode/1` with `Jason.decode/1` | [Markdown](reports/eager-decode/decode-benchmark.md) | [JSON](https://github.com/pcharbon70/simd_json/blob/v1.0.0/docs/benchmarks/reports/eager-decode/decode-benchmark.json) |
| Wide projection | Select 1, 2, 4, 8, and 16 fields from the same row in a one-million-row, 16-field document; compare `SimdJson.select/2` with Jason full decode and lookup | [Markdown](reports/wide-projection/wide-projection.md) | [JSON](https://github.com/pcharbon70/simd_json/blob/v1.0.0/docs/benchmarks/reports/wide-projection/wide-projection.json) |

## How to interpret the results

The reports capture their source Git revision, fixture identity, pinned Jason version,
warmups, measured samples, and workflow-specific statistics. The JSON files preserve raw
samples; the Markdown files emphasize median (`p50`) results and document each metric's
scope.

These are host-specific observations, not universal product guarantees. Whole-VM RSS
includes BEAM heaps, native allocations, loaded code, shared libraries, mapped resident
pages, and allocator retention. Compare only like-for-like metrics from the same run.
Worker-process memory and whole-VM RSS answer different questions and must not be compared
as though they share a scope.

Compressed million-row fixtures are read and decompressed before timed samples in the
stream ETL and wide-projection runners. The stream ETL benchmark exercises the binary
`stream/2` API; bounded file-backed behavior is enforced separately by the release
qualification tests for `stream_file/2`.

## Scope

The report set includes benchmark families with checked-in runners and reproducible input
policies. Historical one-off measurements are intentionally excluded. In particular, the
older million-row select matrix used a narrow three-field row shape and distributed scalar
paths; the wide-projection family supersedes it with a constant 16-field row shape and
controlled selection widths.

Correctness, scheduler responsiveness, lifecycle, file-backed memory bounds, packaging,
and precompiled-native delivery remain release qualification concerns. Their evidence is
generated under `_build/qualification` and is not duplicated here as performance data.
