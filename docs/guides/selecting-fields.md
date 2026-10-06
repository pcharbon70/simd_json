# Selecting Fields

<!-- covers: simd_json.package.documentation_layout -->

Projection extracts several named scalar values in one native traversal and
returns only those values to the BEAM.

```elixir
json =
  ~s({"customer":{"id":1234,"name":"Acme"},"orders":[{"sku":"ABC-123"}]})

{:ok, result} =
  SimdJson.select(json, [
    {:id, ["customer", "id"]},
    {"name", ["customer", "name"]},
    {:first_sku, ["orders", 0, "sku"]}
  ])

%{"name" => "Acme", id: 1234, first_sku: "ABC-123"} = result
```

Output keys are the exact atoms or binaries supplied by the caller. JSON keys
are never converted to atoms. Paths contain UTF-8 binary object keys and
non-negative array indexes.

Selected leaves may be strings, integers, floats, booleans, or null. Selecting
an object or array returns `:incorrect_type`; projection does not materialize
containers. Every selected string is copied into a fresh binary, so a small
result does not retain a large input binary.

## Select from a file

`select_file/2` passes a path through the BEAM boundary and lets the native
layer map and parse the source:

```elixir
{:ok, %{account_id: 7}} =
  SimdJson.select_file("account.json", account_id: ["account", "id"])
```

The source file must remain immutable for the operation. This avoids a
`File.read/1` copy, although simdjson may still retain structural indexes that
scale with input size. Use `stream_file/2` when bounded parser memory is the
primary requirement.

## Explicit document lifetime

Open a document when the caller needs deterministic native cleanup:

```elixir
with {:ok, document} <- SimdJson.open(json),
     {:ok, result} <- SimdJson.select(document, id: ["customer", "id"]) do
  :ok = SimdJson.close(document)
  {:ok, result}
end
```

A document belongs to the process that opened it. Selection is forward-only
and one-shot: success or failure consumes the document after cursor access
begins. Open another document for another projection. Owner `close/1` is
idempotent; another process receives `:not_owner`.

The complete source is validated even after all requested values are found.
For repeated requested object keys, the first occurrence supplies the selected
value. Failures return no partial map.
