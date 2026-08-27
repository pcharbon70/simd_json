---
id: simd_json.native_stack_and_c_abi
status: accepted
date: 2026-08-27
affects:
  - simd_json.native_build_and_abi
  - simd_json.document_api
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

Upgrading simdjson or any ABI-relevant toolchain component is an explicit dependency update with clean-build, conformance, sanitizer, and scheduler-safety evidence.

### ABI boundary

The C ABI exposes opaque handles, fixed-width integers, byte pointer/length pairs, stable numeric status codes, and matching destruction functions. Public C headers contain no C++ classes, templates, standard-library containers, exceptions, references, or compiler-specific ownership types.

Every exported C function catches all C++ exceptions before returning. Known simdjson errors map to stable C status codes; allocation failures and unknown exceptions map to distinct internal codes. Exception text is diagnostic only and never becomes the machine-readable Elixir contract.

Every successful constructor has exactly one matching destructor. Partial construction is cleaned inside the layer that allocated it. Null destruction is safe where doing so simplifies failure cleanup, and pointer/length arguments are validated before dereference.

Only the private C ABI symbols are exported. The C++ shim and simdjson implementation symbols remain hidden from consumers.

### Build and target qualification

The native build is driven through the pinned Zig/Zigler integration and produces the NIF from a clean checkout without requiring a preinstalled simdjson library. It must fail with a clear unsupported-target error rather than silently compile an unqualified combination.

The repository maintains an explicit qualification matrix of operating system, architecture, minimum runtime/toolchain, and expected simdjson runtime-dispatch implementations. Runtime CPU dispatch is allowed only through the pinned official simdjson mechanism and must be observable in diagnostic tests without changing the public API.

Milestone 1 cannot close until at least the release's primary CI target is qualified. Other targets remain explicitly unsupported or experimental until the same native conformance and sanitizer evidence exists.

## Consequences

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
