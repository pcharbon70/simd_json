---
id: simd_json.safe_decode_compatibility_contract
status: accepted
date: 2026-09-04
affects:
  - simd_json.decode_api
  - simd_json.package
---

# Safe Decode Compatibility Contract

## Context

Eager decode is useful for adoption but necessarily materializes the complete
JSON graph. Jason also exposes optional behaviors that would conflict with this
library's atom-safety and deliberately bounded native execution model.

## Decision

Milestone 5 targets Jason 1.4.5 success/failure and value parity for binary
JSON with the empty option list. All top-level JSON values are accepted,
object keys are fresh binaries, source order is preserved for arrays, and the
last duplicate object key wins. Arbitrary key atomization, iodata, structs,
custom decoders, floats-as-decimals, and every non-empty option list are outside
the first contract.

Integers must remain exact, including values outside 64-bit ranges, or fail
with `:number_out_of_range`; conversion through a rounded float is forbidden.
Non-finite float results, malformed Unicode, trailing data, and a byte-order
mark are rejected. Decode will use an explicit native stack, copied strings,
configured finite limits, cancellation checkpoints, and the Milestone 4 pool.

Phase 1 publishes no `decode` function. It implements only deterministic BEAM
preflight and reserves the stable redacted error vocabulary needed later.

## Consequences

Phase 5 publishes the four decode arities over one bounded-pool operation.
The raising functions are Elixir wrappers over tagged decode and raise the same
redacted `SimdJson.Error`; the closed binary-plus-empty-options contract is
validated before admission.

Compatibility is measurable and safe rather than universal. Future option or
iodata support requires a separate decision, public contract, and evidence.

Phase 6 accepts this contract on the qualified Ubuntu 24.04 x86-64 target. Its
differential corpus records Jason's first-value duplicate-key behavior against
the accepted last-value SimdJson behavior, and the aggregate qualifier binds
compatibility, resource, scheduler, sanitizer, package, and benchmark evidence
to the source revision.
