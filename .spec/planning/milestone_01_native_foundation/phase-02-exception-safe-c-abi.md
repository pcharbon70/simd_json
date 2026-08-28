# Phase 2 — Exception-Safe C ABI

Back to plan: [README](./README.md)

- [ ] 2 Phase - Contain all simdjson C++ behavior behind one independently testable private C contract.

  This phase replaces the smoke boundary with the smallest parser ABI required
  by Milestone 1. The public native header contains only opaque handles and plain
  C values, the C++ shim catches every exception and owns its partial failures,
  and release symbol inspection proves implementation details remain hidden.
  Zig and BEAM resource work do not begin until the native harness can exercise
  this boundary safely on its own.

  Contract focus:

  - `simd_json.native_build_and_abi.layered_boundary`
  - `simd_json.native_build_and_abi.opaque_c_contract`
  - `simd_json.native_build_and_abi.exception_containment`
  - `simd_json.native_build_and_abi.partial_failure_cleanup`
  - `simd_json.native_build_and_abi.symbol_visibility`
  - `simd_json.native_build_and_abi.cpp_exception_translation`
  - `simd_json.native_build_and_abi.c_abi_conformance`
  - `simd_json.native_build_and_abi.release_symbol_surface`

## 2.1 Section — Opaque Header and Status Vocabulary

- [x] 2.1 Section - Define a compiler-neutral C header with stable ownership and error semantics.

  This section freezes the only contract Zig may import. It makes input lifetime,
  logical length, output initialization, status categories, and destruction
  responsibilities explicit without exposing any C++ layout or allocator type.

  - [x] 2.1.1 Task - Define the Milestone 1 handle and function surface.

    The task specifies only the parser/document operations needed to validate a
    JSON input and retain an On-Demand document for later milestones.

    - [x] 2.1.1.1 Subtask - Declare opaque parser and document handle types without typedefing C++ objects or exposing their sizes.
    - [x] 2.1.1.2 Subtask - Define constructor or open functions using fixed-width values, `uint8_t` pointer plus logical length, and explicit out parameters.
    - [x] 2.1.1.3 Subtask - Define matching destruction functions and document whether null handles are accepted so failure cleanup can be written without ambiguity.
    - [x] 2.1.1.4 Subtask - Document that the caller-owned padded input must outlive the returned document handle and that padding capacity is not part of the logical JSON length.
    - [x] 2.1.1.5 Subtask - Add compile-time layout assertions for every exported scalar and status field used across the C/Zig boundary.

  - [x] 2.1.2 Task - Define stable native status codes and offsets.

    The task creates one numeric vocabulary that contains simdjson errors before
    Zig translates them into the public Elixir reason set.

    - [x] 2.1.2.1 Subtask - Assign stable status codes for success, invalid JSON, invalid UTF-8, unexpected EOF, allocation failure, invalid arguments, and unmapped internal failure.
    - [x] 2.1.2.2 Subtask - Define an unambiguous sentinel for an unavailable byte offset and require every available offset to be relative to logical input bytes.
    - [x] 2.1.2.3 Subtask - Keep simdjson's raw numeric code as optional diagnostic metadata without treating upstream text as machine-readable behavior.
    - [x] 2.1.2.4 Subtask - Validate null pointers, pointer-length combinations, out parameters, length overflow, and padding preconditions before dereferencing input.

## 2.2 Section — C++ Shim Ownership and Exception Boundary

- [x] 2.2 Section - Implement the opaque handles with total exception containment and local cleanup.

  This section translates the C contract into official simdjson calls. Each
  allocation remains owned by the layer that created it until a successful
  handle transfer, and no C++ exception or standard-library type can cross the
  exported boundary.

  - [x] 2.2.1 Task - Implement parser and On-Demand document construction.

    The task builds a handle graph whose document retains all required C++ state
    while continuing to borrow the padded bytes that the later Zig resource will
    own.

    - [x] 2.2.1.1 Subtask - Construct the pinned official simdjson parser and On-Demand document through the chosen release's supported padded-input API.
    - [x] 2.2.1.2 Subtask - Ensure no handle stores a pointer to stack memory, temporary exception text, or any input capacity beyond the documented caller-owned padded allocation.
    - [x] 2.2.1.3 Subtask - Initialize every out parameter to a safe failure value before work begins and publish a handle only after all construction steps succeed.
    - [x] 2.2.1.4 Subtask - Preserve valid top-level scalars as successful documents rather than assuming the root must be an object or array.

  - [x] 2.2.2 Task - Contain exceptions and partial construction failures.

    The task makes every exported function a complete C++ exception boundary and
    proves that allocation or parser failure cannot leak a half-built handle.

    - [x] 2.2.2.1 Subtask - Wrap every exported C function in catch clauses that distinguish known simdjson errors, allocation failures, standard exceptions, and unknown exceptions.
    - [x] 2.2.2.2 Subtask - Translate failures to stable status values without returning exception text, object addresses, or source snippets.
    - [x] 2.2.2.3 Subtask - Use RAII or equivalent local guards so each allocation made before handle publication is released on every failure edge.
    - [x] 2.2.2.4 Subtask - Implement dependency-safe destruction of On-Demand state before parser state and make null destruction safe where the header promises it.

  - [x] 2.2.3 Task - Restrict the release symbol surface.

    The task prevents consumers and Zig code from binding to shim internals,
    mangled C++ names, simdjson symbols, or allocator implementation details.

    - [x] 2.2.3.1 Subtask - Compile the shim and vendored simdjson with hidden default visibility and explicitly export only the declared private C functions.
    - [x] 2.2.3.2 Subtask - Ensure the final NIF exposes only required NIF entry symbols plus the intended private C boundary for its linkage model.
    - [x] 2.2.3.3 Subtask - Add a platform-appropriate symbol-table inspection command whose expected allowlist is version-controlled.

