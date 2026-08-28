defmodule SimdJson.Error do
  @moduledoc """
  A stable, redacted error returned by `SimdJson` operations.

  Callers should branch on `reason`; `message` is explanatory and may evolve.
  `byte_offset`, when present, is relative to the logical input rather than its
  native padded allocation. `native_code` is diagnostic only. Inspection omits
  the message so accidentally forged or enriched text is not logged by default.

      iex> {:error, error} = SimdJson.open("?")
      iex> error.reason
      :invalid_json
      iex> inspect(error) =~ "reason: :invalid_json"
      true
      iex> inspect(error) =~ error.message
      false
  """

  @type reason ::
          :invalid_json
          | :invalid_utf8
          | :unexpected_eof
          | :out_of_memory
          | :closed
          | :not_owner
          | :native_failure

  @enforce_keys [:reason, :message]
  defstruct [:reason, :byte_offset, :native_code, :message]

  @type t :: %__MODULE__{
          reason: reason(),
          byte_offset: non_neg_integer() | nil,
          native_code: integer() | nil,
          message: String.t()
        }
end

defimpl Inspect, for: SimdJson.Error do
  def inspect(error, options) do
    reason = render(error.reason, options)
    offset = render(error.byte_offset, options)
    code = render(error.native_code, options)

    "#SimdJson.Error<reason: #{reason}, byte_offset: #{offset}, native_code: #{code}>"
  end

  defp render(value, options) do
    value
    |> Inspect.Algebra.to_doc(options)
    |> Inspect.Algebra.format(:infinity)
    |> IO.iodata_to_binary()
  end
end
