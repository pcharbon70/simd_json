# SimdJson

An Elixir library for extracting selected JSON scalars with SIMD-accelerated
parsing.

## Public API

Select several nested scalar values from a binary in one operation:

```elixir
json =
  ~s({"customer":{"id":1234,"name":"Acme"},"orders":[{"sku":"ABC-123"}]})

SimdJson.select(json, [
  {:id, ["customer", "id"]},
  {"name", ["customer", "name"]},
  {:first_sku, ["orders", 0, "sku"]}
])
# => {:ok, %{"name" => "Acme", id: 1234, first_sku: "ABC-123"}}
```

Output keys are the exact existing atoms or binaries supplied by the caller;
JSON keys are never atomized. Paths contain UTF-8 binary object keys and
unsigned 64-bit array indexes. Only string, integer, float, boolean, and null
leaves are returned. Selecting an object or array yields `:incorrect_type`
without building that container.

The complete source is validated even after all requested values have been
found. The first occurrence of a repeated requested object key supplies its
value. Every selected string is copied into a fresh result binary, so a small
result does not retain a large source. Any parse, path, type, range,
allocation, or cancellation failure returns one `SimdJson.Error` and no
partial map.

For deterministic native lifetime, open a document and select from it once:

```elixir
case SimdJson.open(~s({"items": [1, 2, 3], "ready": true})) do
  {:ok, document} ->
    {:ok, %{item: 2, ready: true}} =
      SimdJson.select(document, item: ["items", 1], ready: ["ready"])

    :ok = SimdJson.close(document)

  {:error, %SimdJson.Error{reason: reason}} ->
    {:error, reason}
end
```

`SimdJson.open/1` accepts binaries only. A document belongs to the process that
opened it, owner close is idempotent, and another process receives `:not_owner`
without learning whether the document is open or closed. Once a selection
worker accesses its forward-only cursor, success and failure both consume the
document. Another projection requires another document, or another
`SimdJson.select/2` call with the binary; there is no transparent rewind,
reparse, or reusable public compiled plan.

Invalid projection grammar returns `:invalid_projection` before JSON parsing or
document reservation. A source that is neither a binary nor a genuine
`SimdJson.Document` raises `ArgumentError`. Errors and document inspection omit
JSON content, caller path contents, native identity, timing, generation, and
exception text.

The public root operations are `open/1`, `select/2`, and `close/1`. There is no
bang variant, eager decode, JSONPath, wildcard/filter/default policy,
container materialization, streaming cursor, ownership transfer, raw native
handle, or public diagnostic API. The present threaded execution layer remains
a pre-production qualification runtime; production admission control and a
bounded worker pool arrive in Milestone 4.

Milestones 1 and 2 are active on the qualified Ubuntu 24.04 x86-64 target.
Other platforms remain experimental or unsupported until they pass the same
package, ABI, sanitizer, scheduler, lifecycle, benchmark, and shutdown gates.

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
The projection grammar, traversal, and lifecycle are documented in
[`docs/milestones/02-projection-api.md`](docs/milestones/02-projection-api.md).
Maintainers should also read the
[`Milestone 2 Projection API Operations`](docs/milestones/02-projection-api-operations.md)
guide and
[`Milestone 2 Projection API Acceptance Record`](docs/milestones/02-projection-api-acceptance.md)
before changing the projection or qualification boundary.
