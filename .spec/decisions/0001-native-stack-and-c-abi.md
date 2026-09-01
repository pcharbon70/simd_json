---
id: simd_json.native_stack_and_c_abi
status: accepted
date: 2026-08-27
affects:
  - simd_json.native_build_and_abi
  - simd_json.document_api
  - simd_json.package
---

# Native Stack and C ABI Boundary

## Context

Milestone 1 must connect Elixir to the official simdjson C++ implementation without allowing C++ object layouts, templates, exceptions, or allocator assumptions to leak into Zig or the BEAM. The build must also remain reproducible for Hex consumers and clean-checkout CI rather than depending on an unrecorded system package or mutable upstream branch.

Zigler gives the project an Elixir-to-Zig NIF boundary and Zig provides direct C interoperability, resource ownership tools, and a single place for BEAM-specific marshalling. Zig does not provide a stable direct C++ object interface, and wrapping C++ types directly would couple every upper layer to compiler-specific ABI details.

## Decision

The Milestone 1 native stack is:

```text
Elixir `SimdJson` API
        ↓
Zigler NIF boundary
        ↓
Zig resource, scheduling, and term-conversion layer
        ↓
private C ABI
        ↓
C++ shim
        ↓
official simdjson C++ implementation
```

### Dependency acquisition and provenance

The package will vendor the exact official simdjson release source required by the native build. It will not link an ambient system installation, follow a mutable Git branch, or download unverified source during compilation.

The vendored dependency record must include:

- the upstream release tag and immutable commit;
- the source archive digest;
- the simdjson license and notices;
- the Zig, Zigler, C++ toolchain, and build-profile versions used for qualification;
- any local patch as a separate, reviewable patch with its own rationale and digest.

The distributed package includes the verified source snapshot, provenance
manifest, ordered patch declaration, and upstream license files. A repository
verification command checks the snapshot without network access and, when
given an already-downloaded official archive, reconstructs the vendored source
by applying only the declared patch series.

Upgrading simdjson or any ABI-relevant toolchain component is an explicit dependency update with clean-build, conformance, sanitizer, and scheduler-safety evidence.

### ABI boundary

The C ABI exposes opaque handles, fixed-width integers, byte pointer/length pairs, stable numeric status codes, and matching destruction functions. Public C headers contain no C++ classes, templates, standard-library containers, exceptions, references, or compiler-specific ownership types.

Every exported C function catches all C++ exceptions before returning. Known simdjson errors map to stable C status codes; allocation failures and unknown exceptions map to distinct internal codes. Exception text is diagnostic only and never becomes the machine-readable Elixir contract.

Every successful constructor has exactly one matching destructor. Partial construction is cleaned inside the layer that allocated it. Null destruction is safe where doing so simplifies failure cleanup, and pointer/length arguments are validated before dereference.

Only the private C ABI symbols are exported. The C++ shim and simdjson implementation symbols remain hidden from consumers.

The Milestone 1 contract is ABI version 1 and uses separate opaque parser and
document handles. Document open accepts a `uint8_t` pointer, a `uint64_t`
logical length, a `uint64_t` allocation capacity, and an explicit document out
parameter. The caller-owned initialized padding is included in capacity but not
logical length, and the input plus parser must outlive the document. The caller
destroys the document before its parser and clears each consumed handle; both
destructors accept null.

The fixed status record contains a signed 32-bit stable category, an optional
signed 32-bit raw simdjson code, and an optional unsigned 64-bit logical byte
offset. Dedicated numeric sentinels represent unavailable diagnostic code and
offset values. The stable categories are success, invalid JSON, invalid UTF-8,
unexpected EOF, out of memory, invalid argument, and internal failure. Raw
upstream text, addresses, and input excerpts never cross the boundary.

For the current static NIF linkage model, the C boundary remains local and the
dynamic artifact exports only the required NIF initialization entry. The
independently linked shared ABI test artifact exports exactly the four declared
parser/document constructor and destructor functions through a versioned
allowlist. Test-only injection and accounting controls are compile-time gated
and must be absent from release symbol tables and strings.

### Phase 5 conformance-probe checkpoint

The Phase 5 lifetime test revalidates an already-open On-Demand document after
the original BEAM binary and threaded-operation environment are unreachable.
Two NIF-internal C declarations associate the opaque document with its owned
input and rewind/revalidate it. They use only opaque handles, fixed-width
values, the existing stable status record, total exception containment, and
hidden visibility. They are absent from the versioned public C header and
dynamic symbol allowlist, so ABI version 1 and its four exported constructor and
destructor symbols do not change.

