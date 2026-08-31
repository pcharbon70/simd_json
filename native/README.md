# Native Build Inputs and Support

<!-- covers: simd_json.package.native_build_tooling simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.clean_checkout_build -->

This directory contains every source and configuration input needed to build
the SimdJson NIF. [`manifest.exs`](./manifest.exs) is the authoritative,
machine-readable record. The prose below explains those pins and the process
for changing them. The complete implemented ownership, runtime, public API, and
qualification contract is in the
[Milestone 1 operations guide](../docs/milestones/01-native-foundation-operations.md).
Projection-specific ABI v2, sanitizer, scheduler, lifecycle, and benchmark
procedures are in the
[Milestone 2 operations guide](../docs/milestones/02-projection-api-operations.md).

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

Zigler compiles every C++ translation unit with `zig c++`; no host `g++`,
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

| Target | Status for Milestones 1 and 2 | Runtime and dispatch policy |
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

### Executable qualification gate

The historically named
[`qualification/milestone_1.exs`](./qualification/milestone_1.exs) now binds
the cumulative Milestone 1 and 2 native foundation, supported target, and
deterministic stress seed to a SHA-256 fingerprint of every ABI-, runtime-,
harness-, workflow-, and evidence-relevant input listed under
`qualification_inputs` in the native manifest. Verify it with:

```console
mix simd_json.verify_qualification
```

Changing a tool pin, C header, compiler profile, target row, native source,
runtime bridge, test harness, or qualification command changes that
fingerprint and makes the command fail. Updating the recorded digest alone is
not acceptance: CI runs `scripts/ci/qualify_native_release.sh` from that same
revision and archives its package inventory, tool versions, target, runtime
dispatch, deterministic seed, ordinary and sanitizer logs, symbol inspection,
offline-build results, projection runtime profile, and frozen benchmark. The
isolated pin-change test in
`test/native/build_guard_test.exs` proves a stale record cannot pass.

The complete release-native gate is:

```console
SIMD_JSON_QUALIFICATION_DIR=_build/qualification/native \
  bash scripts/ci/qualify_native_release.sh
```

The complete clean-worktree Milestone 2 gate is:

```console
bash scripts/ci/qualify_milestone_2.sh
```

The supported matrix contains only Ubuntu 24.04 x86-64. Experimental rows are
not generic fallbacks: the build guard and qualification guard both reject
them until equivalent evidence is recorded.

## Build and cache inputs

`mix compile` runs the target, toolchain, lockfile, vendor-digest, and patch
guards before Zigler invokes the C++ compiler. It then compiles
`native/src/build_smoke.cpp`, the parser/document shim in
`native/src/simd_json_abi.cpp`, the projection plan and traversal engine in
`native/src/simd_json_projection.cpp`, and the vendored `simdjson.cpp` through
Zigler and Zig. The native build never contains a library search for simdjson.

`cache_inputs` in `manifest.exs` is the authoritative list used to derive a CI
native-cache key. The key also contains the runner OS/architecture, Mix
environment, and Zigler release mode. Any pin, flag, native source, vendored
file, license, or patch-series change therefore selects a new cache entry.

## Private C ABI

[`include/simd_json_abi.h`](./include/simd_json_abi.h) is the only native
contract visible above C++. It is valid as C11 and C++17 and exposes opaque
parser, document, and operation-scoped projection-plan handles, fixed-width
values, stable numeric statuses, and matching null-safe destructors. No
simdjson or C++ layout is part of the contract.

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

The unchanged 16-byte Milestone 1 status carries success, parse, allocation,
argument, and internal categories plus an optional raw simdjson code and
logical byte offset. ABI version 2 adds a distinct 24-byte projection status
with stable missing-field, bounds, type, numeric-range, consumed-cursor, and
cancellation categories plus an optional failing output slot. Dedicated
sentinels represent unavailable diagnostics; upstream error text is never
returned through this boundary.

