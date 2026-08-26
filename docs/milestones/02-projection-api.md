# Milestone 2 — Projection with `SimdJson.select/2`

[Back to the architecture overview](../research/simdjson_beam_nif_architecture.md#proposed-implementation-milestones)

## Outcome

This milestone delivers the library's primary value proposition: extract a small, caller-defined projection from a JSON document in one native traversal and return only the requested values as BEAM terms.

For a large input, the cost should be proportional to parsing and locating the selected paths, not to allocating an equivalent Elixir map and list tree. `select/2` is therefore more important to the product than eager `decode/1`.

## Prerequisites

Milestone 1 must already provide:

- a safe opaque `SimdJson.Document` resource;
- stable input-buffer and parser lifetimes;
- off-scheduler native execution;
- structured errors;
- owner and closed-resource checks.

Projection should reuse those contracts rather than introduce a second parsing or ownership model.

## Proposed API

The baseline API accepts either a binary or an open document:

```elixir
projection = [
  id: ["customer", "id"],
  name: ["customer", "name"],
  first_sku: ["orders", 0, "sku"],
  total: ["order", "total"]
]

{:ok, result} = SimdJson.select(json, projection)
```

with a result such as:

```elixir
%{
  id: 1234,
  name: "Acme",
  first_sku: "ABC-123",
  total: 987.42
}
```

The binary form creates a temporary document, evaluates the projection, and releases the document before returning. The document form reuses an existing native document when its cursor semantics permit it:

```elixir
SimdJson.select(document, projection)
```

The implementation must define whether a document is reusable for more than one projection. If On-Demand state makes reuse unsafe, the API should return `:cursor_consumed` rather than silently reparsing or producing order-dependent results.

## Projection specification

A projection is a collection of output-key and path pairs.

- Output keys are atoms or binaries supplied by trusted caller code.
- Object path segments are UTF-8 binaries.
- Array path segments are non-negative integers.
- Empty paths are rejected initially because selecting the entire root undermines the milestone's bounded-output goal.
- Duplicate output keys are rejected before native execution.
- Invalid path segment types return `:invalid_projection`.

JSON keys must never be converted to atoms. An atom output key is safe only because it already exists in the caller's projection.

The first version should guarantee scalar leaves: strings, integers, floats, booleans, and `nil`. Selecting an object or array as a leaf should either be explicitly unsupported or require a materialization selector. It must not accidentally materialize a huge subtree merely because a path stopped early.

## Compile once, traverse once

Performing one independent lookup for every requested path would repeatedly move through the On-Demand cursor and create order-dependent behavior. Instead, the projection should be normalized into a native selection tree before traversal.

```mermaid
flowchart LR
    Spec[Elixir projection] --> Validate[Validate keys and path segments]
    Validate --> IR[Build projection trie]
    JSON[JSON input] --> Scan[simdjson structural scan]
    IR --> Walk[Single guided traversal]
    Scan --> Walk
    Walk --> Slots[Typed native result slots]
    Slots --> Terms[Create requested BEAM terms]
    Terms --> Result[One result map]
```

For the paths:

```text
customer.id
customer.name
order.total
```

the internal representation shares the `customer` prefix:

```text
root
├── customer
│   ├── id   → result slot 0
│   └── name → result slot 1
└── order
    └── total → result slot 2
```

The traversal follows document order and matches requested fields as they are encountered. It does not repeatedly rewind the cursor to honor projection declaration order. Result slots restore the caller's output keys after traversal.

This design also gives a natural foundation for a later public `SimdJson.compile/1`, where the validated projection tree can be reused across many documents.

## Result conversion

Only selected values cross into the BEAM.

| JSON value | Elixir value | Notes |
| --- | --- | --- |
| string | binary | Copy into a fresh small binary by default. |
| signed integer | integer | Preserve exact value within the supported native range. |
| unsigned integer | integer | Validate conversion and range explicitly. |
| floating point | float | Define non-finite handling even though JSON forbids such literals. |
| `true` / `false` | boolean | Use existing atoms only. |
| `null` | `nil` | Use the existing atom. |

Selected strings should normally be copied. Returning a sub-binary backed by a multi-gigabyte source can retain that source long after the document would otherwise be collectible.

BEAM terms should be created after the native traversal has identified and validated all result values, or in bounded steps with a clear cleanup path. A partially built result must never escape after a later field fails.

## Missing fields and type errors

The baseline should be deterministic and fail fast:

```elixir
{:error,
 %SimdJson.Error{
   reason: :no_such_field,
   path: ["customer", "name"]
 }}
```

Recommended initial behavior:

- a missing object field returns `:no_such_field`;
- an array index beyond the end returns `:index_out_of_bounds`;
- applying a field segment to a non-object returns `:incorrect_type`;
- applying an index segment to a non-array returns `:incorrect_type`;
- malformed JSON returns the parse error with a byte offset when available;
- a previously consumed document returns `:cursor_consumed`;
- cancellation returns `:cancelled`.

Options such as defaults, optional fields, per-field errors, and null substitution can be designed later. Adding them prematurely complicates both the native result layout and the meaning of a successful projection.

## One boundary crossing

The performance contract is not merely that simdjson performs the parse. The entire projection must be submitted in one call and returned as one result:

```text
BEAM → validate and enqueue projection → native traversal → build result → BEAM
```

An implementation where each path segment or each selected field invokes another NIF does not satisfy this milestone. Crossing overhead, repeated ownership checks, and forward-only cursor behavior would erase the architectural advantage.

## Document-state behavior

Projection operates under the document's owner and lifecycle rules:

- only the owner process can consume a stateful document;
- one projection runs against a document at a time;
- closing is rejected or deferred while a projection is active;
- every operation checks the resource generation before dereferencing native state;
- a failed projection leaves the document in an explicitly defined state.

The simplest safe rule is that attempting a projection consumes the On-Demand document whether it succeeds or fails. Reuse can be added only if the implementation can prove reset or reparse semantics without surprise.

## Implementation work

1. Define and document the accepted projection term grammar.
2. Validate the complete projection in Elixir or bounded native code before parsing.
3. Compile paths into a prefix-sharing native representation.
4. Traverse objects and arrays once without cursor rewinds.
5. Store located values in typed result slots.
6. Copy strings into fresh BEAM binaries during result conversion.
7. Return one result map with the caller-provided keys.
8. Map path, type, parse, lifecycle, and cancellation errors consistently.
9. Add internal timing for projection compilation, traversal, and term construction so later telemetry can expose it.
10. Document document-consumption semantics and enforce them in tests.

## Verification strategy

Functional tests should cover:

- shared path prefixes and paths in different object branches;
- projection order different from JSON field order;
- nested objects and array indices;
- empty strings, Unicode keys, escaped keys, and escaped string values;
- every scalar JSON type;
- missing fields, wrong container types, and out-of-range indices;
- duplicate output keys and malformed projection terms;
- duplicate keys in the input JSON under a documented policy;
- invalid JSON before, inside, and after a selected branch;
- very large unselected subtrees;
- process ownership, close races, and consumed documents.

Performance tests should compare:

```text
SimdJson.select/2

against

full decode + get_in/2
```

for small, medium, and very large documents. Measure end-to-end latency, throughput, BEAM allocations, native allocations, retained binary memory, garbage-collection time, and scheduler latency. A projection benchmark must include the cost of parsing and result construction rather than timing only an already-positioned cursor.

## Completion criteria

Milestone 2 is complete when:

- one `select/2` call can extract multiple scalar paths from a binary;
- common path prefixes are traversed once;
- only selected values become BEAM terms;
- declaration order does not depend on JSON object order;
- missing and incorrectly typed paths produce structured errors;
- selected strings do not retain the source binary by default;
- document consumption and ownership behavior are deterministic;
- benchmarks demonstrate the expected allocation advantage over full materialization;
- large projections preserve the scheduler-safety guarantee from Milestone 1.

## Deferred work

The following are intentionally outside this milestone unless needed to complete the baseline:

- a public compiled-projection resource;
- JSONPath syntax;
- wildcard or recursive descent paths;
- filters and predicates;
- optional/default field policies;
- selecting and materializing arbitrary container subtrees;
- batch streaming across repeated array elements.
