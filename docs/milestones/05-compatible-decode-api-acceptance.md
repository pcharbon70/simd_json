# Milestone 5 Compatible Decode API Acceptance Record

**Status:** Accepted on the qualified Ubuntu 24.04 x86-64 target when the
revision-bound Milestone 5 CI gate is green.

| Identity | Value |
| --- | --- |
| Qualification date | 2026-09-05 |
| Private ABI | v4, retaining ABI v1/v2/v3 symbols |
| Parser | vendored simdjson 4.6.9 |
| Compatibility baseline | Jason 1.4.5 |
| Complete command | `bash scripts/ci/qualify_milestone_5.sh` |
| CI artifact | `milestone-5-acceptance-<source revision>` |

The accepted public surface is `decode/1,2` and `decode!/1,2` for one complete
JSON binary and the empty option list. It materializes every JSON value, keeps
object keys as copied binaries, preserves array order, and uses the last value
for duplicate object keys. Jason 1.4.5 uses the first duplicate value; this is
the sole intentional value difference in the differential corpus.

Integers remain exact through the unsigned 64-bit range and otherwise return
`:number_out_of_range`; they are never silently rounded through a float.
Malformed input, invalid Unicode, non-finite numbers, trailing data, and a
UTF-8 byte-order mark are rejected. Tagged and raising APIs share one redacted
`SimdJson.Error` representation without source excerpts or partial results.

Decode uses the Milestone 4 bounded worker pool, cancellation checkpoints, an
explicit native stack, copied strings, and finite input, depth, container,
string, and estimated-output limits. Saturation returns `:busy`. Telemetry
reports bounded operation, capacity, queue, timing, and outcome data without
JSON content, keys, paths, PIDs, request references, or native addresses.

The benchmark evidence compares seven deterministic success and malformed
profiles with both decoders. It records p50/p95/p99/max latency, throughput,
reductions, process-memory change, garbage collection, exact-result checks,
and native baseline recovery. Results are contextual measurements, not a
universal superiority claim; eager decode necessarily allocates a complete
BEAM tree, so projection or streaming remains preferable when only part of a
large document is needed.

The scheduler profile runs four concurrent large decodes with an independent
2 ms heartbeat and requires p95 at most 50 ms, p99 at most 250 ms, and maximum
at most 500 ms. The immutable CI artifact binds native sanitizer, package,
symbol, compatibility, runtime, benchmark, documentation, test, traceability,
SpecLed, revision, tree, environment, fingerprint, and checksum evidence.

Acceptance excludes iodata, atomized keys, structs, custom decoders, decimal
modes, non-empty options, encoding, incremental socket/file parsing, and
selective container materialization. Any such surface needs a new contract and
qualification evidence.
