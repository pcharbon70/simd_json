defmodule SimdJson.Stream do
  @moduledoc """
  A lazy, owner-bound stream of projected JSON array rows.

  Values are constructed by `SimdJson.stream/2`. The representation is opaque;
  inspect output intentionally reveals only the source class and configured
  limits.
  """

  alias SimdJson.StreamOptions

  @enforce_keys [:__state__]
  defstruct [:__state__]

  @opaque t :: %__MODULE__{__state__: (-> StreamOptions.t())}

  @doc false
  @spec new(StreamOptions.t()) :: t()
  def new(options), do: %__MODULE__{__state__: fn -> options end}

  @doc false
  @spec options(t()) :: StreamOptions.t()
  def options(%__MODULE__{__state__: state}) when is_function(state, 0), do: state.()
end

defimpl Inspect, for: SimdJson.Stream do
  import Inspect.Algebra

  def inspect(stream, options) do
    metadata = stream |> SimdJson.Stream.options() |> SimdJson.StreamOptions.inspect_metadata()

    concat([
      "#SimdJson.Stream<source: ",
      to_doc(metadata.source_kind, options),
      ", batch_size: ",
      to_doc(metadata.batch_size, options),
      ", max_batch_bytes: ",
      to_doc(metadata.max_batch_bytes, options),
      ">"
    ])
  end
end