[`src/simd_json_abi.cpp`](./src/simd_json_abi.cpp) validates every object,
array, and scalar through the official On-Demand API and rewinds a successful
document before publishing it. [`src/simd_json_projection.cpp`](./src/simd_json_projection.cpp)
validates normalized fixed-width descriptors before allocation and builds one
immutable, canonically ordered prefix-sharing trie. Its execution call consumes
one document-order walk, validates selected and skipped content, applies the
first repeated-key occurrence, advances array edges monotonically, and
publishes exact scalar slots only after complete success. Both document-open
validation and projection traversal reject nesting beyond the pinned 1,024
levels before another recursive descent. Every failure clears borrowed slot
views. The C++-only [`src/simd_json_native_internal.hpp`](./src/simd_json_native_internal.hpp)
provides hidden opaque-document access, one cursor claim, and a bounded
operation cancellation probe without expanding the C ABI. Each C++ boundary
catches simdjson, allocation, standard, and unknown exceptions. Local
ownership keeps partial allocations private until publication.

The release C ABI shared-artifact and Zigler NIF symbol surfaces are frozen in
[`symbols`](./symbols). The standalone ABI retains the four ABI v1
parser/document functions and adds only the ABI v2 plan constructor,
destructor, and single execution entry. The current statically linked Zigler
NIF needs only `nif_init`; its C ABI and C++ implementation symbols remain
local. Run
`scripts/native/verify_release_symbols.sh` after compiling the NIF to compare
both artifacts with their checked-in allowlists and to prove test-only failure
controls are absent.

`scripts/native/run_nif_sanitizer_tests.sh` performs an isolated NIF build in
which the C++ shim and simdjson translation units are instrumented with
AddressSanitizer and UndefinedBehaviorSanitizer. It runs the threaded operation
public API, and private binary/document projection corpora with fail-fast
runtimes preloaded. LeakSanitizer is
disabled only for the long-lived BEAM host process, whose allocator ownership
is outside the NIF; standalone C and Zig sanitizer harnesses keep leak
detection enabled, and BEAM tests require every bounded native gauge to return
to its recorded baseline.

## Zig document resource boundary

[`zig/document_resource.zig`](./zig/document_resource.zig) is instantiated with
declarations translated directly from the canonical C header. It checks the C
status width, signedness, alignment, field offsets, and distinct status values
at compile time, then adapts every status into a closed Zig union. Unknown C
status values are contained as internal failures. Raw parser and document
handles remain fields of the native state and have no BEAM encoder.

[`zig/projection_plan.zig`](./zig/projection_plan.zig) separately freezes every
ABI v2 layout, tag, status, and sentinel at compile time. It serializes only
validated numeric output/path slots and typed segments into temporary
descriptor arrays and one key-byte arena. The C++ constructor copies retained
keys before Zig releases those buffers, and the owned Zig plan wrapper provides
one idempotent destruction path. Caller output keys and raw BEAM terms are not
represented at this boundary.

Zigler registers `DocumentResource` during both NIF load and upgrade. Its
payload contains the destructible native state plus the opening process PID;
the state reserves fields for the aligned padded allocation, logical length,
opaque C handles, lifecycle, generation, and admitted-operation count. Explicit
load, upgrade, unload, and destructor callbacks perform only bounded
bookkeeping. Milestone 1's threaded constructor and deferred dispatcher own all
input-dependent creation and destruction, so the resource callback never
copies, parses, waits, or destroys large native allocations on a normal
scheduler.

Milestone 2 Phase 4 adds an independent projection state beside the unchanged
`open -> closing -> closed` lifecycle. An owner-first bounded entry atomically
reserves `fresh -> selecting`; a proven pre-worker rejection may roll it back,
while the worker commits `selecting -> consumed` immediately before its first
cursor access. The admitted-operation count interlocks that reservation with
close. The document, parser, padded input, and resource control remain retained
through plan execution, copied-string construction, join, and terminal release.
Binary projection uses the same state implementation in an unpublished
worker-local document graph.

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

