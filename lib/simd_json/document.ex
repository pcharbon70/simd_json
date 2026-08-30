defmodule SimdJson.Document do
  @moduledoc """
  An opaque handle to a parsed JSON document.

  Documents belong to the process that opened them. Use `SimdJson.close/1` for
  deterministic cleanup; the wrapped native resource is intentionally not a
  public API. Inspection is lifecycle-neutral and reveals neither input nor
  native identity.

  A document is a one-shot source for `SimdJson.select/2`. Once native cursor
  access begins, success or failure consumes it. Use another document or the
  binary form of `SimdJson.select/2` for another projection; documents are not
  rewound or reparsed transparently.

      iex> {:ok, document} = SimdJson.open(~s({"value":1}))
      iex> inspect(document)
      "#SimdJson.Document<opaque>"
      iex> {:error, error} = SimdJson.select(document, value: ["missing"])
      iex> {error.reason, error.path}
      {:no_such_field, ["missing"]}
      iex> SimdJson.close(document)
      :ok
  """

  @enforce_keys [:__resource__]
  defstruct [:__resource__]

  @opaque t :: %__MODULE__{__resource__: reference()}
end

defimpl Inspect, for: SimdJson.Document do
  def inspect(_document, _options) do
    "#SimdJson.Document<opaque>"
  end
end
