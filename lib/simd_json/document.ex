defmodule SimdJson.Document do
  @moduledoc """
  An opaque handle to a parsed JSON document.

  Documents belong to the process that opened them. Use `SimdJson.close/1` for
  deterministic cleanup; the wrapped native resource is intentionally not a
  public API. Inspection is lifecycle-neutral and reveals neither input nor
  native identity.

      iex> {:ok, document} = SimdJson.open("null")
      iex> inspect(document)
      "#SimdJson.Document<opaque>"
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
