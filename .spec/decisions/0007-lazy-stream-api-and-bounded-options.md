---
id: simd_json.lazy_stream_api_and_bounded_options
status: accepted
date: 2026-08-31
affects:
  - simd_json.streaming_api
  - simd_json.stream_cursor
  - simd_json.stream_execution
---

# Lazy Stream API and Bounded Options

## Context

Milestone 3 exposes the first incremental public operation. Unlike
`SimdJson.select/2`, a stream may deliver many successful rows before malformed
input, a projection error, cancellation, or native failure becomes observable.
The API must therefore define when validation and native work begin, how a
mid-stream failure reaches an `Enumerable` consumer, and which bounds prevent
one request from constructing an arbitrarily large native reply.

The API must reuse Milestone 2's projection grammar and scalar conversion. A
second field language, row-by-row NIF API, or public raw cursor would create a
different safety and performance contract and undermine the accepted guided
projection engine.

## Decision

### Public operation and stream term

Milestone 3 adds one public operation:

```elixir
SimdJson.stream(source,
  path: ["customers"],
  fields: [id: ["id"], email: ["contact", "email"]],
  batch_size: 1_000,
  max_batch_bytes: 8_388_608
)
```

`source` is a JSON binary or a genuine `SimdJson.Document`. The function
returns an opaque `SimdJson.Stream.t()` implementing `Enumerable`; it does not
return a tagged result and does not parse, locate an array, reserve a document,
compile a native plan, or create a native cursor merely because `stream/2`
returned.

The stream captures the constructing PID as its owner and retains only the
validated normalized options plus the source term needed for a future
reduction. Its inspection is bounded and redacted: it may show configured
numeric limits and whether the source is binary or document-backed, but never
source bytes, field paths, output keys, owner PID, native state, or a document
identity.

Only the constructing process may reduce the stream. Sending the term does not
transfer authority. A binary-backed stream may be reduced again by its owner;
each reduction creates an independent lazy native graph. A document-backed
stream inherits the document's one-shot cursor contract, so a completed or
committed first reduction leaves later reductions with `:cursor_consumed`.

Milestone 3 does not expose `stream_batches/2`, a public cursor, a cursor
protocol, or a tagged-item stream. Native batching is an implementation and
backpressure boundary; `stream/2` yields projected row maps one at a time from
the current returned batch.

### Closed option grammar

Options are a proper keyword list containing each accepted key at most once.
Unknown keys, duplicate keys, missing required keys, improper lists, and values
outside the domains below raise `ArgumentError` synchronously before native
admission:

| Option | Contract |
| --- | --- |
| `:path` | Required proper list of UTF-8 binary object segments and unsigned 64-bit array indexes. The empty list selects a top-level array. |
| `:fields` | Required non-empty Milestone 2 projection, including exact output-key, path, duplicate-key, UTF-8, index, and scalar-leaf rules. |
| `:batch_size` | Optional positive integer; default `1_000`, maximum `10_000`. |
| `:max_batch_bytes` | Optional positive integer; default `8_388_608`, maximum `67_108_864`. |

The target path deliberately permits `[]` because top-level arrays are a core
ETL input. Every non-empty segment uses the exact Milestone 2 segment grammar;
there is no JSONPath, wildcard, filter, recursive descent, negative index, or
source-derived atom.

`max_batch_bytes` bounds the native encoded batch payload: row descriptors,
typed slots, copied selected string bytes, and other variable result storage
defined by the versioned ABI. It does not include the already-owned input
buffer. The engine checks addition and multiplication before allocation. If a
single projected row cannot fit, enumeration raises a
`SimdJson.Error` with reason `:batch_too_large`; the engine does not exceed the
limit merely to make progress.

These defaults are part of the initial public contract. Changing a default or
upper bound requires a reviewed contract update and renewed memory, scheduler,
and ETL qualification rather than tuning it from one benchmark result.

### Lazy reduction and row contract

Reduction starts native work. The start step validates source ownership and
lifecycle, opens an unpublished document for a binary or reserves the supplied
document, locates the target array once, compiles the per-row plan once, and
creates one cursor. The next step requests at most one bounded native batch.
All rows from that batch are consumed in the BEAM before another request may
start.

