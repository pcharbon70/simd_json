# Phase 5 — Public Document API and Stable Errors

Back to plan: [README](./README.md)

- [x] 5 Phase - Expose the completed native foundation through the deliberately narrow Milestone 1 Elixir contract.

  This phase adds `SimdJson.open/1`, `SimdJson.close/1`, the opaque
  `SimdJson.Document` type, and stable `SimdJson.Error` values. Elixir performs
  argument validation and redaction, the threaded native layer owns all
  input-dependent work, non-owner access is rejected before lifecycle details
  are disclosed, and owner close does not return until exactly-once native
  cleanup is complete. No projection, stream, decode, cursor, transfer, or raw
  handle API is introduced.

  Contract focus:

  - `simd_json.document_api.open_contract`
  - `simd_json.document_api.binary_only`
  - `simd_json.document_api.close_contract`
  - `simd_json.document_api.document_argument_validation`
  - `simd_json.document_api.opaque_document_type`
  - `simd_json.document_api.structured_error`
  - `simd_json.document_api.initial_error_reasons`
  - `simd_json.document_api.logical_offsets`
  - `simd_json.document_api.error_redaction`
  - `simd_json.document_api.valid_json_values`
  - `simd_json.document_api.milestone_scope`
  - `simd_json.document_resource.single_owner`
  - `simd_json.document_resource.idempotent_close`
  - `simd_json.document_api.open_and_close`
  - `simd_json.document_api.all_top_level_values`
  - `simd_json.document_api.invalid_input_errors`
  - `simd_json.document_api.non_binary_argument`
  - `simd_json.document_api.invalid_document_argument`
  - `simd_json.document_api.redacted_failure`
  - `simd_json.document_api.close_and_non_owner`
  - `simd_json.document_api.no_future_surface`
  - `simd_json.document_resource.repeated_close`
  - `simd_json.document_resource.non_owner_rejection`
  - `simd_json.document_resource.native_memory_baseline`

## 5.1 Section — Public Types and Argument Boundary

- [x] 5.1 Section - Define the minimal typed Elixir surface and reject invalid arguments before native submission.

  This section makes the API idiomatic without pretending the On-Demand document
  is a BEAM data tree. Public values reveal neither native identity nor caller
  input, and argument errors remain distinct from parser failures.

  - [x] 5.1.1 Task - Implement the opaque document module.

    The task wraps only the BEAM resource reference and presents a stable type
    and inspection form suitable for later traversal APIs.

    - [x] 5.1.1.1 Subtask - Add `SimdJson.Document` with an opaque typespec whose only runtime authority is the registered NIF resource.
    - [x] 5.1.1.2 Subtask - Prevent construction of a forged struct-shaped value from passing the native resource type check.
    - [x] 5.1.1.3 Subtask - Implement redacted `Inspect` output that reveals only the module identity and safe lifecycle-neutral text, never pointers, JSON, parser state, owner PID, or generation.
    - [x] 5.1.1.4 Subtask - Keep resource extraction private to the wrapper and native bridge; expose no raw resource accessor or serialization protocol.

  - [x] 5.1.2 Task - Implement `SimdJson.open/1` validation and typespecs.

    The task accepts exactly one binary and delegates successful admission to the
    correlated threaded operation from Phase 4.

    - [x] 5.1.2.1 Subtask - Add `open(binary()) :: {:ok, SimdJson.Document.t()} | {:error, SimdJson.Error.t()}` to the root module.
    - [x] 5.1.2.2 Subtask - Raise `ArgumentError` for iodata, atoms, maps, and every other non-binary before a request reference or native allocation is created.
    - [x] 5.1.2.3 Subtask - Pass the accepted binary to the threaded open path without making an extra untracked Elixir or native copy beyond the required owned padded copy.
    - [x] 5.1.2.4 Subtask - Return only a tagged result; never raise for malformed JSON or return a partial document on native failure.

  - [x] 5.1.3 Task - Implement `SimdJson.close/1` validation and typespecs.

    The task accepts only a genuine document resource and joins the shared
    off-scheduler cleanup operation established in Phase 4.

    - [x] 5.1.3.1 Subtask - Add `close(SimdJson.Document.t()) :: :ok | {:error, SimdJson.Error.t()}` to the root module.
    - [x] 5.1.3.2 Subtask - Raise `ArgumentError` for binaries, maps, references, forged document-shaped values, and resources of another registered type before cleanup admission.
    - [x] 5.1.3.3 Subtask - Suspend the caller while threaded cleanup runs and return `:ok` only after the resource reaches `closed` and document-owned native allocations are released.
    - [x] 5.1.3.4 Subtask - Make an owner close on an already closing resource join the same completion and an owner close on an already closed resource return `:ok` immediately.

## 5.2 Section — Stable Error Translation and Redaction

- [x] 5.2 Section - Translate native statuses once into a closed, documented Elixir error vocabulary.

  This section prevents callers from depending on simdjson enum values, compiler
  exception text, or mutable prose while preserving safe diagnostics and logical
  byte locations.

  - [x] 5.2.1 Task - Define `SimdJson.Error` and the initial reason set.

    The task creates a stable data contract with typed fields and a single
    internal translation point.

    - [x] 5.2.1.1 Subtask - Add fields for `reason`, optional `byte_offset`, optional `native_code`, and explanatory `message` with corresponding typespecs.
    - [x] 5.2.1.2 Subtask - Define initial reasons `:invalid_json`, `:invalid_utf8`, `:unexpected_eof`, `:out_of_memory`, `:closed`, `:not_owner`, and `:native_failure`.
    - [x] 5.2.1.3 Subtask - Map every stable C/Zig status in one private translator and route unknown codes to `:native_failure` while retaining their numeric value only as safe diagnostics.
    - [x] 5.2.1.4 Subtask - Treat message text as explanatory only and document `reason` as the caller's machine-readable branch key.

  - [x] 5.2.2 Task - Preserve logical offsets and redact sensitive data.

    The task allows useful failure location without exposing padding, native
    addresses, caller content, or raw exception messages.

    - [x] 5.2.2.1 Subtask - Convert the native unavailable-offset sentinel to `nil` and validate every present offset against the logical JSON length.
    - [x] 5.2.2.2 Subtask - Ensure no byte offset can point into native padding or be computed from allocation capacity.
    - [x] 5.2.2.3 Subtask - Construct safe messages from controlled templates rather than native exception or simdjson text that could include sensitive context.
    - [x] 5.2.2.4 Subtask - Implement redacted `Inspect` behavior for errors and verify default Logger metadata contains no JSON fragment, pointer, owner PID, or C++ exception text.

