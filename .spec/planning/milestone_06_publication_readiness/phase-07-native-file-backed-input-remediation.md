# Phase 7 — Native File-Backed Input Remediation

<!-- covers: simd_json.file_input.native_path_boundary simd_json.file_input.mapped_document simd_json.file_input.open_file_contract simd_json.file_input.select_file_contract simd_json.file_input.stream_file_contract simd_json.file_input.batched_formats simd_json.file_input.no_complete_source_copy simd_json.file_input.immutable_source simd_json.file_input.bounded_stream_memory simd_json.file_input.early_halt simd_json.file_input.pool_and_cleanup -->

Back to plan: [README](./README.md)

- [ ] 7 Phase - Replace the release-blocking complete-binary-only large-document
  design with file-backed simdjson ownership, batching, and measured memory
  evidence before any release identity is frozen.

## 7.1 Section — Contract Supersession and Release Block

- [x] 7.1 Section - Put native file-backed processing at the front of the product contract.
  - [x] 7.1.1 Task - Supersede the resident-input design.
    - [x] 7.1.1.1 Subtask - Accept a durable decision authorizing simdjson-owned memory maps and batched document streams on the supported target.
    - [x] 7.1.1.2 Subtask - Replace complete-binary-only release requirements with explicit in-memory and file-backed source classes.
    - [x] 7.1.1.3 Subtask - Block publication until every section in this phase and a replacement Phase 6 candidate review pass.
  - [x] 7.1.2 Task - Freeze the honest public surface and limitations.
    - [x] 7.1.2.1 Subtask - Specify `open_file/1`, `select_file/2`, and `stream_file/2` without implicit `File.read/1` or BEAM source binaries.
    - [x] 7.1.2.2 Subtask - Retain binary APIs as explicit in-memory convenience operations.
    - [x] 7.1.2.3 Subtask - State that bounded parser memory applies to root arrays and supported document-sequence formats, while file selection avoids the source copy but may retain input-size-dependent structural indexes.

## 7.2 Section — Native Memory-Mapped Document Ownership

- [x] 7.2 Section - Let simdjson own file access and mapped source lifetime.
  - [x] 7.2.1 Task - Extend the private ABI and native resource graph.
    - [x] 7.2.1.1 Subtask - Open a path through `simdjson::padded_memory_map` entirely on a pool worker with stable file errors.
    - [x] 7.2.1.2 Subtask - Retain mapping, parser, On-Demand document, owner, generation, and cleanup state in one opaque resource.
    - [x] 7.2.1.3 Subtask - Reject embedded NULs, non-regular inputs, unsupported targets, mutation/truncation evidence, and stale generations without exposing native identity.
  - [x] 7.2.2 Task - Publish and prove `open_file/1`.
    - [x] 7.2.2.1 Subtask - Keep owner-first, one-shot, idempotent-close, cancellation, and off-scheduler cleanup semantics.
    - [x] 7.2.2.2 Subtask - Prove the operation never constructs or retains a BEAM binary containing the JSON source.
    - [x] 7.2.2.3 Subtask - Cover empty, malformed, missing, permission-denied, replaced, truncated, explicit-close, GC, and sanitizer cases.

## 7.3 Section — File-Backed Selection

- [x] 7.3 Section - Execute sparse selection directly against a simdjson memory map.
  - [x] 7.3.1 Task - Publish `select_file/2` through the bounded native pool.
    - [x] 7.3.1.1 Subtask - Reuse the exact projection grammar, prefix-sharing plan, scalar conversion, full-validation, and redacted error contract.
    - [x] 7.3.1.2 Subtask - Copy only selected result strings into fresh BEAM binaries and close the mapping deterministically after a path operation.
    - [x] 7.3.1.3 Subtask - Preserve cancellation, queue saturation, telemetry, and atomic no-partial-result behavior.
  - [x] 7.3.2 Task - Qualify source-memory behavior honestly.
    - [x] 7.3.2.1 Subtask - Prove no full BEAM or native padded source copy exists for file selection.
    - [x] 7.3.2.2 Subtask - Record peak RSS and native structural-index memory across increasing source sizes.
    - [x] 7.3.2.3 Subtask - Document that selection is zero-copy for source bytes but is not the bounded-parser-memory document-stream path.

## 7.4 Section — Batched File Streaming Through simdjson

- [x] 7.4 Section - Delegate large root-array and document-sequence streaming to simdjson batching.
  - [x] 7.4.1 Task - Add a file document-stream cursor.
    - [x] 7.4.1.1 Subtask - Use `ondemand::parser::iterate_many` over the memory map with explicit root-array, whitespace-delimited, JSON-sequence, and comma-delimited formats.
    - [x] 7.4.1.2 Subtask - Project each simdjson document through the existing compiled plan and preserve row, byte, ordering, transactional-batch, and copied-string bounds.
    - [x] 7.4.1.3 Subtask - Retain one native cursor across demand, use no NIF call per row or field, and stop native iteration immediately on early halt.
  - [x] 7.4.2 Task - Publish and prove `stream_file/2`.
    - [x] 7.4.2.1 Subtask - Require an explicit supported format and reject nested-array path claims that would require a whole-document structural scan.
    - [x] 7.4.2.2 Subtask - Release or advise away consumed mapped pages at safe batch boundaries where the supported OS contract permits it.
    - [x] 7.4.2.3 Subtask - Cover exact batches, malformed later documents, mutation/truncation, cancellation, early halt, owner death, GC, and sanitizer cleanup.

## 7.5 Section — Memory Qualification, Documentation, and Candidate Invalidation

- [ ] 7.5 Section - Demonstrate the corrected goal and rebuild release truth.
  - [ ] 7.5.1 Task - Establish executable large-file evidence.
    - [ ] 7.5.1.1 Subtask - Generate fixtures without first retaining their complete contents in the test VM.
    - [ ] 7.5.1.2 Subtask - Measure peak RSS for progressively larger root-array and document-sequence files and fail when memory scales approximately with total source size.
    - [ ] 7.5.1.3 Subtask - Verify sparse selection and early stream halt from paths, including proof that only demanded batches are advanced.
  - [ ] 7.5.2 Task - Reconcile documentation and release gates.
    - [ ] 7.5.2.1 Subtask - Rewrite README, HexDocs, support policy, changelog, and milestone records around native file-backed processing as the principal large-document capability.
    - [ ] 7.5.2.2 Subtask - Invalidate Phase 6 candidate evidence, artifact checksums, GO/NO_GO review, and qualification fingerprints changed by the native ABI and source surface.
    - [ ] 7.5.2.3 Subtask - Re-run the complete supported-target, archive, precompiled-NIF, Zig-free consumer, and SpecLed matrix before returning to Phase 8.
