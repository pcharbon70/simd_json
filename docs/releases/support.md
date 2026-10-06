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
| Precompiled NIF | SHA-256-pinned `v0.1.0` GitHub release asset |
| Source-build Zig | 0.16.0; maintainer/audit path only |
| Source-build Zigler | 0.16.0; optional and not resolved for ordinary consumers |
| simdjson | Vendored 5.0.1 |
| Runtime dispatch | `haswell`, `westmere`, or `fallback` as selected by simdjson |

Other Linux distributions, libc implementations, architectures, operating
systems, BEAM versions, Elixir versions, toolchains, and CPU dispatch paths are
experimental or unsupported until they pass the same complete qualification.
In particular, the first release does not claim support for macOS, Windows,
musl, ARM, or cross-compilation.

The first release uses a checksummed precompiled NIF on this one target.
Ordinary consumers need neither Zig nor Zigler. The Hex archive still contains
the complete verified native and vendored simdjson sources so maintainers can
reproduce the artifact through the explicit qualified source-build path.

## Input and memory boundary

Binary operations accept a complete resident JSON binary. `open_file/1`,
`select_file/2`, and `stream_file/2` instead pass only a validated path through
the BEAM boundary and retain a simdjson-owned memory map for the native
operation lifetime.

`select/2` and `stream/2` avoid constructing a complete decoded BEAM tree.
Projection returns only requested scalar values, while streaming exposes one
bounded row batch at a time. Their qualification includes the same 45,666,793
byte, one-million-row source. Native parsing still owns or retains bounded
operation state and, depending on the operation, an input copy for safety.

`decode/1,2` intentionally materializes the complete result tree and should not
be described as bounded-memory streaming. Prefer projection or streaming when
only part of a large document is required.

`select_file/2` avoids both the BEAM source binary and the padded native source
copy, but simdjson structural indexes may still scale with input size.
`stream_file/2` is the bounded-parser-memory path: it supports explicit
top-level `:json_array`, `:ndjson`, `:json_sequence`, and `:comma_delimited_json`
formats, uses a fixed 1 MiB parser window, applies bounded result batches, and
stops immediately on early halt. The source must remain immutable. Nested-path
file streaming, sockets, devices, and iodata are not supported.

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