Each yielded item is one map with the exact atom or binary keys from `:fields`.
Values use the accepted Milestone 2 scalar contract: exact signed or unsigned
integers, finite floats, booleans, nil, and fresh copied binaries. Object or
array terminals remain unsupported and fail with `:incorrect_type`. No
selected string or completed row retains the input, parent document, cursor,
or a native view.

An empty array yields no items. Arrays smaller than, equal to, or larger than a
batch preserve source order. A full final batch carries terminal state in its
same native response; exact batch-boundary completion does not require an
extra request solely to discover end of array.

### Validation and operational errors

Caller-shape mistakes are synchronous `ArgumentError`s from `stream/2`:

- a source that is neither a binary nor a genuine document resource;
- an invalid, duplicate, unknown, or missing option;
- an invalid target path;
- an invalid field projection;
- an out-of-range batch limit.

Those errors perform no JSON parsing, document reservation, cursor creation,
or threaded submission. JSON, target path, row projection, ownership,
lifecycle, cancellation, allocation, batch-size, and native failures discovered
during reduction raise `SimdJson.Error` from the enumerable.

`SimdJson.Error` gains an optional non-negative `array_index`. A row-specific
failure reports the zero-based source-array index and the validated caller field
path when known. A target-location failure may report the target path with
`array_index: nil`. Metadata is copied only from validated options or bounded
numeric native status; it never contains discovered source text.

Each native batch is transactional. If row 25 of a requested batch fails, no
row from that in-flight batch is yielded, even if rows 0 through 24 converted
successfully. Rows from earlier completed batches have already been observed
and cannot be rolled back. Cleanup completes before the exception reaches the
consumer.

### Scope boundary

Milestone 3 exposes no public batch enumerable, raw cursor, manual `next`,
rewind, checkpoint, resume, ownership transfer, prefetch control, parallel
single-array traversal, callback execution in native code, optional/default
field semantics, container materialization, compiled-plan resource, JSONPath,
eager decode, worker-pool controls, or public telemetry.

## Consequences

Callers receive ordinary lazy `Enumerable` composition while native work stays
amortized by batches. Immediate option errors remain distinguishable from
failures that can occur only after rows have been consumed.

The row and encoded-byte limits make every reply bounded, but input memory is
still retained for the cursor lifetime and BEAM map overhead is not claimed to
equal the native encoded-byte count. Qualification must measure both native and
BEAM peaks rather than treating the byte option as a complete process-memory
limit.

Binary streams can be replayed only by reparsing in a new reduction. Document
streams remain one-shot. This difference follows explicit source ownership and
does not introduce an implicit document rewind.

## Alternatives Rejected

- **Return `{:ok, stream}`:** option construction has no operational failure
  once caller terms are valid, and wrapping the enumerable would add ceremony
  without representing lazy runtime errors.
- **Yield `{:ok, row}` and `{:error, reason}` together:** every consumer would
  need a tagged item type and could accidentally continue after a terminal
  cursor failure. A separate non-raising API may be proposed later.
- **Expose `stream_batches/2` immediately:** it doubles the public contract
  before real callers demonstrate a need for explicit batch boundaries.
- **Allow unbounded batch size or bytes:** one caller could create an
  arbitrarily large native message and BEAM allocation spike.
- **Make root arrays unreachable:** requiring a non-empty target path would
  exclude the most common array ETL shape for no safety benefit.
- **Validate JSON in `stream/2`:** that would violate laziness and surprise
  callers who construct but never consume a stream.
- **Return a public native cursor:** manual advancement exposes forward-only
  lifetime and correlation state without the deterministic cleanup of the
  enumerable protocol.

## Reopening Conditions

Revisit this decision when measurements justify explicit batch enumeration,
different public bounds, optional fields, container values, ownership transfer,
prefetch, or a non-raising stream. Any replacement must preserve construction
laziness, atom safety, bounded replies, exact source order, deterministic
cleanup, and an unambiguous terminal-error contract.
