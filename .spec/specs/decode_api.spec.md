# Compatible Decode API

Planned current-truth contract for Milestone 5 eager JSON materialization and
the safe Jason 1.4.5 compatibility subset. Phase 3 fills the private ABI v4
graph for every JSON value type; public functions remain planned.

## Intent

This subject adds a familiar complete-value decoder without creating atoms,
silently rounding numbers, recursively overflowing native stacks, bypassing
bounded admission, or exposing partially materialized results. Phases 1–3 own
the contract, preflight, and native graph; public functions arrive in Phase 5.

```spec-meta
id: simd_json.decode_api
kind: feature
status: planned
summary: Milestone 5 will provide binary-only eager decode through the bounded native pool with a documented safe Jason compatibility subset.
surface:
  - lib/simd_json/decode_options.ex
  - lib/simd_json/error.ex
  - test/**/*decode*
  - docs/milestones/05-compatible-decode-api.md
decisions:
  - simd_json.safe_decode_compatibility_contract
  - simd_json.flat_owned_decode_result_abi
bootstrap:
  reason: Phase 1 establishes contract and preflight only; materialization begins in Phase 2 and public decode functions arrive in Phase 5.
  requirements:
    - simd_json.decode_api.binary_input
    - simd_json.decode_api.closed_options
    - simd_json.decode_api.complete_values
    - simd_json.decode_api.binary_keys
    - simd_json.decode_api.exact_numbers
    - simd_json.decode_api.iterative_limits
    - simd_json.decode_api.pool_execution
    - simd_json.decode_api.shared_errors
```

## Requirements

```spec-requirements
- id: simd_json.decode_api.binary_input
  statement: Decode shall accept one complete JSON binary and reject iodata or other source types before admission.
  priority: must
  stability: stable

- id: simd_json.decode_api.closed_options
  statement: The first compatibility release shall accept only an empty proper option list and reject every unknown, duplicate, improper, or non-list option shape before admission.
  priority: must
  stability: stable

- id: simd_json.decode_api.complete_values
  statement: Decode shall materialize every JSON value type with maps, lists, copied binaries, exact numeric terms, booleans, and nil according to the pinned compatibility matrix.
  priority: must
  stability: evolving

- id: simd_json.decode_api.binary_keys
  statement: Object keys shall be copied binaries, arbitrary input shall never create atoms, and the last duplicate key shall win.
  priority: must
  stability: stable

- id: simd_json.decode_api.exact_numbers
  statement: Integers shall remain exact or return number_out_of_range without float rounding, and non-finite floating results shall fail.
  priority: must
  stability: evolving

- id: simd_json.decode_api.iterative_limits
  statement: Materialization shall use a bounded explicit stack and stable depth, container, string, input, and output limit failures.
  priority: must
  stability: evolving

- id: simd_json.decode_api.pool_execution
  statement: Decode shall execute through the Milestone 4 bounded pool with cancellation, busy rejection, redacted telemetry, and exactly-once cleanup.
  priority: must
  stability: stable

- id: simd_json.decode_api.shared_errors
  statement: Tagged and raising decode functions shall share one redacted SimdJson.Error value and never expose source excerpts or partial trees.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: simd_json.decode_api.preflight
  covers:
    - simd_json.decode_api.binary_input
    - simd_json.decode_api.closed_options
  given:
    - Binary and non-binary sources with empty, unknown, and malformed options
  when:
    - Decode input is normalized before native admission
  then:
    - Only a binary with an empty proper list succeeds
    - Invalid terms cause no request, allocation, parse, or lifecycle change

- id: simd_json.decode_api.compatible_materialization
  covers:
    - simd_json.decode_api.complete_values
    - simd_json.decode_api.binary_keys
    - simd_json.decode_api.exact_numbers
  given:
    - The pinned valid, duplicate-key, Unicode, and numeric corpus
  when:
    - Both Jason 1.4.5 and SimdJson decode it
  then:
    - Documented cases produce equivalent values or explicit known differences
    - No input-derived atom or source-retaining binary is created

- id: simd_json.decode_api.bounded_failure
  covers:
    - simd_json.decode_api.iterative_limits
    - simd_json.decode_api.pool_execution
    - simd_json.decode_api.shared_errors
  given:
    - Deep, oversized, malformed, cancelled, and saturated jobs
  when:
    - Decode cannot produce a complete value
  then:
    - One stable redacted error is returned or raised
    - Partial state is released and retained gauges return to baseline
```

## Verification

```spec-verification
- kind: command
  target: MIX_ENV=test mix test test/simd_json/decode_options_test.exs
  execute: true
  covers:
    - simd_json.decode_api.binary_input
    - simd_json.decode_api.closed_options
    - simd_json.decode_api.preflight

- kind: command
  target: bash scripts/ci/qualify_decode.sh
  execute: false
  covers:
    - simd_json.decode_api.complete_values
    - simd_json.decode_api.binary_keys
    - simd_json.decode_api.exact_numbers
    - simd_json.decode_api.iterative_limits
    - simd_json.decode_api.pool_execution
    - simd_json.decode_api.shared_errors
    - simd_json.decode_api.compatible_materialization
    - simd_json.decode_api.bounded_failure
```
