---
id: simd_json.projection_api_and_validation
status: accepted
date: 2026-08-29
affects:
  - simd_json.projection_api
  - simd_json.projection_engine
---

# Projection API and Validation Contract

## Context

Milestone 2 introduces the first operation that exposes simdjson's On-Demand
advantage directly: selecting a small set of scalar values without building a
complete BEAM representation. The caller-facing grammar must be precise before
the native engine is built. An ambiguous grammar would make duplicate output
keys, invalid paths, atom safety, error locations, and document-consumption
behavior depend on whichever layer happened to reject the input first.

The API must also stay distinct from JSONPath, eager decode, and public cursor
APIs. Those features have different output and lifecycle bounds and are assigned
to later work.

## Decision

### Public operation

Milestone 2 adds one synchronous tagged-result operation:

```elixir
SimdJson.select(source, projection)
```

`source` is either a JSON binary or a genuine open `SimdJson.Document` owned by
the caller. Success returns `{:ok, map()}` and an operational or projection
failure returns `{:error, SimdJson.Error.t()}`. Values that are neither binaries
nor genuine document resources raise `ArgumentError` before native admission,
consistent with the existing `open/1` and `close/1` argument boundary.

### Projection grammar

A projection is a non-empty proper list of two-tuples:

```elixir
[
  {output_key, [segment, ...]},
  ...
]
```

The keyword-list spelling remains valid when every output key is an atom:

```elixir
[id: ["customer", "id"], total: ["order", "total"]]
```

The grammar is closed:

- an output key is an existing atom or a binary;
- an object segment is a valid UTF-8 binary, including the empty binary for an
  empty JSON object key;
- an array segment is an integer from zero through `UINT64_MAX`;
- every path is a non-empty proper list;
- duplicate output keys are rejected using exact BEAM key identity;
- duplicate paths under different output keys are allowed and share one native
  terminal value;
- maps, improper lists, empty projections, empty paths, and every other key or
  segment type are invalid.

The complete projection is validated before a document is consumed or native
projection work is admitted. A grammar failure returns
`{:error, %SimdJson.Error{reason: :invalid_projection}}`; it is not a parser
failure and does not inspect JSON input.

Validation never converts caller binaries or JSON field names to atoms. Atom
output keys are safe only because they already exist in the caller-supplied
term. A binary output key remains a binary in the result.

### Result contract

The result is one map whose keys are the exact caller-supplied output keys.
Declaration order has no semantic effect. Milestone 2 supports only scalar
leaves:

| JSON value | Elixir value |
| --- | --- |
| string | a fresh binary |
| signed or unsigned integer | an exact BEAM integer when representable by the parser contract |
| floating point | a finite BEAM float |
| `true` / `false` | the existing boolean atoms |
| `null` | `nil` |

Stopping a path at an object or array returns `:incorrect_type`; it never
materializes the container. Numeric syntax outside the supported simdjson
integer and floating-point contract returns `:number_out_of_range` rather than
silently rounding or changing type.

Selected strings are copied into fresh result binaries. They never become
sub-binaries or native views that retain the source document or its padded
buffer.

### Error contract

`SimdJson.Error.reason` is extended with the Milestone 2 reasons:

- `:invalid_projection`;
- `:no_such_field`;
- `:index_out_of_bounds`;
- `:incorrect_type`;
- `:number_out_of_range`;
- `:cursor_consumed`;
- `:cancelled`.

The error gains an optional `path` field. When present, it is copied only from
the caller-supplied projection and identifies the failing requested path. It
never contains a discovered source substring, an automatically atomized JSON
key, a native address, or C++ exception text. Existing byte offsets remain
relative to logical JSON input.

Missing fields, out-of-range indexes, type failures, malformed JSON, lifecycle
failures, and cancellation are fail-fast errors for the whole projection. No
partial result map escapes.

### Phase 1 implementation checkpoint

Milestone 2 Phase 1 implements the grammar in an undocumented
`SimdJson.Projection` module. Validation walks the outer and path lists without
enumerating caller maps, rejects improper or malformed tails, checks UTF-8 only
for path binaries, preserves arbitrary binary output keys exactly, and accepts
integer segments only through `UINT64_MAX`. The opaque normalized term assigns
output slots by declaration position and interns equal complete paths by their
first declaration, so multiple keys can reference one stable path slot without
using map enumeration order as output.