### Lifecycle and cleanup

Published native state moves only from `open` to `closing` to `closed`. One
compare-and-exchange selects the cleanup owner and increments the generation;
every other close path observes `closing` or `closed`. Operation admission first
increments a bounded counter and then rechecks lifecycle and generation, so a
close can reject new work while preserving already-admitted work. The deferred
executor may release ownership only after that counter reaches zero, and a
second atomic guard makes completion exactly once.

Release order is fixed: document, parser, padded buffer, then resource-record
accounting. Each field is cleared as ownership ends. Construction remains
unpublished until all fields are ready, and every failure edge—after buffer,
parser, document, resource initialization, or immediately before
publication—uses the same reverse rollback. A successfully closed state cannot
be reopened because its invalidated generation is retained.

The BEAM destructor calls only the bounded close-detach transition. Parsed
state is handed to the callback-safe cleanup dispatcher described below; the
callback itself never performs input-dependent destruction.

## Threaded operation runtime

The internal `SimdJson.Native.ThreadedOperation` adapter now admits a binary by
copying its term—not its bytes—into a private NIF environment. That environment,
the caller PID, a native-generated BEAM reference, private operation kind,
module generation, cancellation flag, and terminal state live in a retained
operation resource. A `[]const u8` is never passed directly from the ordinary
admission environment to a Zigler worker because Zigler 0.16 may borrow that
binary without retaining it.

`threaded_document_open` is registered only with `concurrency: :threaded`. Its
worker inspects the retained private term, performs the aligned padded copy,
creates the C parser/document handles, and publishes the opaque resource only
after complete success. It checks cancellation before copy, immediately before
and after the C parse call, before resource publication, and before delivery.
Every failed or cancelled construction edge uses the same reverse rollback as
the native ownership tests. Parser failures return only the closed internal
status, optional native code, and optional logical byte offset.

`threaded_projection_execute` is registered through the same generated
threaded path. Admission retains the complete normalized projection and either
the binary source term or document resource in one operation environment. The
worker decodes one plan, calls the shared guided projection engine once, owns
every typed slot, and constructs one complete scalar map only after traversal
succeeds. Binary calls create and destroy an unpublished padded
input/parser/document graph inside that operation rather than chaining public
open and close calls. Document calls reserve and commit the single-use cursor
through the resource interlock above.

Projection result maps belong to the worker's private environment. The
resource-shaped `JoinCopiedTerm` Zigler adapter performs an explicit
`beam.copy` into the generated join environment; it does not publish an
adapter resource. Selected strings are fresh binaries before source teardown,
and any allocation, cancellation, stale-generation, or later delivery failure
discards the whole private environment. Test-only diagnostics expose only
threaded context, redacted phase durations, boundary counts, and aggregate
lifetime gauges.

`SimdJson.Native.OperationCoordinator` is the stable owner of each generated
Zigler thread resource. The original caller can die without destroying the
thread metadata: the coordinator marks the retained operation cancelled,
waits for the worker to reach a safe boundary and join, then suppresses or
discards its result. Completion messages include the private kind, unique
reference, generation, and worker identity; a mismatch cannot select a waiter.
Messages go to the coordinator rather than an unbounded caller mailbox.

Explicit, concurrent, and orphan-result cleanup run through the correlated
`threaded_document_cleanup` worker. All contenders join one lifecycle owner,
and accounting completes exactly once after reverse native destruction.

GC cleanup uses one cleanup-only native dispatcher. The resource destructor
clears its payload pointer, atomically detaches the fixed-size control block,
links that block into the intrusive dispatcher queue, and returns. It does not
allocate, wait, loop, or destroy parser state. Injected handoff rejection keeps
the same control block on a retained retry list; restoring admission moves it
to the active queue without a normal- or dirty-scheduler fallback.

