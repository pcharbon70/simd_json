# Phase 2 — ABI v4 and Iterative Materializer Ownership

Back to plan: [README](./README.md)

- [ ] 2 Phase - Freeze the private decode ABI and establish iterative native
  materializer, result, and Zig ownership before value conversion.

## 2.1 Section — ABI v4 Decode Graph Contract

- [x] 2.1 Section - Freeze opaque materializer and result handles plus a flat,
  index-based result graph whose byte ranges borrow result-owned storage.
  - [x] 2.1.1 Task - Accept the ABI v4 ownership decision and descriptor layout.
  - [x] 2.1.2 Task - Prove the header remains C11/C++17 compatible with frozen
    sizes, offsets, sentinels, and symbols.

## 2.2 Section — Iterative C++ Materializer Ownership

- [ ] 2.2 Section - Implement exception-contained constructors, explicit frame
  storage, transactional publication, and exactly-once native rollback.
  - [ ] 2.2.1 Task - Keep document, configuration, frames, nodes, edges, and
    copied bytes behind opaque owners.
  - [ ] 2.2.2 Task - Cover invalid descriptors and injected allocation,
    simdjson, standard, and unknown failures without leaks.

## 2.3 Section — Zig Decode Ownership and Rollback

- [ ] 2.3 Section - Serialize limits and own materializer/result handles in
  Zig without exposing raw BEAM terms or input-derived pointers.
  - [ ] 2.3.1 Task - Transfer each handle at one documented boundary and make
    deinitialization idempotent.
  - [ ] 2.3.2 Task - Validate borrowed graph views and rollback every partial
    construction path.

## 2.4 Section — Phase 2 Integration and Qualification

- [ ] 2.4 Section - Integrate ABI v4 sources and tests into native builds,
  symbol policy, packaging, traceability, and sanitizer qualification.
  - [ ] 2.4.1 Task - Run ordinary and sanitizer C/Zig ownership matrices.
  - [ ] 2.4.2 Task - Reconcile the manifest, qualification fingerprint, format,
    regression suite, traceability, and SpecLed state.
