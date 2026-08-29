# Projection API

Planned current-truth contract for the Milestone 2 `SimdJson.select/2` public
API, projection grammar, scalar result map, and stable projection errors.

## Intent

This subject gives callers one operation that extracts several named scalar
paths while allocating only the requested BEAM values. It fixes the public term
grammar and error behavior before implementation so native details, cursor
position, and arbitrary JSON keys cannot leak into the caller contract.

```spec-meta
id: simd_json.projection_api
kind: api
status: planned
summary: Milestone 2 exposes validated binary and document projection through one transactional select/2 result.
surface:
  - lib/simd_json.ex
  - lib/simd_json/**/*.ex
  - test/**/*projection*
  - test/**/*select*
  - docs/milestones/02-projection-api.md
decisions:
  - simd_json.projection_api_and_validation
  - simd_json.projection_admission_consumption_and_lifetime
  - simd_json.document_resource_and_buffer_ownership
```

## Requirements

```spec-requirements
- id: simd_json.projection_api.select_contract
  statement: SimdJson.select/2 shall accept a JSON binary or genuine caller-owned SimdJson.Document plus a projection and return either {:ok, map()} or {:error, SimdJson.Error.t()}.
  priority: must
  stability: evolving

- id: simd_json.projection_api.source_argument_validation
  statement: SimdJson.select/2 shall raise ArgumentError for a source that is neither a binary nor a genuine SimdJson.Document resource before projection work is submitted.
  priority: must
  stability: stable

- id: simd_json.projection_api.projection_grammar
  statement: A projection shall be a non-empty proper list of unique atom-or-binary output keys paired with non-empty proper paths whose segments are valid UTF-8 binaries or integers from zero through UINT64_MAX.
  priority: must
  stability: stable

- id: simd_json.projection_api.complete_preflight_validation
  statement: The complete projection shall be validated before native admission or document consumption, and every invalid collection, key, path, segment, improper list, empty path, or duplicate output key shall return invalid_projection without inspecting JSON input.
  priority: must
  stability: stable

- id: simd_json.projection_api.output_key_identity
  statement: A successful result map shall use the exact caller-supplied atom or binary output keys without creating an atom from projection binaries or JSON input.
  priority: must
  stability: stable

- id: simd_json.projection_api.scalar_results
  statement: Selected string, signed integer, unsigned integer, floating-point, boolean, and null leaves shall become the corresponding binary, exact integer, finite float, boolean, and nil BEAM values, while an object or array leaf shall return incorrect_type without materialization.
  priority: must
  stability: stable

- id: simd_json.projection_api.fresh_string_results
  statement: Every selected JSON string shall be copied into a fresh result binary that does not retain the source binary, native padded input, or document resource.
  priority: must
  stability: stable

- id: simd_json.projection_api.atomic_result
  statement: SimdJson.select/2 shall return one complete result map only after every requested path and the complete JSON source have succeeded, and shall expose no partial result when any later path, parse, conversion, allocation, or cancellation step fails.
  priority: must
  stability: stable

- id: simd_json.projection_api.projection_error_reasons
  statement: SimdJson.Error shall add stable invalid_projection, no_such_field, index_out_of_bounds, incorrect_type, number_out_of_range, cursor_consumed, and cancelled reasons while preserving the existing parse, ownership, lifecycle, allocation, and native failure reasons.
  priority: must
  stability: evolving

- id: simd_json.projection_api.error_path
  statement: A projection error may expose an optional path copied only from the caller-supplied projection and shall not expose source substrings, automatically created atoms, native addresses, padding, or C++ exception text.
  priority: must
  stability: stable

- id: simd_json.projection_api.milestone_scope
  statement: Milestone 2 shall expose no public compiled projection, JSONPath, wildcard, recursive descent, filter, optional or default field policy, container materialization, stream, raw cursor, ownership transfer, or eager decode API.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: simd_json.projection_api.binary_multi_select
  covers:
    - simd_json.projection_api.select_contract
    - simd_json.projection_api.output_key_identity
    - simd_json.projection_api.atomic_result
  given:
    - A valid JSON binary containing nested object and array values
    - A projection with atom and binary output keys in an order different from the JSON fields
  when:
    - SimdJson.select/2 is called once
  then:
    - It returns one map containing every requested scalar under the exact supplied key
    - No unselected container or value appears in the result

- id: simd_json.projection_api.document_select
  covers:
    - simd_json.projection_api.select_contract
  given:
    - A fresh open document owned by the caller
    - A valid multi-path projection
  when:
    - The owner calls SimdJson.select/2
  then:
    - The call returns the same public result shape as the binary form
    - The document resource itself is never exposed in the result

- id: simd_json.projection_api.invalid_source_argument
  covers:
    - simd_json.projection_api.source_argument_validation
  given:
    - An atom, iolist, map, reference, forged document-shaped value, and resource of another registered type
  when:
    - Each value is supplied as the select source
  then:
    - ArgumentError is raised before native admission
    - No document or projection state changes

- id: simd_json.projection_api.invalid_projection
  covers:
    - simd_json.projection_api.projection_grammar
    - simd_json.projection_api.complete_preflight_validation
  given:
    - Empty, map-shaped, improper, duplicate-key, invalid-key, empty-path, improper-path, invalid-UTF-8 segment, negative-index, oversized-index, and unsupported-segment projections
  when:
    - Each projection is submitted with a binary and with a fresh document
  then:
    - Each call returns invalid_projection before JSON parsing or native submission
    - The document remains fresh and usable by a later valid projection

- id: simd_json.projection_api.all_scalar_types
  covers:
    - simd_json.projection_api.scalar_results
    - simd_json.projection_api.fresh_string_results
  given:
    - Requested string, signed integer, unsigned integer, floating-point, true, false, and null leaves
  when:
    - The projection succeeds
  then:
    - Every value has the documented Elixir type and numeric fidelity
    - Every selected string remains valid after the source and document are released
    - Selecting an object or array leaf returns incorrect_type and no container term

- id: simd_json.projection_api.path_failures
  covers:
    - simd_json.projection_api.projection_error_reasons
    - simd_json.projection_api.error_path
    - simd_json.projection_api.atomic_result
  given:
    - Projections containing a missing field, out-of-range index, wrong container segment, unsupported numeric value, and a later failing path after earlier paths succeed
  when:
    - Each projection is evaluated
  then:
    - The documented stable reason and caller-supplied failing path are returned
    - No partial map, source substring, native address, or exception text escapes

- id: simd_json.projection_api.atom_and_surface_safety
  covers:
    - simd_json.projection_api.output_key_identity
    - simd_json.projection_api.milestone_scope
  given:
    - JSON containing many unique object keys and a valid binary-key projection
    - The completed Milestone 2 modules, documentation, exports, and typespecs
  when:
    - Selection runs and the public surface is enumerated
  then:
    - No JSON or binary projection key is converted into a new atom
    - The result retains its binary output key
    - Only select/2 is added to the Milestone 1 API surface and all deferred operations remain absent
```

