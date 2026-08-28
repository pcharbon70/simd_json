# Native Build Inputs and Support

<!-- covers: simd_json.package.native_build_tooling simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.clean_checkout_build -->

This directory contains every source and configuration input needed to build
the SimdJson NIF. [`manifest.exs`](./manifest.exs) is the authoritative,
machine-readable record. The prose below explains those pins and the process
for changing them.

The build must not discover a system simdjson installation, follow a mutable
source reference, or download source while compiling. A supported build uses
the repository vendor snapshot and fails closed when a manifest, target, or
toolchain guard does not match.

## Toolchain

| Input | Pinned or qualified value | Authority |
| --- | --- | --- |
| Elixir | `1.18.4`; project requirement `~> 1.18.4` | [Elixir releases](https://github.com/elixir-lang/elixir/releases/tag/v1.18.4) |
| Erlang/OTP | `27.3` | [OTP releases](https://github.com/erlang/otp/releases/tag/OTP-27.3) |
| Zigler | exact Hex release `0.16.0`; package SHA-256 recorded in the manifest and `mix.lock` | [Hex release](https://hex.pm/packages/zigler/0.16.0) and [threaded concurrency contract](https://hexdocs.pm/zigler/0.16.0/07-concurrency.html#threaded) |
| Zig | `0.16.0`; primary archive SHA-256 recorded in the manifest | [Zig 0.16.0 downloads](https://ziglang.org/download/0.16.0/) |
| C++ | Zig 0.16.0's bundled Clang/LLVM `21.1.0`, C++17, and bundled libc++ | [Zig C/C++ compiler](https://ziglang.org/learn/overview/#integration-with-c-libraries-without-ffibindings) |
| simdjson | official `v4.6.9`, commit and release-archive SHA-256 recorded in the manifest | [simdjson v4.6.9](https://github.com/simdjson/simdjson/releases/tag/v4.6.9) |

The repository-local [`.tool-versions`](../.tool-versions) pins the BEAM and Zig
developer tools. `mix zig.get --version 0.16.0` is also supported for CI or a
developer without asdf; that acquisition occurs before the offline build test,
and Zig's official archive digest remains mandatory.

Zigler compiles both C++ translation units with `zig c++`; no host `g++`,
system simdjson, or system C++ package is selected. The native profiles are
fixed in `manifest.exs`:

- development: debuggable C++ with hidden default visibility;
- release: optimized C++17 with hidden symbols and Zig `ReleaseSafe` behavior;
- sanitizer: AddressSanitizer plus UndefinedBehaviorSanitizer with frame
  pointers retained.

All profiles define `SIMDJSON_AVX512_ALLOWED=0`. Zig 0.16's bundled Clang 21
requires an additional internal `evex512` target feature that simdjson v4.6.9's
Ice Lake target region does not declare. Disabling only that optional upstream
implementation follows simdjson's documented build contract, preserves runtime
dispatch across the qualified `haswell`, `westmere`, and `fallback` paths, and
avoids globally enabling AVX-512 on baseline code. Re-enabling Ice Lake requires
a pinned toolchain or upstream release update and renewed CPU qualification.

## Target and CPU-Dispatch Matrix

| Target | Status for Milestone 1 | Runtime and dispatch policy |
| --- | --- | --- |
| `x86_64-linux-gnu`, Ubuntu 24.04, glibc 2.39 | Primary qualification target | OTP 27.3, Elixir 1.18.4, Zig 0.16.0 with bundled Clang 21.1.0/libc++; simdjson runtime dispatch may select `haswell`, `westmere`, or `fallback`; Ice Lake is deliberately disabled by the recorded profile. |
| `aarch64-linux-gnu` | Experimental | Compilation is not support; it must remain clearly experimental until native conformance, sanitizer, and scheduler evidence is recorded. |
| `x86_64-macos` and `aarch64-macos` | Experimental | No Milestone 1 support claim until equivalent Apple toolchain and scheduler qualification exists. |
| Windows, BSD, musl, and every unlisted triple | Unsupported | Build guards reject the target; no system library or generic artifact fallback is allowed. |

The required rejection is:

```text
unsupported native target <target>; see native/README.md#target-and-cpu-dispatch-matrix
```

The diagnostic must include the detected target triple. A later target becomes
supported only after its row records exact runtime/toolchain versions, allowed
simdjson implementations, clean-build proof, native conformance, sanitizer
results, and scheduler-latency evidence.

## Upgrade Procedure

Any change to Elixir, OTP, Zigler, Zig, the C++ compiler or runtime, build
profiles, simdjson, its patch set, or the target matrix invalidates native
qualification.

1. Select an immutable upstream release and record its authoritative URL,
   version or tag, commit where applicable, archive digest, and license.
2. Update `manifest.exs`, `.tool-versions`, `mix.exs`, and `mix.lock` together.
3. Reconstruct the vendor snapshot from its recorded archive and declared patch
   series; hidden edits are forbidden.
4. Run provenance, clean offline build, C ABI conformance, exported-symbol,
   sanitizer, CPU-dispatch, scheduler, shutdown, and package-content checks.
5. Update the target matrix and checked-in evidence only when all required jobs
   pass for the same source revision.

Changing a version number without regenerating those results is an incomplete
upgrade and must fail the dependency guard.

## Build and cache inputs

`mix compile` runs the target, toolchain, lockfile, vendor-digest, and patch
guards before Zigler invokes the C++ compiler. It then compiles
`native/src/build_smoke.cpp`, the real `native/src/simd_json_abi.cpp` shim, and
the vendored `simdjson.cpp` through Zigler and Zig. The native build never
contains a library search for simdjson.

`cache_inputs` in `manifest.exs` is the authoritative list used to derive a CI
native-cache key. The key also contains the runner OS/architecture, Mix
environment, and Zigler release mode. Any pin, flag, native source, vendored
file, license, or patch-series change therefore selects a new cache entry.

## Private C ABI

[`include/simd_json_abi.h`](./include/simd_json_abi.h) is the only parser
contract visible above C++. It is valid as C11 and C++17 and exposes opaque
parser/document handles, fixed-width values, stable numeric statuses, and
matching null-safe destructors. No simdjson or C++ layout is part of the
contract.

The caller supplies a non-null byte pointer, a logical JSON length, and the
allocation capacity. Capacity must cover the logical length plus the pinned 64
bytes of initialized simdjson padding without integer overflow. The caller
retains that allocation unchanged until the document is destroyed; padding is
never included in a reported logical byte offset. A parser must likewise
outlive every document opened through it, so cleanup order is document, parser,
then (in the later Zig resource) input allocation.

Every constructor initializes its out handle to null before doing work and
publishes ownership only on success. A non-null successful handle is consumed
exactly once by its matching destructor; callers clear that pointer after the
call. Passing null to either destructor is explicitly safe.

The stable native statuses are success, invalid JSON, invalid UTF-8,
unexpected EOF, out of memory, invalid argument, and internal failure. The
status also carries a raw simdjson numeric code when one exists and either a
logical byte offset or the explicit unavailable sentinel. Upstream error text
is never returned through this boundary.

[`src/simd_json_abi.cpp`](./src/simd_json_abi.cpp) is the single C++ exception
boundary. It recursively validates every object, array, and scalar through the
official On-Demand API, rewinds a successful document before publishing it,
and catches simdjson, allocation, standard, and unknown exceptions. Local smart
pointers retain partial allocations until a handle is published.

The release C ABI shared-artifact and Zigler NIF symbol surfaces are frozen in
[`symbols`](./symbols). The standalone ABI exports only its four declared C
functions. The current statically linked Zigler NIF needs only `nif_init`; its
C ABI and C++ implementation symbols remain local. Run
`scripts/native/verify_release_symbols.sh` after compiling the NIF to compare
both artifacts with their checked-in allowlists and to prove test-only failure
controls are absent.

## Zig document resource boundary

[`zig/document_resource.zig`](./zig/document_resource.zig) is instantiated with
declarations translated directly from the canonical C header. It checks the C
status width, signedness, alignment, field offsets, and distinct status values
at compile time, then adapts every status into a closed Zig union. Unknown C
status values are contained as internal failures. Raw parser and document
handles remain fields of the native state and have no BEAM encoder.

Zigler registers `DocumentResource` during both NIF load and upgrade. Its
payload contains the destructible native state plus the opening process PID;
the state reserves fields for the aligned padded allocation, logical length,
opaque C handles, lifecycle, generation, and admitted-operation count. Explicit
load, upgrade, unload, and destructor callbacks perform only bounded
bookkeeping. In Phase 3 no production constructor can put parsed state in the
resource, so its destructor never copies, parses, waits, or destroys large
native allocations on a normal scheduler. Phase 4 attaches deferred teardown.

The two fixture functions on the internal `SimdJson.Native.BuildSmoke` module
exist solely to prove resource registration and opacity. They create only the
fixed-size empty state and are not part of `SimdJson`'s public API. Future child
resources must use the private `retainParent` and `releaseParent` helpers, which
delegate to Zigler's BEAM resource keep/release operations.

### Owned padded input

`DocumentState.openOwned` is the only Milestone 1 parser-input constructor. It
checks the logical length against Zig `usize`, the fixed-width C ABI, and the
padding addition before allocating. The resulting allocation is aligned to the
manifest's 64-byte boundary, contains exactly one copy of the logical bytes,
and ends with all 64 required padding bytes initialized to zero. The C shim
receives the logical length and capacity as separate values; only the logical
length can appear in parser diagnostics.

There is no borrowed slice, BEAM-binary pointer, or zero-copy branch. Native
tests compare the source and owned allocations, overwrite the source after the
C++ On-Demand document is open, and revalidate the document through a guarded
test hook. Linux guard-page cases put the owned allocation's exact capacity at
the end of a readable page, with the following page inaccessible. The ordinary
and AddressSanitizer/UndefinedBehaviorSanitizer profiles exercise zero-length,
small, alignment-boundary, padding-boundary, malformed, and overflow cases.

## Native ABI conformance

The standalone harness in [`test/c_abi_conformance.c`](./test/c_abi_conformance.c)
is compiled by `zig cc` as strict C11 against only the production and test C
header directories. It then links a private archive containing the C++ shim and
vendored parser. This prevents the harness from relying on a C++ declaration,
layout, exception, or implementation symbol.

Test builds add one-shot failure points before and after parser allocation,
during document construction, and immediately before document publication.
Each point can raise a known simdjson exception, `std::bad_alloc`, another
standard exception, or a non-standard exception. Bounded live-handle counters
verify RAII cleanup without exposing addresses or input. These hooks are
guarded by `SIMD_JSON_TESTING`; release symbol and string checks prove that they
are absent from distributed artifacts.

Run the ordinary and sanitizer matrices with:

```text
scripts/native/run_c_abi_conformance.sh ordinary
scripts/native/run_c_abi_conformance.sh sanitizer
```

The sanitizer profile enables AddressSanitizer, UndefinedBehaviorSanitizer,
leak detection, frame pointers, and fail-fast runtime options.

The Zig ownership-state and resource-registration checks run with:

```text
scripts/native/run_zig_resource_tests.sh
scripts/native/run_zig_resource_tests.sh sanitizer
mix test test/native/document_resource_registration_test.exs
```