Application stop first rejects coordinated admission, cancels and drains live
operations, and then advances the native generation. NIF unload independently
rejects native admission, drains and joins the dispatcher, and only then frees
module state. OTP 27.3 application stop/start and generation isolation are
exercised. Repeated in-process shared-object unload is not supported by that
test harness and remains explicitly unqualified in the pinned Zigler research
note. This runtime is a Milestone 1 qualification mechanism; production
admission control and the bounded parse pool remain in Milestone 4.

Milestone 2 projection reuses this same qualification runtime. Its integration
matrix forces out-of-order binary/document completion, submission rejection,
caller death at all six projection boundaries, close and shutdown cancellation,
GC handoff rejection/retry, and complete gauge recovery. A preliminary
concurrent 4 MiB profile checks continued BEAM heartbeats and exact threaded
projection worker entries. Phase 6 of Milestone 2 owns formal percentile,
normal/dirty utilization, and end-to-end benchmark qualification.

### Scheduler qualification

The formal profile runs concurrent 4 MiB valid and invalid inputs while an
independent BEAM heartbeat measures wake-up intervals and
`scheduler_wall_time_all` records normal, dirty CPU, and dirty I/O utilization.
It also injects parse and cleanup submission rejection and proves native worker
entry never occurs, so no alternative scheduler path can be selected. Exact
fixtures, percentile rules, thresholds, environment fields, and retained raw
samples are recorded in
[`phase_6_scheduler_qualification.md`](../.spec/research/phase_6_scheduler_qualification.md).
The earlier Phase 4 profile remains historical development evidence only.

Native test builds add aggregate counters for padded buffers, parser/document
handles, resource records, retained parents, admissions, object destruction,
and completed cleanup. Their snapshot and bounded quiescence poll contain no
pointers, allocation contents, or JSON. Failure controls and accounting are
selected only when the guarded C test header is present; release symbol and
string inspection proves they are absent from the NIF and standalone ABI.

## Native ABI conformance

The standalone harnesses in [`test/c_abi_conformance.c`](./test/c_abi_conformance.c),
[`test/projection_plan_conformance.c`](./test/projection_plan_conformance.c),
and [`test/projection_engine_conformance.c`](./test/projection_engine_conformance.c)
are compiled by `zig cc` as strict C11 against only the production, hidden-NIF,
and test C header directories. They then link a private archive containing both
C++ shims and the vendored parser. This prevents the harnesses from relying on
a C++ declaration, layout, exception, or implementation symbol.

Test builds add one-shot failure points before and after parser allocation,
during document construction, and immediately before document publication.
Each point can raise a known simdjson exception, `std::bad_alloc`, another
standard exception, or a non-standard exception. Bounded live-handle counters
verify RAII cleanup without exposing addresses or input. These hooks are
guarded by `SIMD_JSON_TESTING`; release symbol and string checks prove that they
are absent from distributed artifacts.

Projection test builds additionally inject every constructor checkpoint and
every bounded traversal/skip/slot checkpoint. They report only live plan, node,
copied-key-byte, topology, duration, visit, and filled-slot counts. The C and
Zig matrices cover shared and identical paths, canonical edge ordering, exact
scalar types, malformed selected/unselected/trailing content, repeated keys,
missing/index/type/range failures, pre/post-cursor cancellation, the depth
bound, Unicode and escaped paths, large skipped containers, exact-padding guard
pages, borrowed strings, serializer/allocation failures, every exception class,
and repeated null/idempotent caller cleanup.

Run the ordinary and sanitizer matrices with:

```text
scripts/native/run_c_abi_conformance.sh ordinary
scripts/native/run_c_abi_conformance.sh sanitizer
```

The sanitizer profile enables AddressSanitizer, UndefinedBehaviorSanitizer,
leak detection, frame pointers, and fail-fast runtime options.

The Zig ownership-state and resource-registration checks run with:

```text
scripts/native/run_zig_resource_tests.sh ordinary
scripts/native/run_zig_resource_tests.sh sanitizer
mix test test/native/document_resource_registration_test.exs
```
