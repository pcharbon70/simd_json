# Native Build and ABI

Current-truth contract for the reproducible native toolchain, official simdjson source, and exception-safe language boundary required by Milestone 1.

## Intent

This subject ensures that every native artifact can be traced to pinned source and toolchain inputs and that C++ implementation details terminate at one small C ABI before Zig or BEAM ownership begins.

Phases 1 through 3 provide the reproducible vendored build, independently
tested opaque C11 ABI, and canonical-header Zig ownership layer. The official
On-Demand parser remains behind a C++ shim with stable statuses, total exception
translation, reverse partial-failure cleanup, release symbol allowlists, and
ordinary/sanitizer C and Zig harnesses. Phase 4 additionally records and smoke
tests the exact Zigler 0.16 threaded environment, payload, resource, callback,
join, and cancellation constraints. The qualified path now reaches the private
C ABI from a retained Zigler worker and returns only an opaque resource or
bounded status metadata. Callback-safe GC teardown and application/unload
drain are implemented; repeated shared-object unload remains explicitly
unqualified on OTP 27.3. Phase 5 adds a bounded Zig resource type/owner check,
the Elixir document wrapper, and two hidden NIF-internal conformance functions
that revalidate owned input without changing ABI version 1 or its exported
symbol allowlist. Release checks prove native injection controls remain absent.
Phase 6 Section 6.1 adds the release package inspection, deterministic
randomized C ABI stress, isolated threaded/public NIF sanitizer run, and a
checked-in qualification fingerprint. Every ABI-, runtime-, harness-, target-,
workflow-, and evidence-relevant change now makes the recorded proof stale,
and an isolated pin-change test proves the gate fails closed. Section 6.2 adds
the formal scheduler and lifecycle evidence commands to the same fingerprinted
release matrix. Section 6.3 reconciles the public operations documentation and
activates this subject against one executable release-qualification command.

Milestone 2 Phase 1 leaves ABI version 1, native sources, build profiles, and
symbol allowlists unchanged. Its new BEAM validator and executable preflight
corpus are nevertheless runtime- and evidence-relevant, so both are added to
the qualification input manifest. Any later edit to either now invalidates the
recorded fingerprint and must pass the same Milestone 1 release gates.
Milestone 2 Phase 2 advances the canonical compile-time constant to ABI version
2 but retains all four parser/document functions under their ABI v1 symbol
version with the original 16-byte status and behavior. Three ABI v2 symbols add
an opaque projection-plan constructor/destructor pair and the frozen future
execution signature. A separate 24-byte projection status carries the optional
failing slot. Fixed descriptors, result slots, the projection C++ and Zig
translation units, independent C/Zig conformance, failure accounting,
sanitizers, package inventory, and release allowlists are now pinned inputs;
the statically linked NIF still exports only `nif_init`.
Milestone 2 Phase 3 implements the frozen execution symbol behind the same ABI
v2 layout. A C++-only hidden coordination header provides opaque document
cursor access and the operation cancellation probe without adding an exported
symbol. The guided engine conformance translation unit is packaged and pinned
as an ordinary and sanitizer qualification input; ABI v1 behavior and the
seven-symbol private shared-ABI allowlist remain unchanged.

```spec-meta
id: simd_json.native_build_and_abi
kind: subsystem
status: active
verification_minimum_strength: executed
summary: Milestone 1 builds a reproducible native stack around an opaque, exception-safe C ABI.
surface:
  - .tool-versions
  - mix.exs
  - mix.lock
  - native/**
  - test/**/*native*
  - .github/workflows/**
  - docs/milestones/01-native-foundation.md
decisions:
  - simd_json.native_stack_and_c_abi
```

## Requirements

