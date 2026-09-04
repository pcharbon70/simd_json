defmodule SimdJson.Error do
  @moduledoc """
  A stable, redacted error returned by `SimdJson` operations.

  Callers should branch on `reason`; `message` is explanatory and may evolve.
  `byte_offset`, when present, is relative to the logical input rather than its
  native padded allocation. `native_code` is diagnostic only. `path`, when
  present, is copied from a validated caller projection. `array_index`, when
  present, is a checked zero-based source-array index. Inspection omits the
  message and path contents and bounds numeric metadata so accidentally forged
  or enriched text is not logged by default.

      iex> {:error, error} = SimdJson.open("?")
      iex> error.reason
      :invalid_json
      iex> inspect(error) =~ "reason: :invalid_json"
      true
      iex> inspect(error) =~ error.message
      false

      iex> {:error, error} = SimdJson.select(~s({"ready":true}), value: ["value"])
      iex> {error.reason, error.path}
      {:no_such_field, ["value"]}
      iex> inspect(error) =~ "value"
      false
  """

  @type reason ::
          :invalid_json
          | :invalid_utf8
          | :unexpected_eof
          | :out_of_memory
          | :closed
          | :not_owner
          | :invalid_projection
          | :no_such_field
          | :index_out_of_bounds
          | :incorrect_type
          | :number_out_of_range
          | :max_depth_exceeded
          | :input_too_large
          | :container_too_large
          | :string_too_large
          | :output_too_large
          | :batch_too_large
          | :busy
          | :cursor_consumed
          | :cancelled
          | :native_failure

  defexception [:reason, :byte_offset, :native_code, :path, :array_index, :message]

  @type t :: %__MODULE__{
          reason: reason(),
          byte_offset: non_neg_integer() | nil,
          native_code: integer() | nil,
          path:
            nonempty_list(binary() | 0..18_446_744_073_709_551_615)
            | nil,
          array_index: non_neg_integer() | nil,
          message: String.t()
        }
end

defimpl Inspect, for: SimdJson.Error do
  @reasons [
    :invalid_json,
    :invalid_utf8,
    :unexpected_eof,
    :out_of_memory,
    :closed,
    :not_owner,
    :invalid_projection,
    :no_such_field,
    :index_out_of_bounds,
    :incorrect_type,
    :number_out_of_range,
    :max_depth_exceeded,
    :input_too_large,
    :container_too_large,
    :string_too_large,
    :output_too_large,
    :batch_too_large,
    :busy,
    :cursor_consumed,
    :cancelled,
    :native_failure
  ]
  @max_offset 18_446_744_073_709_551_615
  @min_native_code -9_223_372_036_854_775_808
  @max_native_code 9_223_372_036_854_775_807

  def inspect(error, options) do
    reason = render(safe_reason(error.reason), options)
    offset = render(safe_offset(error.byte_offset), options)
    code = render(safe_native_code(error.native_code), options)
    array_index = safe_array_index(error.array_index)
    array_index = if is_nil(array_index), do: "", else: ", array_index: #{array_index}"
    path = if is_nil(error.path), do: "", else: ", path: <caller-supplied>"

    "#SimdJson.Error<reason: #{reason}, byte_offset: #{offset}, native_code: #{code}#{array_index}#{path}>"
  end

  defp safe_reason(reason) when reason in @reasons, do: reason
  defp safe_reason(_reason), do: :native_failure

  defp safe_offset(nil), do: nil

  defp safe_offset(offset) when is_integer(offset) and offset >= 0 and offset <= @max_offset,
    do: offset

  defp safe_offset(_offset), do: nil

  defp safe_native_code(nil), do: nil

  defp safe_native_code(code)
       when is_integer(code) and code >= @min_native_code and code <= @max_native_code,
       do: code

  defp safe_native_code(_code), do: nil

  defp safe_array_index(nil), do: nil

  defp safe_array_index(index) when is_integer(index) and index >= 0 and index <= @max_offset,
    do: index

  defp safe_array_index(_index), do: nil

  defp render(value, options) do
    value
    |> Inspect.Algebra.to_doc(options)
    |> Inspect.Algebra.format(:infinity)
    |> IO.iodata_to_binary()
  end
end
