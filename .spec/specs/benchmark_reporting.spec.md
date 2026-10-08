# Benchmark Reporting

Current-truth contract for the repository's reproducible performance evidence. The
benchmark families retain independent measurement logic while one command refreshes a
canonical, documented report set.

Published benchmark reports are user-facing HexDocs extras; internal planning,
acceptance, and release-process records are not part of that navigation or archive.

The README summarizes the checked-in reports at the point of product choice:
it confines the measured 7.59×–8.05× speedup to sparse wide-document
projection, notes Jason's eager-decode advantage, and presents streaming as an
early-delivery and memory-peak tradeoff rather than a universal throughput win.

The first stable package identity is `1.0.0`, so published benchmark source
links bind to `v1.0.0` without changing any workload, sample, or claim.

## Intent

Performance claims must remain traceable to their workload, raw samples, source revision,
and measurement scope. Human-readable summaries and machine-readable evidence are kept
together without conflating performance reports with broader release qualification logs.

```spec-meta
id: simd_json.benchmark_reporting
kind: feature
status: active
summary: Four reproducible benchmark families publish paired Markdown and JSON reports under one documented repository directory.
surface:
  - mix.exs
  - docs/benchmarks/**
  - scripts/benchmarks/*.exs
  - scripts/benchmarks/run_all_reports.sh
  - scripts/ci/validate_exdoc_links.exs
  - scripts/ci/verify_benchmark_reports.sh
  - scripts/ci/verify_package_documentation.sh
  - test/release/package_documentation_contract_test.exs
```

## Requirements

```spec-requirements
- id: simd_json.benchmark_reporting.canonical_directory
  statement: Reproducible performance reports shall be stored under docs/benchmarks/reports and indexed by docs/benchmarks/README.md.
  priority: must
  stability: evolving

- id: simd_json.benchmark_reporting.complete_refresh
  statement: One repository command shall run sparse projection, stream ETL, eager decode, and wide projection in separate Erlang VMs and refresh every report pair.
  priority: must
  stability: evolving

- id: simd_json.benchmark_reporting.paired_evidence
  statement: Every benchmark family shall produce a human-readable Markdown summary and machine-readable JSON measurements that identify the same source revision.
  priority: must
  stability: evolving

- id: simd_json.benchmark_reporting.interpretation
  statement: The README, benchmark index, and reports shall distinguish sparse projection, eager decode, and row streaming; identify timed regions, worker memory, whole-VM RSS, and performance evidence separately from release qualification; and bind every comparative claim to its measured workload rather than imply universal superiority.
  priority: must
  stability: evolving

- id: simd_json.benchmark_reporting.hexdocs_visibility
  statement: HexDocs shall render the benchmark index and every human-readable benchmark report in one Benchmarks group with valid local navigation and version-bound raw JSON links.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.benchmark_reporting.refresh
  covers:
    - simd_json.benchmark_reporting.canonical_directory
    - simd_json.benchmark_reporting.complete_refresh
    - simd_json.benchmark_reporting.paired_evidence
  given:
    - The checked-in benchmark runners, fixture policies, and frozen fixtures
  when:
    - The consolidated benchmark command runs from the repository root
  then:
    - All four benchmark families execute in isolated Erlang VMs
    - Eight non-empty reports are written beneath the canonical directory
    - Every Markdown and JSON pair records one common source revision

- id: simd_json.benchmark_reporting.review
  covers:
    - simd_json.benchmark_reporting.interpretation
    - simd_json.benchmark_reporting.hexdocs_visibility
  given:
    - A reader reviewing performance results before release
  when:
    - The benchmark index and linked reports are inspected
  then:
    - Each comparison identifies its input shape and equivalent work
    - Host-contextual RSS and worker-process memory are not presented as interchangeable
    - File-backed qualification evidence is not presented as a binary stream benchmark
    - HexDocs navigation exposes every Markdown report and links raw JSON to the matching release source
```

## Verification

```spec-verification
- kind: command
  target: bash scripts/ci/verify_benchmark_reports.sh
  execute: true
  covers:
    - simd_json.benchmark_reporting.canonical_directory
    - simd_json.benchmark_reporting.paired_evidence
    - simd_json.benchmark_reporting.interpretation
    - simd_json.benchmark_reporting.refresh
    - simd_json.benchmark_reporting.review

- kind: command
  target: bash -n scripts/benchmarks/run_all_reports.sh
  execute: true
  covers:
    - simd_json.benchmark_reporting.complete_refresh

- kind: command
  target: MIX_ENV=test mix test test/release/package_documentation_contract_test.exs
  execute: true
  covers:
    - simd_json.benchmark_reporting.hexdocs_visibility
    - simd_json.benchmark_reporting.review
```
