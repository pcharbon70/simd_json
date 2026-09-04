---
id: simd_json.native_pool_qualification_and_activation
status: accepted
date: 2026-09-04
affects:
  - simd_json.native_pool
  - simd_json.package
  - simd_json.native_build_and_abi
---

# Native Pool Qualification and Activation

## Context

Production operations use the bounded pool, but the subject remained planned
until saturation, scheduler responsiveness, memory cleanup, race behavior,
sanitizers, and operating limits were proven together.

## Decision

Activate the native-pool contract only when a deterministic profile proves the
fixed worker-plus-queue bound, FIFO dequeue, immediate content-free rejection,
responsive BEAM scheduling, and zero retained bytes after drain. Preserve that
profile as machine-readable JSON. Repeat cancellation, delivery, resource,
close, and shutdown cases with adjacent fixed seeds, then run C ABI, Zig
resource, NIF sanitizer, and release-symbol gates through one command.

Package and CI inputs include the profile, qualifier, completed Phase 6 plan,
and concrete operations guidance. Native upgrades require an application or VM
restart while an existing pool runtime is loaded.

## Consequences

Milestone 4 is active on the qualified target with reproducible operational
evidence. Queue growth, adaptive sizing, priorities, and transparent in-place
NIF upgrades remain outside the contract.
