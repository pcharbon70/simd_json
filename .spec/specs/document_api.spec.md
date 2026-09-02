# Document API and Errors

Current-truth contract for the deliberately narrow Milestone 1 Elixir API and its stable structured error boundary.

## Intent

This subject gives callers one safe way to open and deterministically close an opaque native document while preventing native codes, pointers, JSON content, or future cursor operations from leaking into the initial public contract.

Phases 1 through 4 contribute the reproducible NIF, private C parser ABI,
opaque resource, and correlated threaded construction and cleanup runtime.
Phase 5 exposes binary-only `SimdJson.open/1`,
owner-safe and idempotent `SimdJson.close/1`, an opaque redacted
`SimdJson.Document`, and a closed `SimdJson.Error` vocabulary. One private
translator maps all native statuses, validates offsets against logical input
length, retains only numeric native diagnostics, and builds messages from
controlled templates. Forged values fail the registered native resource check
before cleanup admission, and a bounded native check rejects non-owners before
revealing open or closed lifecycle state. Module, README, milestone, export,
typespec, and protocol checks lock the public scope. The Phase 5 integration
matrix now exercises all valid top-level values, malformed and invalid argument
families, failure redaction, input lifetime, owner boundaries, repeated close,
concurrent owners, and explicit/GC baseline recovery. Phase 6 Section 6.1 now
repeats that public corpus against an isolated NIF whose C++ translation units
are instrumented by AddressSanitizer and UndefinedBehaviorSanitizer. Runtime
qualification now repeats owner, non-owner, idempotent-close, submission
failure, and GC behavior in a seeded bounded stress profile. Section 6.3
reconciles the public surface documentation and activates this subject against
executable API and scope qualification.

Milestone 2 Phase 1 additively reserves the projection error reasons and an
optional validated caller-path field in `SimdJson.Error`. Existing open and
close paths retain their original meanings and continue to return `path: nil`.
Default inspection omits both message and path contents and defensively bounds
forged fields, while the root public operation set remains unchanged.
Milestone 2 Phase 2 changes only the private native build: the four
parser/document signatures, their 16-byte status, document error translation,
and every `open/1`/`close/1` result remain unchanged. No projection descriptor,
plan, result slot, pointer, status, or diagnostic is reachable from the public
Elixir API or release NIF exports.
Milestone 2 Phases 3 and 4 add the private guided engine and threaded
projection integration without changing that public boundary. The test-only
projection adapter reuses the reserved error reasons and optional validated
path, while `open/1`, `close/1`, their translations, the opaque document, and
the exported root operation set remain unchanged. No projection timing,
normalized term, one-shot state, native resource identity, or test accounting
is exposed through the Milestone 1 API.
Milestone 2 Phase 5 now adds the separately governed public `select/2` root
operation and its projection types. The Milestone 1 baseline remains
`open/1`, `close/1`, the opaque document, and the shared structured error;
their argument, ownership, lifecycle, offset, redaction, and cleanup behavior
is unchanged. Current public-surface verification therefore permits only that
accepted additive operation while continuing to reject eager decode,
streaming, cursor, transfer, raw-handle, compiled-plan, JSONPath, option, and
diagnostic surfaces.
Milestone 2 Phase 6 re-runs that combined public surface from the unpacked
package and sanitizer-instrumented NIF, records formal scheduler/lifecycle and
frozen Jason evidence, and activates the three projection subjects. The
Milestone 1 open/close/error claims and verification command remain green and
no additional root operation is introduced.
Milestone 3 Phase 1 additively reserves `:batch_too_large` and optional checked
`array_index` metadata in `SimdJson.Error`. Existing open, close, and select
errors retain their reason, message, offset, code, and path behavior and now
default to `array_index: nil`; inspection renders only a bounded valid index.
The root module still exports only `open/1`, `close/1`, and `select/2`, and no
stream, Enumerable, cursor, batch, or stream type is public in this phase.
Milestone 3 Phase 2 changes only the private ABI/resource graph. The root
exports and all open/close/select error translations remain unchanged; no
cursor handle, target descriptor, batch layout, or stream state reaches Elixir.
Milestone 3 Phase 4 exercises select/stream exclusion and parent retention only
through compile-time-gated private seams. The public document representation,
root exports, errors, ownership rules, and absence of cursor/batch handles are
unchanged until Phase 5.

