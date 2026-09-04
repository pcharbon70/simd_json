defmodule SimdJson.DecodeOptions do
  @moduledoc false

  @enforce_keys [:input, :input_bytes]
  defstruct @enforce_keys

  @type t :: %__MODULE__{input: binary(), input_bytes: non_neg_integer()}

  # covers: simd_json.decode_api.binary_input simd_json.decode_api.closed_options simd_json.decode_api.preflight
  @spec new(term(), term()) :: t()
  def new(input, options) when is_binary(input) and options == [] do
    %__MODULE__{input: input, input_bytes: byte_size(input)}
  end

  def new(input, _options) when not is_binary(input) do
    raise ArgumentError, "expected JSON input to be a binary"
  end

  def new(_input, options) do
    if proper_list?(options) do
      raise ArgumentError, "decode options must be an empty list"
    else
      raise ArgumentError, "decode options must be a proper list"
    end
  end

  @spec input(t()) :: binary()
  def input(%__MODULE__{input: input}) when is_binary(input), do: input

  @spec snapshot_for_test(t()) :: map()
  def snapshot_for_test(%__MODULE__{input: input}) when is_binary(input) do
    %{
      input_bytes: byte_size(input),
      option_count: 0,
      compatibility_reference: "jason-1.4.5",
      input_type: :binary
    }
  end

  defp proper_list?([]), do: true
  defp proper_list?([_ | rest]), do: proper_list?(rest)
  defp proper_list?(_other), do: false
end