The high-level `ThreadedOperation` probe helper is compiled only in tests and
runs via the pinned Zigler threaded context with document admission retained
across the C++ traversal. Its generated NIF entry remains confined to the
undocumented native bridge. Native failure-injection and accounting hooks stay
absent from release symbol tables and strings.

### Phase 6 release-qualification checkpoint

Release qualification is bound to a checked-in SHA-256 fingerprint over every
ABI-, runtime-, harness-, workflow-, and evidence-relevant path declared by the
native manifest. The record itself is not an input to its digest, so it can
store the expected value without self-reference. Any other input change makes
`mix simd_json.verify_qualification` fail until the complete qualification
matrix runs for the new revision; an isolated pin-change test freezes that
fail-closed behavior.

The matrix builds and inspects the unpacked Hex artifact, replays vendor and
offline-build verification, checks runtime CPU dispatch and unsupported-target
rejection, runs deterministic and seeded-random C ABI cases, executes C, Zig,
threaded-operation, and public API sanitizer corpora, and inspects release
symbols and strings. CI archives the source revision/tree, target, tool
versions, seed, input digest, package inventory, commands, and outputs. The
Milestone 1 supported matrix remains exactly Ubuntu 24.04 x86-64; experimental
targets receive no generic artifact or fallback claim.

### Milestone 2 Phase 2 ABI checkpoint

Projection advances the canonical header's compile-time version to 2 without
altering the four parser/document signatures, their 16-byte status record, or
their ABI v1 symbol version. Projection functions use a distinct 24-byte status
that adds the optional failing output slot, so the Milestone 1 calling
convention remains intact. The standalone artifact adds only the versioned
projection-plan constructor, null-safe destructor, and reserved execution
entry; the statically linked NIF continues to export only `nif_init`.

The new C++ plan boundary validates every count, pointer/count pair, segment
range, tag, reserved field, output slot, byte range, and structural reference
before allocation. It catches known, allocation, standard, and unknown
exceptions, and one reverse-order ownership arena releases copied key bytes and
nodes after every partial or complete construction. Its independent C11 and
Zig ordinary/sanitizer harnesses join the qualification fingerprint.

### Build and target qualification

The native build is driven through the pinned Zig/Zigler integration and produces the NIF from a clean checkout without requiring a preinstalled simdjson library. It must fail with a clear unsupported-target error rather than silently compile an unqualified combination.

The repository maintains an explicit qualification matrix of operating system, architecture, minimum runtime/toolchain, and expected simdjson runtime-dispatch implementations. Runtime CPU dispatch is allowed only through the pinned official simdjson mechanism and must be observable in diagnostic tests without changing the public API.

Milestone 1 cannot close until at least the release's primary CI target is qualified. Other targets remain explicitly unsupported or experimental until the same native conformance and sanitizer evidence exists.

## Consequences

Milestone 3 Phase 2 implementation checkpoint: the private boundary is now ABI
v3, retaining all ABI v1/v2 layouts and symbols and adding only three versioned
cursor entries. Canonical C11/C++17/Zig layout assertions, release inspection,
and ordinary/sanitizer cursor conformance are executable qualification inputs.

The Zig and Elixir layers depend on a small stable C contract rather than C++ implementation details. Native dependency resolution is reproducible and reviewable, and clean-checkout builds do not vary with the host's package manager.

The package carries vendored third-party source and must maintain license, provenance, upgrade, and vulnerability review. The extra C++ shim adds code and tests, but it confines the highest-risk language boundary to a small surface.

The initial build supports only explicitly qualified platforms. Expanding the matrix requires evidence rather than an assumption that compilation implies correctness.

## Alternatives Rejected

- **Call simdjson C++ directly from Zig:** this exposes unstable C++ ABI and template details to the ownership layer.
- **Write the NIF entirely in C++:** this collapses BEAM resource, scheduling, marshalling, and parser concerns into one exception-prone layer and abandons the chosen Zigler integration.
- **Use a system simdjson package:** this makes builds depend on mutable host state and complicates Hex distribution.
- **Fetch an upstream branch during compilation:** this is non-reproducible and introduces an avoidable supply-chain and offline-build dependency.
- **Reimplement simdjson algorithms in Zig:** this is outside the wrapper's purpose and would no longer use the official parser being evaluated.

## Reopening Conditions

Revisit this decision only if an official, versioned simdjson C ABI provides the required On-Demand ownership and error semantics, Zig gains a stable qualified C++ boundary that removes rather than shifts risk, or vendoring becomes incompatible with the accepted package distribution model. Any replacement must preserve reproducible source provenance, exception containment, opaque ownership, and clean-checkout native verification.