```spec-requirements
- id: simd_json.native_build_and_abi.official_vendored_source
  statement: The native build shall compile an exact vendored official simdjson release whose tag, commit, source digest, license, and notices are recorded in the repository.
  priority: must
  stability: stable

- id: simd_json.native_build_and_abi.pinned_toolchain
  statement: The project shall pin every ABI-relevant Zig, Zigler, C++, simdjson, and native build-profile input needed to reproduce a qualified NIF.
  priority: must
  stability: stable

- id: simd_json.native_build_and_abi.clean_checkout_build
  statement: A supported target shall build the NIF from a clean checkout without an ambient system simdjson installation or an unverified network fetch during compilation.
  priority: must
  stability: stable

- id: simd_json.native_build_and_abi.layered_boundary
  statement: Native calls shall flow through Elixir, Zigler, Zig, a private C ABI, a C++ shim, and the official simdjson implementation without bypassing the accepted ownership boundary.
  priority: must
  stability: stable

- id: simd_json.native_build_and_abi.opaque_c_contract
  statement: The C ABI shall expose only opaque handles, fixed-width scalar values, validated pointer-length pairs, stable status codes, and matching destruction functions.
  priority: must
  stability: stable

- id: simd_json.native_build_and_abi.exception_containment
  statement: Every exported C function shall catch all C++ exceptions and translate them to stable status codes before control returns to Zig.
  priority: must
  stability: stable

- id: simd_json.native_build_and_abi.partial_failure_cleanup
  statement: Each native layer shall release every allocation it owns when construction fails and shall provide exactly one destruction path for each successful constructor.
  priority: must
  stability: stable

- id: simd_json.native_build_and_abi.symbol_visibility
  statement: Release artifacts shall export only the symbols required by the private C ABI and NIF entry boundary while hiding C++ shim and simdjson implementation symbols.
  priority: must
  stability: stable

- id: simd_json.native_build_and_abi.target_qualification
  statement: The repository shall publish and test an explicit supported-target and CPU-dispatch matrix, and unsupported targets shall fail clearly rather than silently using an unqualified build.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.native_build_and_abi.clean_supported_build
  covers:
    - simd_json.native_build_and_abi.official_vendored_source
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.clean_checkout_build
    - simd_json.native_build_and_abi.target_qualification
  given:
    - A clean checkout on a target listed as supported
    - The pinned Elixir, Zig, Zigler, C++, and simdjson inputs
  when:
    - The release native build runs without a system simdjson package
  then:
    - The NIF is produced from the recorded vendored source
    - The selected simdjson runtime implementation is reported by qualification diagnostics
    - Repeating the build uses the same recorded inputs

- id: simd_json.native_build_and_abi.cpp_exception_translation
  covers:
    - simd_json.native_build_and_abi.opaque_c_contract
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.partial_failure_cleanup
  given:
    - A native test seam that injects a known C++ exception and an unknown C++ exception
  when:
    - Each failure crosses the C++ shim boundary
  then:
    - No exception crosses the C ABI
    - Each failure becomes its documented numeric status
    - Every partially created allocation is released exactly once

- id: simd_json.native_build_and_abi.c_abi_conformance
  covers:
    - simd_json.native_build_and_abi.layered_boundary
    - simd_json.native_build_and_abi.opaque_c_contract
    - simd_json.native_build_and_abi.partial_failure_cleanup
  given:
    - An independent native harness linked only to the public C header and private C ABI artifact
  when:
    - It opens valid object, array, and scalar inputs
    - It submits malformed, empty, null-pointer, invalid-length, and injected allocation-failure cases
    - It destroys successful and null handles repeatedly through the documented contract
  then:
    - Success and failure use only documented opaque handles and stable status values
    - Invalid inputs do not crash or expose a C++ exception
    - Every successful or partial allocation is released exactly once

- id: simd_json.native_build_and_abi.release_symbol_surface
  covers:
    - simd_json.native_build_and_abi.symbol_visibility
  given:
    - A release-mode NIF and native shim for a supported target
  when:
    - Their dynamic symbol tables are inspected
  then:
    - Only the required NIF entry and private C ABI symbols are visible
    - No C++ standard-library, shim-internal, or simdjson implementation symbol is exported

- id: simd_json.native_build_and_abi.unsupported_target_rejection
  covers:
    - simd_json.native_build_and_abi.target_qualification
  given:
    - A target absent from the qualified support matrix
  when:
    - The native build is attempted
  then:
    - The build fails with an explicit unsupported-target diagnostic
    - No fallback system library or unqualified parser implementation is used

- id: simd_json.native_build_and_abi.dependency_upgrade_gate
  covers:
    - simd_json.native_build_and_abi.official_vendored_source
    - simd_json.native_build_and_abi.pinned_toolchain
  given:
    - A proposed simdjson or ABI-relevant toolchain upgrade
  when:
    - Its source or version pin changes
  then:
    - Provenance, license, clean-build, ABI conformance, sanitizer, and scheduler evidence are regenerated before acceptance
```

