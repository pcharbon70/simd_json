# Zigler 0.16 Threaded Execution Qualification

<!-- covers: simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.layered_boundary simd_json.native_execution.bounded_nif_entry simd_json.native_execution.threaded_cleanup simd_json.native_execution.preproduction_boundary simd_json.package.documentation_layout -->

This note records the exact concurrency boundary accepted for Milestone 1. It
is implementation research, not a replacement for the current-truth contract
in [`native_execution.spec.md`](../specs/native_execution.spec.md) or the
accepted execution decision in
[`0003-off-scheduler-native-execution.md`](../decisions/0003-off-scheduler-native-execution.md).

The qualified sources are Zigler `0.16.0` from the immutable `mix.lock` entry,
the generated threaded template, and the BEAM support modules shipped in that
package:

- `deps/zigler/lib/zig/templates/threaded.zig.eex`;
- `deps/zigler/priv/beam/threads.zig`;
- `deps/zigler/priv/beam/processes.zig`;
- `deps/zigler/priv/beam/get.zig`;
- `deps/zigler/priv/beam/resource.zig`;
- the pinned [Zigler threaded-concurrency documentation](https://hexdocs.pm/zigler/0.16.0/07-concurrency.html#threaded).

## Verified generated flow

For a NIF declared with `concurrency: :threaded`, Zigler generates two ordinary
NIF table entries and an Elixir receive wrapper:

1. the launch entry builds a payload, allocates a private environment, creates
   a typed thread resource, starts an OS thread, and returns that opaque
   resource term;
2. the worker sets `beam.context.mode` to `threaded`, runs the Zig function,
   stores its result, and sends `{:done, thread_resource}` or
   `{:error, thread_resource}` to its spawning process;
3. the Elixir wrapper matches the exact resource term and invokes the join
   entry only after the completion message;
4. join reclaims the OS thread and constructs the bounded return value on the
   calling scheduler.

The generated thread resource is unforgeable and function-specific, but it is
not sufficient as the library operation identity. SimdJson therefore pairs it
with a native operation record containing a separately generated BEAM
reference, a private operation kind, and a NIF generation. The Elixir adapter
must match all three before delivery.

## Context and API matrix

| Context | Environment and identity | Permitted work in SimdJson | Prohibited work |
| --- | --- | --- | --- |
| Ordinary admission NIF | Process-bound call environment; `beam.self` identifies the caller; argument terms live only for the call | Binary shape inspection, private-environment allocation, reference creation, term/resource retention, atomic state changes, and thread submission | Input-sized copying, padding, parsing, waits, native document destruction, or large term construction |
| Zigler worker | Allocated private environment; `beam.self` returns the process that launched the worker; `beam.context.mode == .threaded` | Inspect retained input in its private environment, allocate the owned padded copy, call the C ABI, check cancellation, and produce bounded status/resource metadata | Dereference a term or borrowed binary slice from the expired admission environment |
| Completion/join | Ordinary NIF table entry invoked only after the worker's exact completion resource is received | Join an already-finished worker, copy bounded metadata/resource terms into the caller environment, and release the thread payload | Input-dependent parsing, waits for unfinished work, or unbounded result materialization |
| Resource destructor/down callback | Callback environment; no process-bound `beam.self` | Atomic cancellation, lifecycle detach, and bounded handoff to an already-running cleanup dispatcher | Launching a Zigler threaded NIF, waiting for a worker, parsing, or destroying input-sized native state |
| Load/upgrade/unload callback | Callback environment and module private data | Initialize a fresh generation, reject admission, signal shutdown, and drain the cleanup dispatcher | Accept new work after shutdown starts or release code while native work can re-enter it |

Additional ownership rules follow directly from the pinned implementation:

- `[]const u8` payload conversion can borrow the inspected BEAM binary. It does
  not retain that binary after launch, so SimdJson never passes caller input to
  a threaded function as a borrowed slice.
- Admission copies the binary *term* into an allocated private environment.
  This retains the ref-counted binary without copying its bytes. The worker is
  the only context that inspects that retained term and copies the bytes into
  the aligned, padded native allocation.
- A resource parameter is kept during payload construction and released during
  worker cleanup by default. Every operation record and document it can
  dereference therefore remains retained through the generated join.
- Terms owned by a private environment are copied into the destination
  environment before delivery. No private-environment term escapes by raw
  value.
- Worker messages use `enif_send` with the allocated environment. Callback
  handoff uses the callback environment and bounded native queue metadata.

## Pinned limitations and reconciliation

Two Zigler `0.16.0` behaviors prevent the generated threaded resource from
being the complete teardown protocol:

1. its destructor attempts to join a still-running worker for only 750
   microseconds; if the worker does not reach a cancellation boundary quickly,
   Zigler documents that thread metadata can leak;
2. `beam.Thread.launch` accepts synchronous or dirty contexts, not resource
   callback context, so a document destructor cannot submit a generated
   threaded cleanup operation directly.

SimdJson contains those limitations as follows:

- a library-owned coordinator process, rather than the requesting caller,
  owns each generated threaded call through completion and join;
- caller death marks the separate operation record cancelled, suppresses
  delivery, and lets the coordinator finish or discard the native result;
- explicit cleanup may use a correlated Zigler worker because the coordinator
  remains its stable owner;
- GC and orphan cleanup use one module-owned, cleanup-only native dispatcher.
  A destructor transfers an intrusive cleanup record to that already-running
  dispatcher with bounded work and returns immediately;
- unload rejects admission, waits for coordinator quiescence, drains the
  cleanup dispatcher, and only then releases module state.

The cleanup dispatcher is not a parse executor, has no public admission queue,
and does not claim the backpressure or telemetry guarantees assigned to the
Milestone 4 worker pool. There is no normal- or dirty-scheduler fallback.

## Qualification boundary

This mechanism is accepted only for the Milestone 1 native vertical slice. A
Zigler upgrade reopens this qualification because payload retention, callback
legality, cancellation timing, join behavior, and environment rules are all
version-sensitive. Milestone 4 replaces per-operation Zigler OS threads with
the bounded production worker pool while retaining the operation identity,
cancellation, ownership, and delivery rules proved here.
