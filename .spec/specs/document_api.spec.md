# Document API and Errors

Current-truth contract for the deliberately narrow Milestone 1 Elixir API and its stable structured error boundary.

## Intent

This subject gives callers one safe way to open and deterministically close an opaque native document while preventing native codes, pointers, JSON content, or future cursor operations from leaking into the initial public contract.

Phases 1 through 3 contribute the reproducible NIF, private C parser ABI, and
an internal opaque resource fixture beneath this subject's broad source
surface. Phase 4 adds a private threaded-operation adapter and admission smoke
proof, but neither is a `SimdJson.Document` public type or document API. There
is still no `open/1`, `close/1`, structured error, or public document API, so
the bootstrap exception remains in force.

```spec-meta
id: simd_json.document_api
kind: api
status: planned
summary: Milestone 1 exposes binary open and idempotent close through opaque documents and stable structured errors.
surface:
  - lib/simd_json.ex
  - lib/simd_json/**/*.ex
  - test/**/*document*
  - test/**/*error*
  - docs/milestones/01-native-foundation.md
decisions:
  - simd_json.native_stack_and_c_abi
  - simd_json.document_resource_and_buffer_ownership
  - simd_json.off_scheduler_native_execution
```

## Requirements

```spec-requirements
- id: simd_json.document_api.open_contract
  statement: SimdJson.open/1 shall accept one JSON binary and return either {:ok, SimdJson.Document.t()} or {:error, SimdJson.Error.t()}.
  priority: must
  stability: evolving

- id: simd_json.document_api.binary_only
  statement: Milestone 1 shall accept binaries only, and non-binary caller arguments shall raise ArgumentError before native work is submitted.
  priority: must
  stability: stable

- id: simd_json.document_api.close_contract
  statement: SimdJson.close/1 shall return :ok only after the owner's exactly-once native cleanup has completed and shall return a structured not_owner error when another process supplies a valid document.
  priority: must
  stability: evolving

- id: simd_json.document_api.document_argument_validation
  statement: SimdJson.close/1 shall raise ArgumentError for values that are not SimdJson.Document resources before native cleanup work is submitted.
  priority: must
  stability: stable

- id: simd_json.document_api.opaque_document_type
  statement: SimdJson.Document shall expose an opaque type and a redacted inspection form that reveals no native pointer, input contents, parser state, or generation.
  priority: must
  stability: stable

- id: simd_json.document_api.structured_error
  statement: SimdJson.Error shall provide a stable reason, optional logical byte offset, optional native diagnostic code, and explanatory message without making message text machine-readable.
  priority: must
  stability: evolving

- id: simd_json.document_api.initial_error_reasons
  statement: The initial stable reasons shall include invalid_json, invalid_utf8, unexpected_eof, out_of_memory, closed, not_owner, and native_failure.
  priority: must
  stability: stable

- id: simd_json.document_api.logical_offsets
  statement: Reported byte offsets shall refer to the logical JSON input and shall never count native padding bytes.
  priority: must
  stability: stable

- id: simd_json.document_api.error_redaction
  statement: Public errors, inspection, logs, and diagnostics shall not include raw JSON, selected source substrings, native addresses, or C++ exception text by default.
  priority: must
  stability: stable

- id: simd_json.document_api.valid_json_values
  statement: SimdJson.open/1 shall admit every valid top-level JSON value, including objects, arrays, strings, numbers, booleans, and null.
  priority: must
  stability: stable

- id: simd_json.document_api.milestone_scope
  statement: Milestone 1 shall expose no eager decode, projection, streaming, ownership transfer, raw cursor, or raw native-handle API.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: simd_json.document_api.open_and_close
  covers:
    - simd_json.document_api.open_contract
    - simd_json.document_api.close_contract
    - simd_json.document_api.opaque_document_type
  given:
    - A valid JSON object binary
  when:
    - Its owner opens and closes the document
  then:
    - Open returns an opaque SimdJson.Document
    - Inspection reveals no native or input details
    - Close returns :ok

- id: simd_json.document_api.all_top_level_values
  covers:
    - simd_json.document_api.open_contract
    - simd_json.document_api.valid_json_values
  given:
    - Valid object, array, string, integer, float, true, false, and null documents
  when:
    - Each binary is opened
  then:
    - Each call returns an opaque document

- id: simd_json.document_api.invalid_input_errors
  covers:
    - simd_json.document_api.structured_error
    - simd_json.document_api.initial_error_reasons
    - simd_json.document_api.logical_offsets
  given:
    - Empty and whitespace-only binaries
    - JSON malformed at the beginning, middle, or end
    - Truncated, invalid UTF-8, and embedded-null JSON binaries
  when:
    - Each input is opened
  then:
    - Each call returns the appropriate stable reason
    - Any available byte offset is relative to the logical input
    - No partially usable document is returned

- id: simd_json.document_api.non_binary_argument
  covers:
    - simd_json.document_api.binary_only
  given:
    - An iolist, atom, map, or other non-binary argument
  when:
    - SimdJson.open/1 is called
  then:
    - ArgumentError is raised before native work is submitted

- id: simd_json.document_api.invalid_document_argument
  covers:
    - simd_json.document_api.document_argument_validation
  given:
    - A binary, map, reference, and forged SimdJson.Document-shaped value
  when:
    - SimdJson.close/1 is called with each value
  then:
    - ArgumentError is raised before cleanup work is submitted
    - No native document lifecycle is changed

- id: simd_json.document_api.redacted_failure
  covers:
    - simd_json.document_api.error_redaction
  given:
    - Malformed JSON containing a unique sensitive marker and an injected native exception message
  when:
    - The error is returned, inspected, and logged through default diagnostics
  then:
    - The sensitive input marker is absent
    - The native address and raw C++ exception text are absent
    - Stable reason and safe location metadata remain available

- id: simd_json.document_api.close_and_non_owner
  covers:
    - simd_json.document_api.close_contract
    - simd_json.document_api.initial_error_reasons
  given:
    - A document owned by process A and shared with process B
  when:
    - Process B attempts to close it while it is open
    - Process A closes it twice
  then:
    - The non-owner close returns not_owner without changing lifecycle state
    - Both owner closes return :ok only after native cleanup is complete

- id: simd_json.document_api.no_future_surface
  covers:
    - simd_json.document_api.milestone_scope
  given:
    - The completed Milestone 1 public modules and documentation
  when:
    - Their exported functions and types are enumerated
  then:
    - Only the document open, close, type, and structured error surface is present
    - Decode, projection, streaming, cursor, transfer, and native-handle operations are absent
```