## 2.3 Section — Native Failure Injection and Harness

- [x] 2.3 Section - Build test-only seams that can exercise every unsafe C++ edge independently of the BEAM.

  This section provides deterministic proof for paths that are otherwise hard to
  trigger, including allocation failure and unknown exceptions. All seams are
  compile-time gated out of release artifacts.

  - [x] 2.3.1 Task - Add deterministic native failure injection.

    The task lets tests select a failure after each construction step without
    changing production status mapping or allocation ownership.

    - [x] 2.3.1.1 Subtask - Add test-profile injection points before parser allocation, after parser allocation, during document construction, and before handle publication.
    - [x] 2.3.1.2 Subtask - Add test-profile injection for known simdjson failure, `std::bad_alloc`, another standard exception, and an unknown exception.
    - [x] 2.3.1.3 Subtask - Prove release builds contain neither injection entrypoints nor mutable failure controls through symbol and string inspection.

  - [x] 2.3.2 Task - Add an independent C ABI conformance harness.

    The task compiles as C against only the exported header and links to the
    private ABI artifact, ensuring the boundary is usable without C++ knowledge.

    - [x] 2.3.2.1 Subtask - Cover valid object, array, string, number, boolean, and null documents using correctly padded harness buffers.
    - [x] 2.3.2.2 Subtask - Cover empty, whitespace-only, truncated, malformed, invalid UTF-8, embedded-null, null-pointer, and invalid-length inputs.
    - [x] 2.3.2.3 Subtask - Cover every injected failure edge and assert output handles stay null and native allocations return to their pre-call counts.
    - [x] 2.3.2.4 Subtask - Destroy each successful handle once, pass null to null-safe destructors repeatedly, and verify the caller clears a consumed handle rather than reusing a dangling pointer.

## 2.4 Section — Phase 2 Integration Tests

- [ ] 2.4 Section - Prove ABI conformance, exception containment, cleanup, and symbol isolation together.

  This section closes the highest-risk language boundary before Zig is allowed to
  rely on it.

  - [ ] 2.4.1 Task - Run the independent C ABI acceptance matrix.

    The task executes `c_abi_conformance` and `cpp_exception_translation` across
    ordinary, failure-injection, and sanitizer profiles.

    - [ ] 2.4.1.1 Subtask - Compile the harness as C with warnings treated as errors and no C++ header available on its include path.
    - [ ] 2.4.1.2 Subtask - Run all valid, invalid-argument, malformed-input, exception-injection, allocation-failure, and destruction cases.
    - [ ] 2.4.1.3 Subtask - Run the native harness under AddressSanitizer and UndefinedBehaviorSanitizer and retain leak, overflow, use-after-free, and double-free results.
    - [ ] 2.4.1.4 Subtask - Assert every failure returns a documented status and that no exception terminates or unwinds through the C caller.

  - [ ] 2.4.2 Task - Run release boundary and regression checks.

    The task verifies the `release_symbol_surface` contract and confirms the
    completed shim still uses the reproducible build established in Phase 1.

    - [ ] 2.4.2.1 Subtask - Inspect release dynamic symbols against the version-controlled allowlist and reject C++ standard-library, shim-internal, and simdjson implementation exports.
    - [ ] 2.4.2.2 Subtask - Repeat the offline clean-checkout build with the real shim and native harness included.
    - [ ] 2.4.2.3 Subtask - Run the focused native tests, `mix test`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 2 complete.
