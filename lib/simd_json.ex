defmodule SimdJson do
  # covers: simd_json.package.mix_library simd_json.native_build_and_abi.layered_boundary simd_json.document_api.open_contract simd_json.document_api.binary_only simd_json.document_api.close_contract simd_json.document_api.document_argument_validation simd_json.projection_api.select_contract simd_json.projection_api.source_argument_validation simd_json.projection_api.output_key_identity simd_json.projection_api.scalar_results simd_json.projection_api.atomic_result
  @moduledoc """
  Opens opaque JSON documents and selects scalar values using SIMD-accelerated
  parsing.

  `select/2` extracts several named scalar paths from either a JSON binary or
  a caller-owned document. Results use the exact atom or binary keys supplied
  by the caller. Object and array leaves are deliberately not materialized.

  A document belongs to the process that opened it. Owner `close/1` is
  idempotent and waits for native cleanup; another process receives a stable
  `:not_owner` error even when the document has already been closed. Projection
  is one-shot: after native cursor access begins, success or failure consumes
  the document. Use another document, or call `select/2` with the binary again,
  for another projection.

  Projection grammar errors are tagged `:invalid_projection`. Values that are
  not binaries or genuine document resources raise `ArgumentError`. Other
  parsing, path, ownership, lifecycle, allocation, and cancellation failures
  return `{:error, %SimdJson.Error{}}` without a partial result. Selected
  strings are fresh binaries independent of their source.

  The API intentionally has no bang variant, eager decode, JSONPath, wildcard,
  default-field policy, container materialization, public compiled plan,
  stream, cursor, ownership-transfer, or native-handle operation.

  Threaded execution in this milestone is a qualification runtime. Production
  admission control and its bounded worker pool arrive in Milestone 4.

  ## Examples

      iex> {:ok, document} = SimdJson.open(~s({"ready": true}))
      iex> inspect(document)
      "#SimdJson.Document<opaque>"
      iex> SimdJson.close(document)
      :ok
      iex> SimdJson.close(document)
      :ok

      iex> json = ~s({"customer":{"id":7,"name":"Acme"},"orders":[{"sku":"A-1"}]})
      iex> projection = [{:id, ["customer", "id"]}, {"sku", ["orders", 0, "sku"]}]
      iex> SimdJson.select(json, projection)
      {:ok, %{"sku" => "A-1", id: 7}}

      iex> {:ok, document} = SimdJson.open(~s({"value":42}))
      iex> SimdJson.select(document, value: ["value"])
      {:ok, %{value: 42}}
      iex> {:error, consumed} = SimdJson.select(document, value: ["value"])
      iex> consumed.reason
      :cursor_consumed
      iex> SimdJson.close(document)
      :ok

      iex> {:error, missing} = SimdJson.select(~s({"ready":true}), value: ["value"])
      iex> {missing.reason, missing.path}
      {:no_such_field, ["value"]}
      iex> inspect(missing) =~ "value"
      false

      iex> {:error, type_error} = SimdJson.select(~s({"items":[]}), items: ["items"])
      iex> type_error.reason
      :incorrect_type

      iex> {:error, invalid} = SimdJson.select("not inspected", [])
      iex> {invalid.reason, invalid.byte_offset, invalid.path}
      {:invalid_projection, nil, nil}

      iex> source = ~s({"selected":"small","ignored":"#{String.duplicate("x", 256)}"})
      iex> {:ok, %{selected: selected}} = SimdJson.select(source, selected: ["selected"])
      iex> source = nil
      iex> :erlang.garbage_collect(self())
      iex> {source, selected}
      {nil, "small"}

      iex> function_exported?(SimdJson, :select!, 2)
      false
      iex> Code.ensure_loaded?(SimdJson.CompiledProjection)
      false

      iex> {:error, error} = SimdJson.open("[1,")
      iex> {error.reason, error.message}
      {:unexpected_eof, "unexpected end of JSON input"}
      iex> inspect(error) =~ "[1,"
      false

      iex> SimdJson.open(:not_a_binary)
      ** (ArgumentError) expected JSON input to be a binary

      iex> {:ok, document} = SimdJson.open("null")
      iex> task = Task.async(fn -> SimdJson.close(document) end)
      iex> {:error, non_owner_error} = Task.await(task)
      iex> non_owner_error.reason
      :not_owner
      iex> SimdJson.close(document)
      :ok
  """

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.ProjectionOperation
  alias SimdJson.Native.ThreadedOperation

  @typedoc "An exact caller-supplied result key. No atom is created from a binary key."
  @type output_key :: atom() | binary()

  @typedoc "A UTF-8 JSON object-key segment."
  @type object_segment :: binary()

  @typedoc "A JSON array index in the unsigned 64-bit domain."
  @type array_index :: 0..18_446_744_073_709_551_615

  @typedoc "One object-key or array-index segment in a projection path."
  @type path_segment :: object_segment() | array_index()

  @typedoc "A non-empty path to one scalar JSON value."
  @type path :: nonempty_list(path_segment())

  @typedoc "One output key paired with its scalar path."
  @type projection_entry :: {output_key(), path()}

  @typedoc "A non-empty proper list of projection entries with unique output keys."
  @type projection :: nonempty_list(projection_entry())

  @typedoc "A selected scalar converted to an independent BEAM term."
  @type scalar_result :: binary() | integer() | float() | boolean() | nil

  @typedoc "The transactional map returned after every selected path succeeds."
  @type projection_result :: %{optional(output_key()) => scalar_result()}

  @doc """
  Opens one JSON binary as an opaque document owned by the calling process.

  Malformed input returns a structured error. A non-binary argument raises
  `ArgumentError` before native work is submitted.
  """
  @spec open(binary()) :: {:ok, Document.t()} | {:error, Error.t()}
  def open(input) when is_binary(input) do
    result =
      try do
        ThreadedOperation.open(input)
      rescue
        ErlangError -> native_failure_result()
      catch
        :exit, _reason -> native_failure_result()
      end

    case result do
      {:ok, resource} -> {:ok, %Document{__resource__: resource}}
      {:error, native_error} -> {:error, translate_error(native_error, byte_size(input))}
    end
  end

  def open(_input) do
    raise ArgumentError, "expected JSON input to be a binary"
  end

  @doc """
  Selects several scalar paths from a JSON binary or caller-owned document.

  The projection is completely validated before parsing or document
  reservation. It must be a non-empty proper list of `{output_key, path}`
  pairs. Output keys are existing atoms or binaries; paths are non-empty proper
  lists of UTF-8 binary object keys and unsigned 64-bit array indexes.

  Success returns one map under the exact supplied keys. Strings are copied
  into fresh binaries. A document is a forward-only, single-owner, one-shot
  source: once cursor access starts, either success or operational failure
  consumes it. Invalid projection, invalid source, non-owner, closed, and
  proven pre-worker submission rejection do not consume a fresh document.

  Source misuse raises `ArgumentError`. Projection, parse, path, lifecycle,
  allocation, and cancellation failures return a structured tagged error; no
  partial map escapes.
  """
  @spec select(binary() | Document.t(), projection()) ::
          {:ok, projection_result()} | {:error, Error.t()}
  def select(source, projection), do: ProjectionOperation.select(source, projection)

  @doc """
  Closes an opaque document owned by the calling process.

  Owner close is idempotent and returns only after native cleanup completes.
  A non-owner receives `{:error, %SimdJson.Error{reason: :not_owner}}` without
  learning the document lifecycle. A non-document argument raises
  `ArgumentError` before cleanup is submitted.
  """
  @spec close(Document.t()) :: :ok | {:error, Error.t()}
  def close(%Document{__resource__: resource}) do
    case owner_state(resource) do
      :open -> run_cleanup(resource)
      :closing -> run_cleanup(resource)
      :closed -> :ok
      :not_owner -> {:error, error(:not_owner)}
      :invalid -> invalid_document!()
    end
  end

  def close(_document), do: invalid_document!()

  defp owner_state(resource) do
    try do
      BuildSmoke.document_owner_state(resource)
    rescue
      ArgumentError -> :invalid
      ErlangError -> :invalid
    end
  end

  defp run_cleanup(resource) do
    case ThreadedOperation.cleanup(resource) do
      :ok -> :ok
      {:error, native_error} -> {:error, translate_error(native_error, 0)}
    end
  rescue
    ErlangError -> {:error, error(:native_failure)}
  catch
    :exit, _reason -> {:error, error(:native_failure)}
  end

  defp translate_error(native_error, logical_length) do
    native_reason = Map.get(native_error, :reason)
    reason = stable_reason(native_reason)

    %Error{
      reason: reason,
      byte_offset: safe_offset(Map.get(native_error, :byte_offset), logical_length),
      native_code: safe_native_code(Map.get(native_error, :native_code)),
      message: message(reason)
    }
  end

  defp stable_reason(reason)
       when reason in [:invalid_json, :invalid_utf8, :unexpected_eof, :out_of_memory],
       do: reason

  defp stable_reason(:not_owner), do: :not_owner
  defp stable_reason(:closed), do: :closed
  defp stable_reason(_reason), do: :native_failure

  defp safe_offset(offset, logical_length)
       when is_integer(offset) and offset >= 0 and offset <= logical_length,
       do: offset

  defp safe_offset(_offset, _logical_length), do: nil

  defp safe_native_code(code) when is_integer(code), do: code
  defp safe_native_code(_code), do: nil

  defp error(reason) do
    %Error{reason: reason, message: message(reason)}
  end

  defp message(:invalid_json), do: "invalid JSON"
  defp message(:invalid_utf8), do: "invalid UTF-8 in JSON input"
  defp message(:unexpected_eof), do: "unexpected end of JSON input"
  defp message(:out_of_memory), do: "native JSON allocation failed"
  defp message(:closed), do: "document is closed"
  defp message(:not_owner), do: "document belongs to another process"
  defp message(:native_failure), do: "native JSON operation failed"

  defp native_failure_result do
    {:error, %{reason: :native_failure, native_code: nil, byte_offset: nil}}
  end

  defp invalid_document! do
    raise ArgumentError, "expected a SimdJson.Document"
  end
end