## Verification

```spec-verification
- kind: test_file
  target: test/native/document_resource_policy_test.exs
  covers:
    - simd_json.document_api.milestone_scope
```

## Required Closure Evidence

Before activation, replace the bootstrap exception with executed public API, typespec, doctest, error mapping, redaction, ownership, close, valid-value corpus, malformed-input corpus, UTF-8, and API-surface tests. The native and scheduler subjects must also be active before this API can be presented as Milestone 1 complete.

## Exceptions

```spec-exceptions
- id: simd_json.document_api.milestone_01_bootstrap
  covers:
    - simd_json.document_api.open_contract
    - simd_json.document_api.binary_only
    - simd_json.document_api.close_contract
    - simd_json.document_api.document_argument_validation
    - simd_json.document_api.opaque_document_type
    - simd_json.document_api.structured_error
    - simd_json.document_api.initial_error_reasons
    - simd_json.document_api.logical_offsets
    - simd_json.document_api.error_redaction
    - simd_json.document_api.valid_json_values
    - simd_json.document_api.milestone_scope
    - simd_json.document_api.open_and_close
    - simd_json.document_api.all_top_level_values
    - simd_json.document_api.invalid_input_errors
    - simd_json.document_api.non_binary_argument
    - simd_json.document_api.invalid_document_argument
    - simd_json.document_api.redacted_failure
    - simd_json.document_api.close_and_non_owner
    - simd_json.document_api.no_future_surface
  reason: The Milestone 1 public document API is not implemented; remove this exception and replace it with executed API, corpus, redaction, ownership, and scope-verification tests before activation.
```
