---
id: simd_json.native_file_backed_input_and_batched_streaming
status: accepted
date: 2026-09-29
affects:
  - simd_json.file_input
  - simd_json.document_resource
  - simd_json.document_api
  - simd_json.projection_api
  - simd_json.streaming_api
  - simd_json.stream_cursor
  - simd_json.native_build_and_abi
  - simd_json.release
---

# Native File-Backed Input and Batched Streaming

## Context

The pre-release implementation accepts complete JSON binaries. Binary
projection and streaming avoid a complete decoded BEAM tree, but the caller
must first make the complete source resident in the BEAM and the native
document path creates a padded source copy. That design contradicts the
library's principal large-document goal and leaves simdjson's file mapping and
batched document-stream facilities unused.

The pinned simdjson 5.0.1 release provides `padded_memory_map` plus On-Demand
`iterate_many` formats for whitespace-delimited documents, JSON sequences,
comma-delimited documents, and a top-level comma-delimited array. These are the
authoritative source ownership and batching mechanisms for the supported
file-backed surface.

## Decision

### Product priority and source classes

Native file-backed processing is the principal large-document capability.
`open_file/1`, `select_file/2`, and `stream_file/2` pass only a validated path
through the BEAM boundary; no public or private step may call `File.read/1`,
construct a BEAM binary containing the complete source, or create a padded
native copy of the complete file.

Existing `open/1`, `select/2`, `stream/2`, and `decode/1,2` remain explicit
in-memory conveniences for sources already held as binaries. They retain the
accepted padded-copy and decoded-result contracts and must not be described as
file streaming or bounded source-memory operations.

This decision narrowly supersedes the complete-binary-only and zero-copy
exclusions in decisions 0002, 0007, 0008, and 0018 for the new file-backed
surface. It does not permit borrowing an ordinary BEAM binary, weaken padding
safety, or change binary-operation ownership.

### Memory-mapped documents and selection

On the qualified POSIX target, a pool worker opens the path through
`simdjson::padded_memory_map`. One opaque native owner retains the mapping,
parser, On-Demand state, owner PID, application generation, lifecycle, and
cleanup synchronization. Mapping construction, parsing, projection, and
teardown remain off ordinary schedulers.

`select_file/2` reuses the existing projection grammar and engine and copies
only selected scalar strings into result binaries. It avoids a complete source
copy but may allocate simdjson structural indexes proportional to the mapped
document. Documentation and evidence must distinguish this zero-copy source
property from the bounded parser working set of document-stream iteration.

The file must remain unchanged for the complete native lifetime, as required
by simdjson's memory-map contract. The implementation rejects observed
identity, size, or metadata changes at safe boundaries, but documentation must
not claim protection against an undetectable concurrent writer. Callers that
cannot guarantee immutability must provide an immutable snapshot path.

### Batched file streams

`stream_file/2` is lazy and owner-bound. Its closed options require `:format`
and `:fields`, with the existing optional row and encoded-byte bounds. Supported
formats are `:json_array`, `:ndjson`, `:json_sequence`, and
`:comma_delimited`. File streaming has no nested `:path`: a nested target would
require the whole-document structural scan this API exists to avoid.

At first demand, C++ creates one simdjson On-Demand document stream over the
memory map. `:json_array` uses `comma_delimited_array`; the other values map to
their corresponding simdjson stream formats. The cursor reuses one compiled
projection plan, copies selected strings before advancing, and returns the same
transactional row-and-byte-bounded batches as the in-memory stream. It performs
no NIF call per row or field and stops iteration immediately on early halt.

Where the supported OS contract permits, fully consumed page ranges are
advised away only after every borrowed view in the completed batch has been
copied. Such advice is an optimization and is not the correctness boundary.

### Qualification and release gate

Qualification creates large fixtures incrementally from a path, never through
one retained test-VM binary. It records peak RSS, mapping/source-copy
accounting, parser working memory, batch advancement, early halt, sanitizer
results, and cleanup baselines across progressively larger sources. File-stream
memory must remain within an approved fixed-plus-batch envelope rather than
grow approximately with total source size.

All Phase 6 candidate evidence, artifact checksums, qualification fingerprints,
and GO/NO_GO review preceding this decision are invalid. Tagging, GitHub release
creation, and Hex publication remain prohibited until the complete corrected
surface passes the full supported-target and packaged-consumer matrix.

## Consequences

The private ABI, NIF checksum, package candidate, public surface, documentation,
and release qualification all change. The first release remains restricted to
the qualified Linux glibc target where simdjson memory mapping is exercised.

File-backed selection eliminates duplicate source residency but is not itself
a fixed-memory parser. Batched file streaming is the operation that makes the
bounded-parser-memory claim for supported top-level formats. Eager decode still
materializes the complete result and receives no bounded-memory claim.

## Alternatives Rejected

- **Keep binary-only APIs and improve wording:** accurate wording does not fix
  the release-blocking product mismatch.
- **Call `File.read/1` inside an Elixir convenience wrapper:** this merely hides
  complete BEAM residency and does not delegate ownership to simdjson.
- **Copy the file into one padded native buffer:** this avoids BEAM residency
  but still scales source allocation with file size and bypasses memory mapping.
- **Use the existing single-document array cursor for files:** its initial
  document parse structurally scans the complete input; it is not the batched
  document-stream path.
- **Promise nested file-array streaming:** simdjson's bounded document-stream
  formats operate at the top level; silently scanning a complete enclosing
  document would make the memory claim false.

## Reopening Conditions

Additional targets require their own mapping, mutation, sanitizer, lifecycle,
and RSS evidence. Nested file targets require a proven simdjson-supported or
equivalently bounded native mechanism and a new decision. Socket or generic IO
streaming is not authorized by this decision.
