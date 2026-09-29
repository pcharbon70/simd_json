# Native File-Backed Input

Milestone 6 Phase 7 corrects the release-blocking resident-binary design by
making simdjson own file mapping, On-Demand traversal, and batched document
streams. This subject remains planned until its native, public, memory, and
packaged-consumer evidence executes successfully.

```spec-meta
id: simd_json.file_input
kind: feature
status: planned
verification_minimum_strength: executed
summary: File-backed operations delegate source ownership and batched traversal to simdjson without a complete BEAM or padded native source copy.
surface:
  - lib/simd_json.ex
  - lib/simd_json/**/*file*
  - native/include/**
  - native/src/**
  - native/zig/**
  - test/**/*file*
  - test/**/*memory*
  - scripts/**/*file*
decisions:
  - simd_json.native_file_backed_input_and_batched_streaming
  - simd_json.off_scheduler_native_execution
  - simd_json.owned_native_jobs_and_bounded_fifo
  - simd_json.monitored_delivery_and_resource_serialization
bootstrap:
  reason: Phase 7.1 freezes the corrected contract; Sections 7.2 through 7.5 must implement and qualify the complete native and public path before activation.
  requirements:
    - simd_json.file_input.native_path_boundary
    - simd_json.file_input.mapped_document
    - simd_json.file_input.open_file_contract
    - simd_json.file_input.select_file_contract
    - simd_json.file_input.stream_file_contract
    - simd_json.file_input.batched_formats
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.immutable_source
    - simd_json.file_input.bounded_stream_memory
    - simd_json.file_input.early_halt
    - simd_json.file_input.pool_and_cleanup
```

## Requirements

```spec-requirements
- id: simd_json.file_input.native_path_boundary
  statement: File-backed APIs shall pass only a validated filesystem path through the BEAM boundary and shall never read the complete JSON file into an Elixir binary.
  priority: must
  stability: evolving

- id: simd_json.file_input.mapped_document
  statement: On the supported target, C++ shall open file sources through simdjson::padded_memory_map and retain the mapping with every parser, document, stream, and borrowed native view that depends on it.
  priority: must
  stability: evolving

- id: simd_json.file_input.open_file_contract
  statement: SimdJson.open_file/1 shall open one immutable regular-file JSON source as an opaque owner-bound SimdJson.Document without constructing a complete BEAM binary or padded native source copy.
  priority: must
  stability: evolving

- id: simd_json.file_input.select_file_contract
  statement: SimdJson.select_file/2 shall apply the existing validated projection grammar directly to a simdjson memory map and return only complete copied scalar results or one redacted structured error.
  priority: must
  stability: evolving

- id: simd_json.file_input.stream_file_contract
  statement: SimdJson.stream_file/2 shall return a lazy owner-bound opaque Enumerable whose first reduction opens one native memory map and simdjson document stream and whose terminal reduction or halt deterministically closes them.
  priority: must
  stability: evolving

- id: simd_json.file_input.batched_formats
  statement: File streaming shall require one explicit format from json_array, ndjson, json_sequence, or comma_delimited, map it to simdjson iterate_many, and reject nested target paths or implicit whole-document scans.
  priority: must
  stability: evolving

- id: simd_json.file_input.no_complete_source_copy
  statement: File-backed open, select, and stream operations shall create neither a complete source BEAM binary nor a complete padded native source allocation; result strings and bounded descriptors may be copied.
  priority: must
  stability: stable

- id: simd_json.file_input.immutable_source
  statement: A file source shall be documented and checked as immutable for its complete native lifetime; observed identity, size, or metadata changes shall fail closed without claiming detection of every concurrent external mutation.
  priority: must
  stability: evolving

- id: simd_json.file_input.bounded_stream_memory
  statement: File-stream qualification shall prove peak process memory remains inside an approved fixed-plus-parser-batch-plus-result-batch envelope across progressively larger sources rather than scaling approximately with total file size.
  priority: must
  stability: evolving

- id: simd_json.file_input.early_halt
  statement: Early file-stream halt shall stop simdjson document iteration without scanning or materializing undemanded documents and shall release the cursor, parser, mapping, plan, and operation graph exactly once.
  priority: must
  stability: stable

- id: simd_json.file_input.pool_and_cleanup
  statement: File open, selection, stream setup, batch advancement, cancellation, and potentially unbounded teardown shall use the bounded native pool and accepted owner, generation, serialization, telemetry, redaction, and off-scheduler cleanup contracts.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: simd_json.file_input.no_resident_source_binary
  covers:
    - simd_json.file_input.native_path_boundary
    - simd_json.file_input.mapped_document
    - simd_json.file_input.no_complete_source_copy
  given:
    - A large immutable JSON file generated incrementally
  when:
    - It is opened, selected, and streamed only by path
  then:
    - No complete source binary exists in the test VM
    - Native accounting reports a mapping and no padded source copy
    - Copied results remain valid after every native owner is closed

- id: simd_json.file_input.file_api_contracts
  covers:
    - simd_json.file_input.open_file_contract
    - simd_json.file_input.select_file_contract
    - simd_json.file_input.stream_file_contract
    - simd_json.file_input.immutable_source
  given:
    - Valid, malformed, empty, missing, unreadable, non-regular, replaced, and truncated paths
  when:
    - Each file-backed public operation runs and cleanup completes
  then:
    - Valid immutable files preserve their operation's existing result semantics
    - Invalid or observably changed files return stable redacted failures
    - No native identity, path content, or JSON source enters errors or telemetry

- id: simd_json.file_input.batched_memory_scaling
  covers:
    - simd_json.file_input.stream_file_contract
    - simd_json.file_input.batched_formats
    - simd_json.file_input.bounded_stream_memory
    - simd_json.file_input.early_halt
    - simd_json.file_input.pool_and_cleanup
  given:
    - Progressively larger top-level arrays and supported document sequences
    - Fixed row and encoded-byte limits
  when:
    - Full reductions and one-batch early halts run under RSS, boundary, and native-allocation instrumentation
  then:
    - Rows retain source order and exact projection semantics
    - One compiled plan and one native boundary per batch are used
    - Peak memory stays within the approved envelope instead of following total source size
    - Early halt advances only demanded batches and every native count returns to baseline
```

