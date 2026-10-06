# 03 — Selecting Fields

<!-- covers: simd_json.package.documentation_layout -->

Often you do not need to turn a complete JSON document into an Elixir tree.
This tutorial shows how to extract a small set of scalar values in one native
traversal.

## Build a projection

Suppose an API returns a customer and their orders:

```elixir
json = ~s({
  "customer": {"id": 1234, "name": "Acme", "plan": "business"},
  "orders": [
    {"sku": "ABC-123", "total": 29.95},
    {"sku": "XYZ-900", "total": 8.50}
  ]
})
```

You only need the customer identifier, name, and first SKU. Describe each
result field with an output key and a JSON path:

```elixir
fields = [
  {:customer_id, ["customer", "id"]},
  {:customer_name, ["customer", "name"]},
  {:first_sku, ["orders", 0, "sku"]}
]

{:ok, result} = SimdJson.select(json, fields)

result
# => %{customer_id: 1234, customer_name: "Acme", first_sku: "ABC-123"}
```

A binary path segment enters an object. A non-negative integer enters an array
at that index. The output keys are exactly the atoms or binaries you supplied;
JSON keys are never converted to atoms.

## Select scalar values

Selected leaves can be strings, integers, floats, booleans, or `null`:

```elixir
json = ~s({"name":"Ada","score":9.5,"active":true,"note":null})

SimdJson.select(json,
  name: ["name"],
  score: ["score"],
  active: ["active"],
  note: ["note"]
)
# => {:ok, %{name: "Ada", score: 9.5, active: true, note: nil}}
```

Objects and arrays are not scalar results. Selecting one returns an
`:incorrect_type` error instead of materializing that container. A failure
returns no partial map.

Every selected string is copied into a fresh binary. Keeping a small result
therefore does not retain the complete source through a substring.

## Select directly from a file

When the source is already on disk, avoid `File.read/1` and pass the path to
`select_file/2`:

```elixir
{:ok, customer} =
  SimdJson.select_file("customer.json",
    id: ["customer", "id"],
    plan: ["customer", "plan"]
  )

customer
# => %{id: 1234, plan: "business"}
```

The BEAM passes only the path across the native boundary. The file must remain
unchanged until the operation finishes. This avoids a complete BEAM binary
copy, although the one-shot simdjson structural index can still grow with the
document.

## Open a document for explicit cleanup

Most callers can use `select/2` or `select_file/2` directly. If you need an
explicit native lifetime, open and close a document yourself:

```elixir
with {:ok, document} <- SimdJson.open(json),
     {:ok, result} <- SimdJson.select(document, id: ["customer", "id"]) do
  :ok = SimdJson.close(document)
  {:ok, result}
end
```

The process that opens a document owns it. Selection is forward-only and
one-shot once native cursor access begins, whether it succeeds or fails. Open
a new document for another projection. Calling `close/1` again from the owner
is safe; another process receives `:not_owner`.

SimdJson validates the complete JSON source even when all selected values were
found early. If an object repeats a requested key, its first occurrence is the
selected value.

Previous: [02 — Decoding JSON](02-decoding-json.md)  
Next: [04 — Streaming Large Files](04-streaming-large-files.md)
