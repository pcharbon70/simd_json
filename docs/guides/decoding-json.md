# Decoding JSON

`decode/1,2` converts one complete JSON value into Elixir terms. `decode!/1,2`
returns the value directly and raises `SimdJson.Error` on failure.

```elixir
{:ok, %{"name" => "Ada", "scores" => [10, 20]}} =
  SimdJson.decode(~s({"name":"Ada","scores":[10,20]}))

%{"ready" => true} = SimdJson.decode!(~s({"ready":true}))
```

The accepted options are intentionally narrow: omit the second argument or
pass `[]`. Any non-empty option list is rejected. Input must be a binary;
iodata is not accepted.

## Result mapping

| JSON | Elixir |
| --- | --- |
| object | map with binary keys |
| array | list |
| string | binary |
| integer | integer |
| number with fraction or exponent | float |
| `true` / `false` | boolean |
| `null` | `nil` |

Duplicate object keys use the last value. Integers remain exact when they fit
the supported native range; an out-of-range number returns an error rather
than silently rounding. Input never creates atoms.

## Memory behavior

Decoding necessarily builds the complete Elixir tree. This is appropriate
when the application needs the whole value. When it needs only a few fields,
use [Selecting Fields](selecting-fields.md). For a large array or document
stream, use [Streaming Large Files](streaming-large-files.md).

## Error handling

```elixir
case SimdJson.decode(json) do
  {:ok, value} ->
    value

  {:error, %SimdJson.Error{reason: reason, byte_offset: offset}} ->
    {:invalid_json, reason, offset}
end
```

Error inspection is redacted and does not reveal source contents.
