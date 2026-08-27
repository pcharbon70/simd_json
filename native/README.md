# Native Build Inputs and Support

<!-- covers: simd_json.package.native_build_tooling simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.target_qualification -->

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
| C++ | GCC `13.3.0`, C++17, `libstdc++.so.6` | [GCC 13 documentation](https://gcc.gnu.org/onlinedocs/gcc-13.3.0/gcc/) |
| simdjson | official `v4.6.9`, commit and release-archive SHA-256 recorded in the manifest | [simdjson v4.6.9](https://github.com/simdjson/simdjson/releases/tag/v4.6.9) |

The repository-local [`.tool-versions`](../.tool-versions) pins the BEAM and Zig
developer tools. `mix zig.get --version 0.16.0` is also supported for CI or a
developer without asdf; that acquisition occurs before the offline build test,
and Zig's official archive digest remains mandatory.

The native profiles are fixed in `manifest.exs`:

- development: debuggable C++ with hidden default visibility;
- release: optimized C++17 with hidden symbols and Zig `ReleaseSafe` behavior;
- sanitizer: AddressSanitizer plus UndefinedBehaviorSanitizer with frame
  pointers retained.

## Target and CPU-Dispatch Matrix

| Target | Status for Milestone 1 | Runtime and dispatch policy |
| --- | --- | --- |
| `x86_64-linux-gnu`, Ubuntu 24.04, glibc 2.39 | Primary qualification target | OTP 27.3, Elixir 1.18.4, GCC/libstdc++ 13.3.0; simdjson runtime dispatch may select `icelake`, `haswell`, `westmere`, or `fallback`. |
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
