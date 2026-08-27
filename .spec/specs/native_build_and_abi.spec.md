# Native Build and ABI

Current-truth contract for the reproducible native toolchain, official simdjson source, and exception-safe language boundary required by Milestone 1.

## Intent

This subject ensures that every native artifact can be traced to pinned source and toolchain inputs and that C++ implementation details terminate at one small C ABI before Zig or BEAM ownership begins.

```spec-meta
id: simd_json.native_build_and_abi
kind: subsystem
status: planned
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

Before this subject changes from `planned` to `active`, replace the bootstrap exception with executed verification for:

- clean-checkout native builds on every supported target;
- independent C ABI unit tests for success, malformed arguments, exception injection, allocation failure, and repeated destruction;
- AddressSanitizer and UndefinedBehaviorSanitizer runs;
- exported-symbol inspection proving only the private C ABI is visible;
- provenance and license checks for the vendored simdjson source;
- runtime CPU-dispatch qualification.

## Verification

```spec-verification
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
  target: .github/workflows/ci.yml
  covers:
    - simd_json.native_build_and_abi.pinned_toolchain
    - simd_json.native_build_and_abi.clean_checkout_build

- kind: command
  target: mix compile --force
  covers:
    - simd_json.native_build_and_abi.clean_checkout_build
```

## Exceptions

```spec-exceptions
- id: simd_json.native_build_and_abi.milestone_01_bootstrap
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
  reason: Milestone 1 native code does not exist yet; remove this exception and add executed native, sanitizer, provenance, and clean-build verification before activating the subject.
```
