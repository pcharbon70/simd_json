# Changelog

All notable changes to SimdJson are documented here. The project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html); while the major
version is zero, backward-incompatible public changes increment the minor
version and compatible fixes increment the patch version.

## 0.1.0

First public release candidate.

### Added

- Binary-only `decode/1,2` and `decode!/1,2` for the documented safe subset of
  Jason 1.4.5 behavior.
- `select/2` for one-call extraction of multiple scalar paths without
  materializing the complete decoded BEAM tree.
- `stream/2` for lazy, row-count- and byte-bounded projection of root or nested
  JSON arrays with no native prefetch.
- Owner-bound `open/1` and idempotent `close/1` around opaque, one-shot native
  documents.
- A fixed native worker pool, finite non-blocking queue, cooperative
  cancellation, serialized stateful resources, and redacted `:telemetry`
  events.
- Source distribution of the pinned simdjson 4.6.9 snapshot, provenance,
  licenses, Zig/Zigler build inputs, and C ABI v4 implementation.

### Safety and qualification

- JSON keys never create atoms; decoded and selected strings are copied into
  independent BEAM binaries.
- C++ exceptions terminate at a fixed C ABI and all public errors use a closed,
  redacted `SimdJson.Error` vocabulary.
- Ordinary, sanitizer, symbol, scheduler-latency, cancellation, lifecycle,
  saturation, differential compatibility, clean-package, and offline native
  build gates cover the qualified target.
- Sparse `select/2` and batched `stream/2` both exercise the same 45,666,793-byte,
  one-million-row fixture.

### Known limitations

- Only Ubuntu 24.04 x86-64 with glibc 2.39, OTP 27.3, Elixir 1.18.4, Zig 0.16.0,
  Zigler 0.16.0, and the recorded simdjson CPU-dispatch paths is supported.
- The package ships source and compiles a NIF during installation; it provides
  no precompiled native artifacts.
- Every operation receives a complete resident binary. There is no incremental
  file, socket, device, or iodata input API and no zero-total-memory claim.
- `decode/2` accepts only `[]`; key atomization, structs, custom decoders,
  decimal modes, and other Jason options are not implemented.
- Decode uses the last duplicate object value while Jason 1.4.5 uses the first.
  Projection returns the first occurrence of a requested repeated object key.
- Projection and stream fields return scalars only. JSONPath, wildcards,
  filters, defaults, public compiled plans, and raw cursor/batch APIs are absent.
- Open documents are process-owned and forward-only. Once selection or stream
  traversal accesses the cursor, another traversal requires another document.
- Native admission is bounded. A full queue returns `:busy` rather than waiting
  or falling back to synchronous parsing.
- Integers outside the implemented signed/unsigned 64-bit native boundary fail
  with `:number_out_of_range`; values are never silently rounded through float.
- AVX-512/Ice Lake dispatch is disabled by the qualified Zig 0.16.0 build
  profile. macOS, Windows, musl, ARM, cross-compilation, and other unqualified
  environments remain experimental or unsupported.