## Required Closure Evidence

Before activation, replace the bootstrap exception with executed API, grammar,
typespec, doctest, scalar corpus, atom-safety, output-lifetime, error-path,
redaction, argument-boundary, and public-surface verification. Both binary and
document sources must run through the real native projection path.

## Exceptions

```spec-exceptions
- id: simd_json.projection_api.milestone_02_bootstrap
  covers:
    - simd_json.projection_api.select_contract
    - simd_json.projection_api.source_argument_validation
    - simd_json.projection_api.projection_grammar
    - simd_json.projection_api.complete_preflight_validation
    - simd_json.projection_api.output_key_identity
    - simd_json.projection_api.scalar_results
    - simd_json.projection_api.fresh_string_results
    - simd_json.projection_api.atomic_result
    - simd_json.projection_api.projection_error_reasons
    - simd_json.projection_api.error_path
    - simd_json.projection_api.milestone_scope
    - simd_json.projection_api.binary_multi_select
    - simd_json.projection_api.document_select
    - simd_json.projection_api.invalid_source_argument
    - simd_json.projection_api.invalid_projection
    - simd_json.projection_api.all_scalar_types
    - simd_json.projection_api.path_failures
    - simd_json.projection_api.atom_and_surface_safety
  reason: Milestone 2 projection is not implemented; remove this exception and replace it with executed public API, grammar, result, error, lifetime, atom-safety, and scope evidence before activation.
```
