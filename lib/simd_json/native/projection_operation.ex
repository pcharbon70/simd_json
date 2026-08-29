defmodule SimdJson.Native.ProjectionOperation do
  @moduledoc false

  @test_hooks Mix.env() == :test

  if @test_hooks do
    alias SimdJson.Document
    alias SimdJson.Error
    alias SimdJson.Native.ThreadedOperation
    alias SimdJson.Projection

    @doc false
    @spec select_for_test(term(), term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
    def select_for_test(source, projection, options \\ []) when is_list(options) do
      with {:ok, normalized} <- Projection.validate(projection) do
        {source_kind, native_source, logical_length} = classify_source!(source)

        case ThreadedOperation.project(
               source_kind,
               native_source,
               normalized,
               options
             ) do
          {:ok, result} ->
            {:ok, result}

          {:error, native_error} ->
            {:error, translate_error(native_error, normalized, logical_length)}
        end
      end
    end

    defp classify_source!(source) when is_binary(source),
      do: {:binary, source, byte_size(source)}

    defp classify_source!(%Document{__resource__: resource}),
      do: {:document, resource, nil}

    defp classify_source!(_source),
      do: raise(ArgumentError, "expected JSON input to be a binary or SimdJson.Document")

    defp translate_error(native_error, normalized, logical_length) do
      native_reason = Map.get(native_error, :reason)
      reason = stable_reason(native_reason)

      %Error{
        reason: reason,
        byte_offset: safe_offset(Map.get(native_error, :byte_offset), logical_length),
        native_code: safe_native_code(Map.get(native_error, :native_code)),
        path: failing_path(normalized, Map.get(native_error, :output_slot)),
        message: message(reason)
      }
    end

    defp stable_reason(:missing_field), do: :no_such_field

    defp stable_reason(reason)
         when reason in [
                :invalid_json,
                :invalid_utf8,
                :unexpected_eof,
                :out_of_memory,
                :closed,
                :not_owner,
                :invalid_projection,
                :index_out_of_bounds,
                :incorrect_type,
                :number_out_of_range,
                :cursor_consumed,
                :cancelled
              ],
         do: reason

    defp stable_reason(_reason), do: :native_failure

    defp failing_path(_normalized, nil), do: nil

    defp failing_path(normalized, output_slot) when is_integer(output_slot) do
      %{entries: entries, paths: paths} = Projection.snapshot_for_test(normalized)

      with {_slot, _output_key, path_slot} <-
             Enum.find(entries, fn {slot, _key, _path_slot} -> slot == output_slot end),
           {^path_slot, path} <-
             Enum.find(paths, fn {candidate, _path} -> candidate == path_slot end) do
        path
      else
        _missing -> nil
      end
    end

    defp failing_path(_normalized, _output_slot), do: nil

    defp safe_offset(nil, _logical_length), do: nil

    defp safe_offset(offset, nil)
         when is_integer(offset) and offset >= 0 and offset <= 18_446_744_073_709_551_615,
         do: offset

    defp safe_offset(offset, logical_length)
         when is_integer(offset) and is_integer(logical_length) and offset >= 0 and
                offset <= logical_length,
         do: offset

    defp safe_offset(_offset, _logical_length), do: nil

    defp safe_native_code(code) when is_integer(code), do: code
    defp safe_native_code(_code), do: nil

    defp message(:invalid_json), do: "invalid JSON"
    defp message(:invalid_utf8), do: "invalid UTF-8 in JSON input"
    defp message(:unexpected_eof), do: "unexpected end of JSON input"
    defp message(:out_of_memory), do: "native JSON allocation failed"
    defp message(:closed), do: "document is closed"
    defp message(:not_owner), do: "document belongs to another process"
    defp message(:invalid_projection), do: "invalid projection"
    defp message(:no_such_field), do: "requested field does not exist"
    defp message(:index_out_of_bounds), do: "requested array index is out of bounds"
    defp message(:incorrect_type), do: "selected value has an incorrect type"
    defp message(:number_out_of_range), do: "selected number is out of range"
    defp message(:cursor_consumed), do: "document cursor has already been consumed"
    defp message(:cancelled), do: "JSON operation was cancelled"
    defp message(:native_failure), do: "native JSON operation failed"
  end
end
