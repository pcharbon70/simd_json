# SimdJson

An Elixir library for working with JSON using SIMD-accelerated parsing.

## Milestone 1 API

The current public runtime contract opens a binary as an opaque document and
closes it deterministically:

```elixir
case SimdJson.open(~s({"items": [1, 2, 3]})) do
  {:ok, document} ->
    # Later milestones add traversal; Milestone 1 deliberately exposes none.
    :ok = SimdJson.close(document)

  {:error, %SimdJson.Error{reason: reason}} ->
    {:error, reason}
end
```

`SimdJson.open/1` accepts binaries only. A document belongs to the process that
opened it, owner close is idempotent, and another process receives `:not_owner`
without learning whether the document is open or closed. Errors and document
inspection omit JSON content and native identity.

Milestone 1 exposes only `SimdJson.open/1`, `SimdJson.close/1`,
`SimdJson.Document`, and `SimdJson.Error`. Decode, projection, streaming,
cursors, ownership transfer, and raw native handles are intentionally absent.
The present threaded execution layer is a qualification runtime; production
admission control and a bounded worker pool arrive in Milestone 4.

Milestone 1 is active on its qualified Ubuntu 24.04 x86-64 target. Other
platforms remain experimental or unsupported until they pass the same package,
ABI, sanitizer, scheduler, lifecycle, and shutdown gates.

## Development

Install dependencies and run the test suite:

```sh
mix deps.get
mix test
```

The Milestone 1 architecture and acceptance boundary are documented in
[`docs/milestones/01-native-foundation.md`](docs/milestones/01-native-foundation.md).
Maintainers should also read the
[`Milestone 1 Native Foundation Operations`](docs/milestones/01-native-foundation-operations.md)
guide before changing a native dependency, ownership rule, or threaded
execution boundary. The
[`Milestone 1 Acceptance Record`](docs/milestones/01-native-foundation-acceptance.md)
identifies the qualified target, immutable evidence, and remaining non-goals.
