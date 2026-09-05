# Supported Environments and Compatibility

SimdJson 0.1.x has one qualified target. “Supported” means the exact
environment has passed package reconstruction, ABI and symbol checks,
ordinary and sanitizer native tests, scheduler and lifecycle qualification,
large-input profiles, and the complete public test suite.

## Qualified target

| Component | Qualified value |
| --- | --- |
| Operating system | Ubuntu 24.04 LTS |
| ABI and architecture | glibc 2.39, `x86_64-linux-gnu` |
| BEAM | OTP 27.3 |
| Elixir | 1.18.4 |
| Zig | 0.16.0 |
| Zigler | 0.16.0 |
| simdjson | Vendored 4.6.9 |
| Runtime dispatch | `haswell`, `westmere`, or `fallback` as selected by simdjson |

Other Linux distributions, libc implementations, architectures, operating
systems, BEAM versions, Elixir versions, toolchains, and CPU dispatch paths are
experimental or unsupported until they pass the same complete qualification.
In particular, the first release does not claim support for macOS, Windows,
musl, ARM, or cross-compilation.

The first release ships native source, not precompiled NIF binaries. A consumer
must satisfy the pinned Zig/Zigler and platform build requirements during Mix
compilation. The package contains the verified simdjson source needed for an
offline native build after dependencies and toolchains are available.

## Input and memory boundary

All public operations accept a complete JSON binary. The encoded source is
therefore already resident in memory; this library does not incrementally read
from a file, socket, or device.

`select/2` and `stream/2` avoid constructing a complete decoded BEAM tree.
Projection returns only requested scalar values, while streaming exposes one
bounded row batch at a time. Their qualification includes the same 45,666,793
byte, one-million-row source. Native parsing still owns or retains bounded
operation state and, depending on the operation, an input copy for safety.

`decode/1,2` intentionally materializes the complete result tree and should not
be described as bounded-memory streaming. Prefer projection or streaming when
only part of a large document is required.

## Public compatibility boundary

- Inputs are binaries; iodata is not accepted.
- Decode accepts only the empty option list in the first compatibility release.
- JSON object keys remain binaries and input never creates atoms.
- Decode uses the last duplicate object value; Jason 1.4.5 uses the first.
- Integers are exact through the unsigned 64-bit range or fail with
  `:number_out_of_range`; silent floating-point rounding is forbidden.
- Non-finite numbers, malformed Unicode, trailing data, and a UTF-8 byte-order
  mark are rejected.
- Native jobs use a finite worker pool and queue; saturation returns `:busy`.
- Errors and telemetry are redacted and contain no JSON excerpts.

See the [Milestone 5 acceptance record](../milestones/05-compatible-decode-api-acceptance.md)
for eager-decode evidence, the [Milestone 3 acceptance record](../milestones/03-batched-array-streaming-acceptance.md)
for streaming evidence, and the [Milestone 2 acceptance record](../milestones/02-projection-api-acceptance.md)
for projection evidence.

## Adding a supported target

A target becomes supported only after a reviewed change records its complete
toolchain and ABI identity and passes, on that target:

1. clean and repeated source-package builds with vendored-source verification;
2. ordinary, ASan, UBSan, race, symbol, exception, and failure-injection gates;
3. scheduler latency, cancellation, shutdown, ownership, and native-baseline checks;
4. projection, streaming, eager-decode, compatibility, and large-input profiles;
5. fresh Hex-archive consumer compilation with no repository-relative inputs;
6. strict documentation, the full test suite, SpecLed traceability, and an
   immutable checksummed CI evidence bundle.

Passing a smaller smoke test may establish experimental compatibility but does
not inherit the supported-target claim.
