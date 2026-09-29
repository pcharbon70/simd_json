defmodule SimdJson.Native.ProjectionOperation do
  @moduledoc false

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.ThreadedOperation
  alias SimdJson.Projection

  @test_hooks Mix.env() == :test
  @max_u64 18_446_744_073_709_551_615
  @min_native_code -2_147_483_648
  @max_native_code 2_147_483_647

  # covers: simd_json.projection_api.select_contract simd_json.projection_api.source_argument_validation simd_json.projection_api.complete_preflight_validation simd_json.projection_api.atomic_result simd_json.projection_api.projection_error_reasons simd_json.projection_api.error_path simd_json.projection_execution.preadmission_nonconsumption
  @doc false
  @spec select(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def select(source, projection), do: select_with_options(source, projection, [])

  # covers: simd_json.file_input.native_path_boundary simd_json.file_input.select_file_contract simd_json.file_input.no_complete_source_copy simd_json.file_input.immutable_source simd_json.file_input.pool_and_cleanup
  @doc false
  @spec select_file(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def select_file(path, projection) do
    with {:ok, normalized} <- Projection.validate(projection),
         :ok <- validate_file_path!(path),
         {:ok, %Document{} = document} <- SimdJson.open_file(path) do
      run_file_projection(document, normalized)
    end
  end

  if @test_hooks do
    @doc false
    @spec select_for_test(term(), term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
    def select_for_test(source, projection, options \\ []) when is_list(options) do
      select_with_options(source, projection, options)
    end

    @doc false
    @spec translate_error_for_test(term(), term(), non_neg_integer() | nil) :: Error.t()
    def translate_error_for_test(native_error, projection, logical_length)
        when is_nil(logical_length) or
               (is_integer(logical_length) and logical_length >= 0) do
      case Projection.validate(projection) do
        {:ok, normalized} -> translate_error(native_error, normalized, logical_length)
        {:error, error} -> error
      end
    end
  end

  defp select_with_options(source, projection, options) do
    with {:ok, normalized} <- Projection.validate(projection),
         {:ok, source_kind, native_source, logical_length} <- classify_source(source) do
      run_projection(source_kind, native_source, normalized, logical_length, options)
    end
  end

  defp classify_source(source) when is_binary(source),
    do: {:ok, :binary, source, byte_size(source)}

  defp classify_source(%Document{__resource__: resource}) when is_reference(resource) do
    case document_owner_state(resource) do
      :open -> {:ok, :document, resource, nil}
      :closing -> {:error, error(:closed)}
      :closed -> {:error, error(:closed)}
      :not_owner -> {:error, error(:not_owner)}
      :invalid -> invalid_source!()
    end
  end

  defp classify_source(_source), do: invalid_source!()

  defp document_owner_state(resource) do
    try do
      BuildSmoke.document_owner_state(resource)
    rescue
      ArgumentError -> :invalid
      ErlangError -> :invalid
    end
  end

  defp run_projection(source_kind, native_source, normalized, logical_length, options) do
    result =
      try do
        ThreadedOperation.project(source_kind, native_source, normalized, options)
      rescue
        ErlangError -> native_failure_result()
      catch
        :exit, _reason -> native_failure_result()
      end

    case result do
      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:error, native_error} ->
        {:error, translate_error(native_error, normalized, logical_length)}

      _unexpected ->
        {:error, error(:native_failure)}
    end
  end

  defp run_file_projection(%Document{__resource__: resource} = document, normalized) do
    try do
      result = run_projection(:document, resource, normalized, nil, [])

      case SimdJson.close(document) do
        :ok -> result
        {:error, %Error{} = error} -> {:error, error}
      end
    after
      _ = SimdJson.close(document)
    end
  end

  defp translate_error(native_error, normalized, logical_length) do
    reason = native_error |> field(:reason) |> stable_reason()

    %Error{
      reason: reason,
      byte_offset: safe_offset(field(native_error, :byte_offset), logical_length),
      native_code: safe_native_code(field(native_error, :native_code)),
      path: failing_path(reason, normalized, field(native_error, :output_slot)),
      message: message(reason)
    }
  end

  defp field(native_error, key) when is_map(native_error), do: Map.get(native_error, key)
  defp field(_native_error, _key), do: nil

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
              :busy,
              :cursor_consumed,
              :cancelled,
              :file_not_found,
              :file_unreadable,
              :not_regular_file,
              :file_changed
            ],
       do: reason

  defp stable_reason(_reason), do: :native_failure

  defp failing_path(reason, normalized, output_slot)
       when reason in [
              :no_such_field,
              :index_out_of_bounds,
              :incorrect_type,
              :number_out_of_range
            ],
       do: Projection.path_for_output_slot(normalized, output_slot)

  defp failing_path(_reason, _normalized, _output_slot), do: nil

  defp safe_offset(nil, _logical_length), do: nil

  defp safe_offset(offset, nil)
       when is_integer(offset) and offset >= 0 and offset <= @max_u64,
       do: offset

  defp safe_offset(offset, logical_length)
       when is_integer(offset) and is_integer(logical_length) and offset >= 0 and
              offset <= logical_length,
       do: offset

  defp safe_offset(_offset, _logical_length), do: nil

  defp safe_native_code(code)
       when is_integer(code) and code >= @min_native_code and code <= @max_native_code,
       do: code

  defp safe_native_code(_code), do: nil

  defp error(reason), do: %Error{reason: reason, message: message(reason)}

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
  defp message(:busy), do: "native execution capacity is busy"
  defp message(:cursor_consumed), do: "document cursor has already been consumed"
  defp message(:cancelled), do: "JSON operation was cancelled"
  defp message(:file_not_found), do: "JSON file was not found"
  defp message(:file_unreadable), do: "JSON file could not be read"
  defp message(:not_regular_file), do: "JSON path is not a regular file"
  defp message(:file_changed), do: "JSON file changed while mapped"
  defp message(:native_failure), do: "native JSON operation failed"

  defp native_failure_result do
    {:error, %{reason: :native_failure, native_code: nil, byte_offset: nil}}
  end

  defp invalid_source! do
    raise ArgumentError, "expected JSON input to be a binary or SimdJson.Document"
  end

  defp validate_file_path!(path)
       when is_binary(path) and byte_size(path) > 0 do
    if :binary.match(path, <<0>>) == :nomatch do
      :ok
    else
      invalid_file_path!()
    end
  end

  defp validate_file_path!(_path), do: invalid_file_path!()

  defp invalid_file_path! do
    raise ArgumentError, "expected file path to be a non-empty binary without NUL bytes"
  end
end