## Required Closure Evidence

Replace the bootstrap exception with executed C/C++ and Zig ABI conformance,
ordinary and sanitizer lifecycle tests, public API tests, progressively scaled
RSS qualification, early-halt boundary accounting, package inventory, release
symbol, precompiled artifact, and Zig-free fresh-consumer evidence.

## Verification

```spec-verification
- kind: source_file
  target: .spec/planning/milestone_06_publication_readiness/phase-07-native-file-backed-input-remediation.md
  covers:
    - simd_json.file_input.native_path_boundary
    - simd_json.file_input.mapped_document
    - simd_json.file_input.open_file_contract
    - simd_json.file_input.select_file_contract
    - simd_json.file_input.stream_file_contract
    - simd_json.file_input.batched_formats
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.immutable_source
    - simd_json.file_input.bounded_stream_memory
    - simd_json.file_input.early_halt
    - simd_json.file_input.pool_and_cleanup

- kind: test_file
  target: test/simd_json/file_input_test.exs
  covers:
    - simd_json.file_input.native_path_boundary
    - simd_json.file_input.mapped_document
    - simd_json.file_input.open_file_contract
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.immutable_source
    - simd_json.file_input.pool_and_cleanup

- kind: test_file
  target: test/qualification/file_selection_memory_qualification_test.exs
  covers:
    - simd_json.file_input.native_path_boundary
    - simd_json.file_input.select_file_contract
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.pool_and_cleanup

- kind: test_file
  target: test/simd_json/public_surface_test.exs
  covers:
    - simd_json.file_input.open_file_contract
    - simd_json.file_input.select_file_contract

- kind: command
  target: bash scripts/native/run_c_abi_conformance.sh ordinary
  covers:
    - simd_json.file_input.mapped_document
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.immutable_source

- kind: command
  target: bash scripts/native/run_c_abi_conformance.sh sanitizer
  covers:
    - simd_json.file_input.mapped_document
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.immutable_source

- kind: command
  target: bash scripts/native/run_zig_resource_tests.sh ordinary
  covers:
    - simd_json.file_input.mapped_document
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.pool_and_cleanup

- kind: command
  target: bash scripts/native/run_zig_resource_tests.sh sanitizer
  covers:
    - simd_json.file_input.mapped_document
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.pool_and_cleanup

- kind: command
  target: bash scripts/native/run_nif_sanitizer_tests.sh
  covers:
    - simd_json.file_input.native_path_boundary
    - simd_json.file_input.mapped_document
    - simd_json.file_input.open_file_contract
    - simd_json.file_input.no_complete_source_copy
    - simd_json.file_input.immutable_source
    - simd_json.file_input.pool_and_cleanup
```
