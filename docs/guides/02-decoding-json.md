# 02 — Decoding JSON

Use `decode/1` when you want to turn one complete JSON value into ordinary
Elixir data. In this tutorial, you will decode an order, work with the result,
and handle malformed input.

## Decode your first value

Start with a small order:

```elixir
json = ~s({
  "order_id": 4815,
  "paid": true,
  "items": [
    {"sku": "BOOK-1", "quantity": 2},
    {"sku": "PEN-4", "quantity": 5}
  ]
})

{:ok, order} = SimdJson.decode(json)
```

The result is made from familiar Elixir values:

```elixir
order["order_id"]
# => 4815

Enum.map(order["items"], & &1["sku"])
# => ["BOOK-1", "PEN-4"]
```

JSON object keys remain binaries. SimdJson never creates atoms from input, so
you can safely decode documents with keys you have not seen before.

## Choose tagged or raising results

`decode/1` is convenient at trust boundaries because success and failure are
explicit:

```elixir
case SimdJson.decode(payload) do
  {:ok, value} ->
    {:accepted, value}

  {:error, %SimdJson.Error{} = error} ->
    {:rejected, error.reason}
end
```

When invalid JSON is exceptional, use `decode!/1`:

```elixir
order = SimdJson.decode!(json)
```

It returns the value directly and raises `SimdJson.Error` on failure. Both
forms use the same parser and produce the same Elixir data.

## Understand the result types

SimdJson maps JSON values as follows:

| JSON value | Elixir value |
| --- | --- |
| object | map with binary keys |
| array | list |
| string | binary |
| integer | integer |
| fraction or exponent | float |
| `true` or `false` | boolean |
| `null` | `nil` |

If an object repeats a key, the last value wins. Integers remain exact when
they fit the supported native range; values outside that range return an error
instead of being silently rounded.

## Handle malformed input

Errors include a stable reason and, when available, a byte offset:

```elixir
invalid = ~s({"order_id":4815,"items":[})

case SimdJson.decode(invalid) do
  {:error, %SimdJson.Error{reason: reason, byte_offset: offset}} ->
    IO.inspect({reason, offset}, label: "decode failed")

  {:ok, _order} ->
    :unexpected_success
end
```

Error inspection is redacted: it will not print the JSON source, native
addresses, or internal request data.

## Know when not to decode

Decoding builds the complete Elixir tree, so the result naturally grows with
the document. That is the right tradeoff when your application needs the whole
value.

If the order contains thousands of fields but you only need its identifier,
select that field instead. If the source is a large row sequence, stream it.

`decode/2` currently accepts only an empty option list, and input must be a
binary rather than iodata:

```elixir
SimdJson.decode(json, [])
# => {:ok, order}
```

Previous: [01 — Getting Started](01-getting-started.md)  
Next: [03 — Selecting Fields](03-selecting-fields.md)
