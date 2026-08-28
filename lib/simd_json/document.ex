defmodule SimdJson.Document do
  @moduledoc """
  An opaque handle to a parsed JSON document.

  Documents belong to the process that opened them. Use `SimdJson.close/1` for
  deterministic cleanup; the wrapped native resource is intentionally not a
  public API.
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