## 5.3 Section — Ownership, Lifecycle, and Scope Enforcement

- [x] 5.3 Section - Make single-process authority and deterministic cleanup observable through the public API.

  This section applies the native lifecycle rules at every document boundary and
  fixes the Milestone 1 public surface so later work cannot leak in accidentally.

  - [x] 5.3.1 Task - Enforce owner-first document access.

    The task ensures possession of a resource term does not grant authority or
    disclose whether another process has already closed the document.

    - [x] 5.3.1.1 Subtask - Capture the successful opener's PID as immutable owner metadata before publishing the document.
    - [x] 5.3.1.2 Subtask - Check caller ownership before lifecycle state for every document operation, including close.
    - [x] 5.3.1.3 Subtask - Return `{:error, %SimdJson.Error{reason: :not_owner}}` to another process without changing lifecycle, generation, admission, or cleanup state.
    - [x] 5.3.1.4 Subtask - Return the stable `:closed` reason for any future owner document operation after close while retaining idempotent `close/1` as the explicit exception.

  - [x] 5.3.2 Task - Lock the Milestone 1 public surface.

    The task prevents foundation work from quietly implementing functionality
    assigned to later milestones.

    - [x] 5.3.2.1 Subtask - Document only `open/1`, `close/1`, `SimdJson.Document`, and `SimdJson.Error` as the Milestone 1 public contract.
    - [x] 5.3.2.2 Subtask - Keep NIF bridge, native diagnostics, counters, failure injection, and resource helpers private or test-only.
    - [x] 5.3.2.3 Subtask - Add an exported-function and typespec allowlist proving eager decode, projection, stream, cursor, ownership transfer, and raw native-handle operations are absent.
    - [x] 5.3.2.4 Subtask - State in module and milestone documentation that production admission control arrives with the bounded worker pool in Milestone 4.

## 5.4 Section — Phase 5 Integration Tests

- [x] 5.4 Section - Prove the public contract across JSON corpora, ownership boundaries, lifecycle races, and redaction.

  This section closes the user-visible vertical slice before Phase 6 performs
  release qualification and removes bootstrap exceptions.

  - [x] 5.4.1 Task - Run public open, validation, and error-corpus tests.

    The task executes `open_and_close`, `all_top_level_values`,
    `invalid_input_errors`, `non_binary_argument`, `invalid_document_argument`,
    and `redacted_failure` through the real threaded native stack.

    - [x] 5.4.1.1 Subtask - Open valid object, array, string, integer, floating-point, true, false, and null documents with leading and trailing legal whitespace.
    - [x] 5.4.1.2 Subtask - Test empty, whitespace-only, beginning/middle/end malformed, truncated, invalid UTF-8, and unescaped embedded-null binaries with stable reasons and logical offsets.
    - [x] 5.4.1.3 Subtask - Inject allocation and unknown native failures and assert `:out_of_memory` and `:native_failure` mappings without a partial document.
    - [x] 5.4.1.4 Subtask - Test every invalid `open/1` and `close/1` argument shape and prove no threaded submission, allocation, or lifecycle change occurs.
    - [x] 5.4.1.5 Subtask - Put a unique secret in malformed input and injected exception text, then assert errors, inspection, logs, and diagnostics never contain it.

  - [x] 5.4.2 Task - Run ownership, lifetime, and deterministic-close tests.

    The task executes `close_and_non_owner`, `non_owner_rejection`,
    `input_lifetime`, `repeated_close`, and `native_memory_baseline` through
    public terms and multiple BEAM processes.

    - [x] 5.4.2.1 Subtask - Drop every original binary reference after `open/1`, force garbage collection, and prove the document remains valid through a native conformance probe until close.
    - [x] 5.4.2.2 Subtask - Send an open and a closed document term to another process and assert owner-first `:not_owner` results with no state or generation change.
    - [x] 5.4.2.3 Subtask - Race repeated owner close calls and later resource destruction; assert every close returns `:ok` only after one cleanup completes and every native object is freed once.
    - [x] 5.4.2.4 Subtask - Open independent documents concurrently from different owners and prove their input, lifecycle, reference, error, and cleanup state never cross.
    - [x] 5.4.2.5 Subtask - Release batches by explicit close and GC, await cleanup quiescence, and assert all bounded native counters return to baseline.

  - [x] 5.4.3 Task - Run API-surface and documentation integration tests.

    The task executes `no_future_surface` and confirms examples and types agree
    with actual runtime behavior.

    - [x] 5.4.3.1 Subtask - Enumerate documented modules, exported functions, typespecs, and protocols against the Milestone 1 allowlist.
    - [x] 5.4.3.2 Subtask - Add doctests for successful open/close, malformed input, invalid arguments, redacted inspection, repeated close, and non-owner rejection.
    - [x] 5.4.3.3 Subtask - Run focused API/resource/error tests, native baseline checks, `mix test`, `mix format --check-formatted`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 5 complete.
