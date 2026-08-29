---
id: simd_json.prefix_sharing_projection_engine
status: accepted
date: 2026-08-29
affects:
  - simd_json.projection_engine
  - simd_json.projection_api
  - simd_json.native_build_and_abi
---

# Prefix-Sharing Native Projection Engine

## Context

simdjson's On-Demand document is forward-moving. Performing one independent
lookup per requested path would make results depend on projection declaration
order, revisit shared prefixes, and encourage a NIF call per field or path
segment. That design would discard the core Milestone 2 advantage.

The engine also has to distinguish minimal materialization from incomplete JSON
validation. It may avoid allocating unselected values, but a malformed token in
an unselected or trailing branch must still fail the projection rather than be
silently ignored.

## Decision

### Prefix-sharing plan

After Elixir preflight validation, the native worker compiles the complete
projection into one immutable prefix-sharing tree. Object-key and array-index
edges are typed distinctly. Terminal nodes contain one or more output-slot
indexes so duplicate paths under different output keys are evaluated once.

Plan construction is deterministic and independent of declaration order.
Object edges are matched while their source object is visited in document
order; requested array indexes are visited in ascending index order. Output
slots restore the association with the caller's exact keys after traversal.

The plan is internal and operation-scoped. Milestone 2 does not publish a
compiled-plan resource or cache plans across calls.

### Private C ABI version 2

The private Zig-to-C++ ABI advances to version 2 for projection. It preserves
the Milestone 1 parser/document constructor and destructor contract and adds:

- fixed-width, tagged projection descriptors and a byte arena for normalized
  object-key data;
- an opaque projection-plan constructor and matching null-safe destructor;
- one projection execution entry accepting a document and complete plan;
- caller-provided, fixed-layout typed result slots;
- stable projection status categories and the failing output-slot identifier
  when one exists.

The C++ plan owns any bytes or nodes it retains after construction. Result-slot
string views borrow document input only inside the native operation; Zig copies
them into fresh BEAM binaries before any plan, document, or temporary input is
released. No pointer, string view, C++ type, allocator object, or exception
crosses into the public Elixir contract.

Every new C function catches all exceptions. Partial plan construction,
traversal failure, result conversion failure, and cancellation unwind through
one dependency-safe destruction path. Release symbol allowlists and independent
C conformance tests are updated for ABI version 2.

### One guided traversal

One execution call consumes the On-Demand document in source order. At each
object or array node it advances the source cursor once, follows matching plan
edges, and skips unrequested values without constructing BEAM terms. Shared
prefixes are visited once.

The traversal consumes and structurally validates the complete JSON value,
including unselected branches and bytes after the last selected value. Skipping
means no materialization, not no validation. Invalid JSON anywhere in the
logical input returns the corresponding parse error.

When a JSON object repeats a key requested by the plan, the first occurrence in
document order supplies that path. Later duplicates are still structurally
consumed and validated but do not overwrite a completed result slot. This
policy applies independently at every object depth.

### Transactional typed results

Traversal writes only native typed slots. No public result is constructed until
the full document has validated and every requested terminal has exactly one
supported scalar value. Missing fields, indexes, type failures, parse failures,
numeric range failures, cancellation, and allocation failures discard all
slots and return one stable error.

Only after native success does Zig create the bounded result terms in an
operation-owned environment. Conversion is chunked with cancellation checks
where result size makes one unbroken conversion unsafe. Delivery transfers one
complete result map across one BEAM/NIF request boundary.

Internal, redacted timing may record projection compilation, traversal, and
term-construction durations. It is test/diagnostic data for later telemetry and
is not a Milestone 2 public API.

## Consequences

The engine's work follows the JSON document rather than the caller's path
ordering. Common prefixes and identical paths are evaluated once, while result
slots retain the public key association.

Complete structural validation may inspect much more input than the selected
paths alone require. This is intentional: successful projection means the
source is valid JSON, not merely that selected prefixes happened to parse.

The private ABI grows and must be requalified, but C++ ownership and exception
behavior remain behind fixed C data shapes. A future compiled-projection API can
reuse the plan model only after accepting its own resource and cache policy.

## Alternatives Rejected

- **One lookup per path:** forward-only cursor position makes behavior
  declaration-order-dependent and repeats shared-prefix work.
- **One NIF call per field or segment:** boundary and ownership overhead scales
  with the projection and exposes cursor state piecemeal.
- **Stop parsing after all slots are filled:** malformed trailing or unselected
  JSON could be reported as success.
- **Build BEAM terms during traversal:** a later error could leave partial terms
  and complicate cleanup across native failure paths.
- **Use declaration order as traversal order:** requested order is unrelated to
  object order and would require rewinds or reparsing.
- **Expose the plan handle publicly in Milestone 2:** public caching and
  cross-process lifetime rules are not required to prove the baseline API.

## Reopening Conditions

Revisit this decision if the pinned simdjson release provides a better
qualified multi-path API, if a public compiled projection is proposed, or if
complete-source validation proves incompatible with the accepted performance
goal. Any replacement must remain declaration-order-independent, avoid
per-field NIF crossings, contain C++ exceptions, and never return a partial
result.
