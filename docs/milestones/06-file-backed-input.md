# Milestone 6 — Native File-Backed Input

Milestone 6 Phase 7 corrects the original resident-binary release design.
Large-file processing now passes only a path through the BEAM boundary and
keeps mapping, parser, traversal, projection, and batching inside the native
ownership graph.

## Choose the operation by memory contract

| Operation | Source ownership | Memory contract |
| --- | --- | --- |
| `open_file/1` | simdjson `padded_memory_map` retained by the document | No complete BEAM or padded native source copy |
| `select_file/2` | Mapping and On-Demand document closed after selection | Source bytes are zero-copy; structural indexes may scale with input size |
| `stream_file/2` | Mapping, parser, `document_stream`, plan, and cursor retained until halt/completion | Fixed 1 MiB parser window plus bounded result batch and native overhead |

Binary APIs remain useful for data already present as a binary. Calling
`File.read/1` before a binary API defeats the large-file design.

## File streaming

`stream_file/2` requires `:fields` and an explicit top-level format:

- `:json_array` for one root array;
- `:ndjson` for whitespace-delimited JSON documents;
- `:json_sequence` for RFC 7464 record-separator framing;
- `:comma_delimited` for top-level comma-separated documents.

There is deliberately no file-stream `:path` option. Locating an arbitrary
nested array would require a whole-document structural scan and would not have
the promised document-stream memory behavior.

Each demand submits one job to the fixed native worker pool. C++ advances
simdjson once per row inside that job, applies one shared compiled projection,
copies selected strings into bounded batch storage, and crosses back into the
BEAM once for the complete batch. Early halt destroys the cursor immediately.
On Linux, fully consumed mapping pages are advised away at safe batch
boundaries. The file must remain immutable; observable metadata changes fail
closed with `:file_changed`.

## Qualification result

The Phase 7 qualification incrementally generates 1, 8, and 32 MiB root-array
and NDJSON fixtures without retaining their contents in the test VM. With a
1 MiB parser window, 256-row result limit, and 1 MiB result-byte limit, every
sample stayed below the fixed 96 MiB RSS-increase ceiling. The recorded 32 MiB
samples increased peak RSS by about 12.3 MiB for the root array and 2.2 MiB for
NDJSON on the qualified host. An independent early-halt proof observed exactly
one setup job and one requested batch even with a malformed undemanded tail.

The machine-readable evidence is
`_build/qualification/file-input/file-stream-memory.json`. It is generated
evidence rather than a packaged runtime input.

## Boundaries

File streaming is not random access, a reusable cursor, or a general JSONPath
engine. It does not accept sockets, devices, or iodata. Individual documents
must fit the fixed simdjson parser window; result rows must fit the configured
result-byte limit. Eager decode still materializes the complete BEAM value, and
file selection does not claim bounded structural-index memory.
