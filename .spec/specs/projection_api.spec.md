# Projection API

Active current-truth contract for the Milestone 2 `SimdJson.select/2` public
API, projection grammar, scalar result map, and stable projection errors.

## Intent

This subject gives callers one operation that extracts several named scalar
paths while allocating only the requested BEAM values. It fixes the public term
grammar and error behavior before implementation so native details, cursor
position, and arbitrary JSON keys cannot leak into the caller contract.

Phase 1 implements the grammar as an undocumented BEAM preflight module.
It assigns declaration-order output slots, preserves exact caller keys and
paths, deterministically interns identical paths, validates proper-list shape,
UTF-8 object segments, and the complete unsigned 64-bit index domain, and
returns one controlled `invalid_projection` error before any native admission.
`SimdJson.Error` carries the reserved Milestone 2 reason union and optional
redacted caller path.
Phase 2 consumes representative copies of that normalized shape only in native
conformance: its Zig serializer deliberately omits output keys and raw BEAM
terms, and its C++ plan remains an opaque operation detail. It adds no Elixir
function, protocol, struct, resource, error translation, or compiled-plan API;
the existing preflight and public-surface boundaries therefore remain intact.
Phase 3 implements the guided scalar engine only below the BEAM. Phase 4
uses an undocumented test-only adapter to exercise both accepted source forms,
exact caller keys and scalar values, fresh copied strings, atomic maps, stable
reasons, and validated caller paths through the real threaded runtime. Invalid
projection stops before source classification or native admission. Phase 5 now
publishes `SimdJson.select/2` with its closed public types, binary and genuine
document dispatch, one stable translator, exact scalar maps, copied strings,
validated caller-path errors, doctests, atom-safety corpus, and export/type/
protocol allowlists. No normalized representation, native plan, cursor state,
timing, diagnostic, or deferred operation crosses that boundary. This subject
is now active after Phase 6 qualified the packaged public path, native
sanitizer corpus, projection scheduler and lifecycle profiles, and frozen Jason
comparison on the supported target.
Milestone 3 Phase 1 reuses this exact validator for each `fields` projection and
adds one internal target-path entry that permits only the streaming root path
to be empty. The active `select/2` grammar remains non-empty and unchanged;
shared-path interning, exact caller keys, UTF-8 and unsigned-index validation,
invalid-projection behavior, and atom safety continue through the same code.

```spec-meta
id: simd_json.projection_api
kind: api
status: active
verification_minimum_strength: executed
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

Phase 5 supplies executed API, grammar, typespec, doctest, scalar corpus,
atom-safety, output-lifetime, error-path, redaction, argument-boundary, and
public-surface evidence through the real native projection path for both source
forms. Phase 6 adds the complete supported-target package, sanitizer,
scheduler, lifecycle, and frozen Jason comparison evidence through the
executable command below.

## Evidence Inventory

```yaml
- kind: test_file
  target: test/simd_json/select_test.exs
  covers:
    - simd_json.projection_api.select_contract
    - simd_json.projection_api.source_argument_validation
    - simd_json.projection_api.complete_preflight_validation
    - simd_json.projection_api.output_key_identity
    - simd_json.projection_api.scalar_results
    - simd_json.projection_api.fresh_string_results
    - simd_json.projection_api.atomic_result
    - simd_json.projection_api.projection_error_reasons
    - simd_json.projection_api.error_path
    - simd_json.projection_api.binary_multi_select
    - simd_json.projection_api.document_select
    - simd_json.projection_api.invalid_source_argument
    - simd_json.projection_api.invalid_projection
    - simd_json.projection_api.all_scalar_types
    - simd_json.projection_api.path_failures
    - simd_json.projection_api.atom_and_surface_safety

- kind: test_file
  target: test/simd_json/projection_validation_test.exs
  covers:
    - simd_json.projection_api.projection_grammar
    - simd_json.projection_api.complete_preflight_validation
    - simd_json.projection_api.output_key_identity
    - simd_json.projection_api.invalid_projection

- kind: test_file
  target: test/simd_json/public_surface_test.exs
  covers:
    - simd_json.projection_api.select_contract
    - simd_json.projection_api.error_path
    - simd_json.projection_api.milestone_scope
    - simd_json.projection_api.atom_and_surface_safety

- kind: test_file
  target: test/simd_json_test.exs
  covers:
    - simd_json.projection_api.select_contract
    - simd_json.projection_api.projection_error_reasons
    - simd_json.projection_api.error_path
```

## Verification

```spec-verification
- kind: command
  target: bash scripts/ci/qualify_document_api.sh
  execute: true
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
```