## Required Closure Evidence

The executable release-qualification command below supplies closure evidence for:

- clean-checkout native builds on every supported target;
- independent C ABI unit tests for success, malformed arguments, exception injection, allocation failure, and repeated destruction;
- AddressSanitizer and UndefinedBehaviorSanitizer runs;
- exported-symbol inspection proving only the private C ABI is visible;
- provenance and license checks for the vendored simdjson source;
- runtime CPU-dispatch qualification.

## Evidence Inventory

```yaml
- kind: source_file
  target: .tool-versions
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain

- kind: source_file
  target: mix.exs
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain

- kind: source_file
  target: native/manifest.exs
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.target_qualification

- kind: source_file
  target: native/README.md
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.target_qualification

- kind: source_file
  target: .spec/research/zigler_0_16_threaded_qualification.md
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.layered_boundary

- kind: source_file
  target: native/vendor/simdjson/README.md
  covers:
    - simd_json.native_build_and_abi.official_vendored_source

- kind: command
  target: mix simd_json.verify_vendor
  covers:
    - simd_json.native_build_and_abi.official_vendored_source

- kind: source_file
  target: lib/simd_json/native/build_guard.ex
  covers:
    - simd_json.native_build_and_abi.clean_checkout_build
    - simd_json.native_build_and_abi.target_qualification

- kind: source_file
  target: lib/simd_json/native/build_smoke.ex
  covers:
    - simd_json.native_build_and_abi.clean_checkout_build

- kind: source_file
  target: lib/simd_json.ex
  covers:
    - simd_json.native_build_and_abi.layered_boundary

- kind: source_file
  target: native/include/simd_json_abi.h
  covers:
    - simd_json.native_build_and_abi.opaque_c_contract

- kind: source_file
  target: native/include/simd_json_nif_internal.h
  covers:
    - simd_json.native_build_and_abi.layered_boundary
    - simd_json.native_build_and_abi.opaque_c_contract
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.symbol_visibility

- kind: source_file
  target: native/src/simd_json_abi.cpp
  covers:
    - simd_json.native_build_and_abi.opaque_c_contract
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.partial_failure_cleanup
    - simd_json.native_build_and_abi.symbol_visibility

- kind: source_file
  target: .github/workflows/ci.yml
  covers:
    - simd_json.native_build_and_abi.official_vendored_source
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.clean_checkout_build
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.clean_supported_build
    - simd_json.native_build_and_abi.unsupported_target_rejection

- kind: command
  target: mix compile --force
  covers:
    - simd_json.native_build_and_abi.clean_checkout_build

- kind: test_file
  target: test/native/build_smoke_test.exs
  covers:
    - simd_json.native_build_and_abi.clean_checkout_build
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.clean_supported_build

- kind: test_file
  target: test/native/build_guard_test.exs
  covers:
    - simd_json.native_build_and_abi.official_vendored_source
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.unsupported_target_rejection

- kind: test_file
  target: test/native/native_build_policy_test.exs
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.clean_checkout_build

- kind: command
  target: mix test test/native
  covers:
    - simd_json.native_build_and_abi.official_vendored_source
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.clean_checkout_build
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.clean_supported_build
    - simd_json.native_build_and_abi.unsupported_target_rejection

- kind: command
  target: bash scripts/ci/verify_offline_native_build.sh
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.clean_checkout_build
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.clean_supported_build

- kind: test_file
  target: test/native/c_abi_header_test.exs
  covers:
    - simd_json.native_build_and_abi.opaque_c_contract
    - simd_json.native_build_and_abi.c_abi_conformance

- kind: test_file
  target: test/native/c_abi_conformance_test.exs
  covers:
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.partial_failure_cleanup
    - simd_json.native_build_and_abi.cpp_exception_translation
    - simd_json.native_build_and_abi.c_abi_conformance

- kind: command
  target: bash scripts/native/run_c_abi_conformance.sh ordinary
  covers:
    - simd_json.native_build_and_abi.opaque_c_contract
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.partial_failure_cleanup
    - simd_json.native_build_and_abi.cpp_exception_translation
    - simd_json.native_build_and_abi.c_abi_conformance

- kind: command
  target: bash scripts/native/run_c_abi_conformance.sh sanitizer
  covers:
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.partial_failure_cleanup
    - simd_json.native_build_and_abi.cpp_exception_translation
    - simd_json.native_build_and_abi.c_abi_conformance

- kind: command
  target: bash scripts/native/run_zig_resource_tests.sh ordinary
  covers:
    - simd_json.native_build_and_abi.layered_boundary
    - simd_json.native_build_and_abi.partial_failure_cleanup

- kind: command
  target: bash scripts/native/run_zig_resource_tests.sh sanitizer
  covers:
    - simd_json.native_build_and_abi.layered_boundary
    - simd_json.native_build_and_abi.partial_failure_cleanup

- kind: test_file
  target: test/native/release_symbol_test.exs
  covers:
    - simd_json.native_build_and_abi.symbol_visibility
    - simd_json.native_build_and_abi.release_symbol_surface

- kind: command
  target: bash scripts/native/verify_release_symbols.sh
  covers:
    - simd_json.native_build_and_abi.symbol_visibility
    - simd_json.native_build_and_abi.release_symbol_surface

- kind: source_file
  target: native/qualification/milestone_1.exs
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.dependency_upgrade_gate

- kind: source_file
  target: lib/simd_json/native/build_guard.ex
  covers:
    - simd_json.native_build_and_abi.dependency_upgrade_gate

- kind: command
  target: mix simd_json.verify_qualification
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.dependency_upgrade_gate

- kind: test_file
  target: test/qualification/native_release_qualification_test.exs
  covers:
    - simd_json.native_build_and_abi.clean_supported_build
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.unsupported_target_rejection
    - simd_json.native_build_and_abi.dependency_upgrade_gate

- kind: test_file
  target: test/native/build_guard_test.exs
  covers:
    - simd_json.native_build_and_abi.dependency_upgrade_gate

- kind: command
  target: bash scripts/native/run_nif_sanitizer_tests.sh
  covers:
    - simd_json.native_build_and_abi.layered_boundary
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.partial_failure_cleanup

- kind: command
  target: bash scripts/ci/qualify_native_release.sh
  covers:
    - simd_json.native_build_and_abi.official_vendored_source
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.clean_checkout_build
    - simd_json.native_build_and_abi.layered_boundary
    - simd_json.native_build_and_abi.opaque_c_contract
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.partial_failure_cleanup
    - simd_json.native_build_and_abi.symbol_visibility
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.clean_supported_build
    - simd_json.native_build_and_abi.cpp_exception_translation
    - simd_json.native_build_and_abi.c_abi_conformance
    - simd_json.native_build_and_abi.release_symbol_surface
    - simd_json.native_build_and_abi.unsupported_target_rejection
    - simd_json.native_build_and_abi.dependency_upgrade_gate

- kind: command
  target: bash scripts/ci/qualify_runtime.sh
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.dependency_upgrade_gate
```

## Verification

```spec-verification
- kind: command
  target: bash scripts/ci/qualify_native_release.sh
  execute: true
  covers:
    - simd_json.native_build_and_abi.official_vendored_source
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.clean_checkout_build
    - simd_json.native_build_and_abi.layered_boundary
    - simd_json.native_build_and_abi.opaque_c_contract
    - simd_json.native_build_and_abi.exception_containment
    - simd_json.native_build_and_abi.partial_failure_cleanup
    - simd_json.native_build_and_abi.symbol_visibility
    - simd_json.native_build_and_abi.target_qualification
    - simd_json.native_build_and_abi.clean_supported_build
    - simd_json.native_build_and_abi.cpp_exception_translation
    - simd_json.native_build_and_abi.c_abi_conformance
    - simd_json.native_build_and_abi.release_symbol_surface
    - simd_json.native_build_and_abi.unsupported_target_rejection
    - simd_json.native_build_and_abi.dependency_upgrade_gate
```