```spec-meta
id: simd_json.document_api
kind: api
status: active
verification_minimum_strength: executed
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
  statement: SimdJson.Error shall provide a stable reason, optional logical byte offset, optional native diagnostic code, optional validated caller projection path, and explanatory message without making message text machine-readable.
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
  statement: The Milestone 1 baseline shall remain limited to document open, close, opacity, and structured errors; separately governed milestone additions shall not weaken those contracts or introduce eager decode, streaming, ownership transfer, raw cursor, or raw native-handle APIs.
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
    - The document open, close, type, and structured error baseline is present together with only separately accepted milestone additions
    - Eager decode, ungoverned projection variants, streaming, cursor, transfer, and native-handle operations are absent
```

## Evidence Inventory

```yaml
- kind: test_file
  target: test/simd_json/document_api_test.exs
  covers:
    - simd_json.document_api.open_contract
    - simd_json.document_api.binary_only
    - simd_json.document_api.close_contract
    - simd_json.document_api.document_argument_validation
    - simd_json.document_api.opaque_document_type
    - simd_json.document_api.structured_error
    - simd_json.document_api.open_and_close
    - simd_json.document_api.non_binary_argument
    - simd_json.document_api.invalid_document_argument
    - simd_json.document_api.close_and_non_owner

- kind: test_file
  target: test/simd_json/error_test.exs
  covers:
    - simd_json.document_api.structured_error
    - simd_json.document_api.initial_error_reasons
    - simd_json.document_api.logical_offsets
    - simd_json.document_api.error_redaction
    - simd_json.document_api.invalid_input_errors
    - simd_json.document_api.redacted_failure

- kind: test_file
  target: test/simd_json/public_surface_test.exs
  covers:
    - simd_json.document_api.milestone_scope
    - simd_json.document_api.no_future_surface

- kind: test_file
  target: test/simd_json_test.exs
  covers:
    - simd_json.document_api.open_contract
    - simd_json.document_api.binary_only
    - simd_json.document_api.close_contract
    - simd_json.document_api.opaque_document_type
    - simd_json.document_api.structured_error
    - simd_json.document_api.error_redaction
    - simd_json.document_api.non_binary_argument
    - simd_json.document_api.redacted_failure
    - simd_json.document_api.close_and_non_owner

- kind: test_file
  target: test/simd_json/phase_5_integration_test.exs
  covers:
    - simd_json.document_api.structured_error
    - simd_json.document_api.initial_error_reasons
    - simd_json.document_api.logical_offsets
    - simd_json.document_api.error_redaction
    - simd_json.document_api.valid_json_values
    - simd_json.document_api.open_and_close
    - simd_json.document_api.all_top_level_values
    - simd_json.document_api.invalid_input_errors
    - simd_json.document_api.non_binary_argument
    - simd_json.document_api.invalid_document_argument
    - simd_json.document_api.redacted_failure
    - simd_json.document_api.close_and_non_owner

- kind: test_file
  target: test/native/document_resource_policy_test.exs
  covers:
    - simd_json.document_api.milestone_scope

- kind: command
  target: bash scripts/native/run_nif_sanitizer_tests.sh
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

- kind: test_file
  target: test/qualification/lifecycle_memory_qualification_test.exs
  covers:
    - simd_json.document_api.open_contract
    - simd_json.document_api.close_contract
    - simd_json.document_api.structured_error
    - simd_json.document_api.initial_error_reasons
    - simd_json.document_api.close_and_non_owner
```

## Required Closure Evidence

The executable API-qualification command below supplies public API, typespec,
doctest, error mapping, redaction, ownership, close, valid-value,
malformed-input, UTF-8, lifetime, and public-surface evidence.

## Verification

```spec-verification
- kind: command
  target: bash scripts/ci/qualify_document_api.sh
  execute: true
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
```