The validator is the only constructor for that term. Invalid input returns a
controlled `invalid_projection` error with `path: nil`; it never atomizes a
binary or examines the supplied JSON source. The common error type now reserves
the complete reason union and optional accepted-path shape. Default inspection
reports only that a caller path is present, never its bytes, and defensively
bounds forged reason and numeric fields. Test-only snapshot and source seams are
compile-time gated, and no public `select/2`, compiled projection, serializer,
protocol, or native handle is introduced by this checkpoint.

### Phase 4 internal result checkpoint

An undocumented, test-build-only `SimdJson.Native.ProjectionOperation` now
connects the validated representation to the private threaded engine. It
preserves exact caller atom and binary keys, returns exact signed/unsigned
integers, finite floats, booleans, nil, and newly allocated binaries, and
discards the whole map on every traversal or conversion failure. Stable native
statuses are translated once into the reserved projection reason vocabulary;
an available output slot is resolved only against the validated normalized
projection before its copied caller path is attached. Offsets and native codes
remain bounded and diagnostics contain no source keys, values, paths, or
addresses.

This seam exists solely to exercise the complete internal vertical slice. It
is compiled only in tests and does not add `SimdJson.select/2`, documentation,
typespecs, protocols, or another public struct/resource. Phase 5 still owns the
public argument order, root-module function, doctests, and surface activation.

### Phase 5 public API checkpoint

The root module now exposes the decided `SimdJson.select/2` operation and
public types for its exact closed grammar and transactional scalar map. It runs
complete projection validation first, accepts binaries directly, and accepts a
document-shaped value only after a bounded registered-resource check. Invalid
source values raise `ArgumentError` before projection admission; non-owner and
closed genuine documents retain their structured operational errors.

The Phase 4 adapter is now the production-private operation used by the root
function, while its pause, failure, diagnostic, and synthetic-translation seams
remain test-build-only. One translator maps every projection status, bounds
numeric metadata, attaches a path only for path-specific reasons after resolving
the native output slot against the validated projection, and maps unknown
statuses to `native_failure` without a path. Public scalar, lifetime, redaction,
atom-safety, doctest, export, typespec, protocol, and deferred-surface corpora
exercise that boundary. No normalized projection, plan, cursor, timing, source,
or native identity is returned.

### Phase 6 qualification checkpoint

The public contract is now qualified and active on Ubuntu 24.04 x86-64. The
release package is compiled offline from its unpacked vendored sources, the
public binary/document corpus runs through the sanitizer-instrumented NIF, and
formal scheduler and lifetime profiles preserve exact keys, copied strings,
atomic failures, redaction, and the closed public surface. Frozen sparse
fixtures also compare the complete `select/2` workflow with Jason full decode
plus equivalent lookups. No benchmark, diagnostic, failure-injection, or
compiled-plan option is added to the caller API.

### Deferred surface

Milestone 2 exposes no public compiled-projection resource, JSONPath parser,
wildcard, recursive descent, filter, optional/default field policy, container
materialization selector, stream, raw cursor, or eager decode API.

## Consequences

Callers receive a compact, deterministic API whose shape can be validated
without touching the native document. The list representation preserves enough
information to reject duplicate output keys, while allowing shared paths and
both atom and binary result keys.

The initial API is intentionally strict. Optional fields and container results
would change the meaning and bounds of success, so they require later contract
work rather than ad hoc options.

Copying selected strings adds work proportional to selected output size, but it
prevents a tiny result from retaining a very large source allocation.

## Alternatives Rejected

- **Accept a map as the projection:** map construction has already erased
  duplicate output keys, so complete validation cannot report them.
- **Accept JSONPath strings:** this adds a second parser and syntax surface
  before the underlying typed path model is proven.
- **Atomize JSON object keys:** arbitrary input could exhaust the non-collected
  BEAM atom table.
- **Return per-field errors beside successful fields:** partial success makes
  cleanup, consumption, and result typing substantially more complex.
- **Materialize object or array leaves automatically:** a short path could
  unexpectedly allocate an unbounded BEAM subtree.
- **Return source-backed substrings:** small selected values could retain the
  complete native document or original input.

## Reopening Conditions

Revisit this decision when a public compiled projection, optional/default
fields, container materialization, JSONPath, or zero-copy result mode is
proposed. Any replacement must preserve atom safety, complete preflight
validation, deterministic errors, bounded output semantics, and the rule that
no partial result escapes.
