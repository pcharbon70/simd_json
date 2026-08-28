defmodule SimdJson do
  # covers: simd_json.package.mix_library simd_json.native_build_and_abi.layered_boundary simd_json.document_api.open_contract simd_json.document_api.binary_only simd_json.document_api.close_contract simd_json.document_api.document_argument_validation
  @moduledoc """
  Opens and closes opaque JSON documents using SIMD-accelerated parsing.

  The Milestone 1 public contract consists only of `open/1`, `close/1`,
  `SimdJson.Document`, and `SimdJson.Error`. It accepts binaries only and
  intentionally exposes no decoded tree, projection, stream, cursor,
  ownership-transfer, or native-handle API.

  A document belongs to the process that opened it. Owner `close/1` is
  idempotent and waits for native cleanup; another process receives a stable
  `:not_owner` error even when the document has already been closed. Other
  owner operations introduced by later milestones will return `:closed` after
  close.

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
  alias SimdJson.Native.ThreadedOperation

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
