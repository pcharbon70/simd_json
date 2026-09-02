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

defimpl Enumerable, for: SimdJson.Stream do
  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.ThreadedOperation
  alias SimdJson.StreamOptions

  def count(_stream), do: {:error, __MODULE__}
  def member?(_stream, _value), do: {:error, __MODULE__}
  def slice(_stream), do: {:error, __MODULE__}

  def reduce(stream, command, reducer) do
    runtime = stream |> SimdJson.Stream.options() |> StreamOptions.runtime()

    if runtime.owner != self() do
      raise error(:not_owner)
    end

    case command do
      {:halt, acc} -> {:halted, acc}
      {:suspend, acc} -> {:suspended, acc, &reduce(stream, &1, reducer)}
      {:cont, acc} -> setup_and_reduce(runtime, acc, reducer)
    end
  end

  defp setup_and_reduce(runtime, acc, reducer) do
    source =
      case runtime.source do
        %Document{__resource__: resource} -> resource
        binary -> binary
      end

    setup =
      ThreadedOperation.stream_setup(
        runtime.source_kind,
        source,
        runtime.fields,
        runtime.target_path,
        runtime.batch_size,
        runtime.max_batch_bytes
      )

    case setup do
      {:ok, %{cursor: cursor}} -> drive(cursor, runtime.fields, 1, 0, [], acc, reducer)
      {:error, native} -> raise translate(native)
    end
  end

  defp drive(cursor, projection, generation, sequence, [], acc, reducer) do
    case ThreadedOperation.stream_batch(cursor, projection, generation, sequence) do
      {:ok, %{rows: [], done: true}} ->
        close(cursor, {:done, acc})

      {:ok, %{rows: rows, done: done}} ->
        drive(cursor, projection, generation, sequence + 1, {rows, done}, acc, reducer)

      {:error, native} ->
        close(cursor, {:raise, translate(native)})
    end
  end

  defp drive(cursor, _projection, _generation, _sequence, {[], true}, acc, _reducer),
    do: close(cursor, {:done, acc})

  defp drive(cursor, projection, generation, sequence, {[], false}, acc, reducer),
    do: drive(cursor, projection, generation, sequence, [], acc, reducer)

  defp drive(cursor, projection, generation, sequence, {[row | rows], done}, acc, reducer) do
    try do
      case reducer.(row, acc) do
        {:cont, next} ->
          drive(cursor, projection, generation, sequence, {rows, done}, next, reducer)

        {:halt, next} ->
          close(cursor, {:halted, next})

        {:suspend, next} ->
          {:suspended, next,
           &resume(cursor, projection, generation, sequence, rows, done, &1, reducer)}
      end
    rescue
      exception ->
        stacktrace = __STACKTRACE__
        _ = BuildSmoke.stream_cursor_resource_close(cursor)
        reraise exception, stacktrace
    end
  end

  defp resume(cursor, projection, generation, sequence, rows, done, {:cont, acc}, reducer),
    do: drive(cursor, projection, generation, sequence, {rows, done}, acc, reducer)

  defp resume(cursor, _projection, _generation, _sequence, _rows, _done, {:halt, acc}, _reducer),
    do: close(cursor, {:halted, acc})

  defp resume(cursor, projection, generation, sequence, rows, done, {:suspend, acc}, reducer),
    do:
      {:suspended, acc,
       &resume(cursor, projection, generation, sequence, rows, done, &1, reducer)}

  defp close(cursor, outcome) do
    _ = BuildSmoke.stream_cursor_resource_close(cursor)

    case outcome do
      {:done, acc} -> {:done, acc}
      {:halted, acc} -> {:halted, acc}
      {:raise, exception} -> raise exception
    end
  end

  defp translate(native) do
    native_reason = Map.get(native, :reason, :native_failure)
    reason = stable_reason(native_reason)

    %Error{
      reason: reason,
      message: message(reason),
      byte_offset: safe_non_negative(Map.get(native, :byte_offset)),
      native_code: safe_integer(Map.get(native, :native_code)),
      array_index: safe_non_negative(Map.get(native, :array_index))
    }
  end

  defp stable_reason(:missing_field), do: :no_such_field
  defp stable_reason(:invalid_target), do: :incorrect_type
  defp stable_reason(:cursor_state), do: :cursor_consumed

  defp stable_reason(reason)
       when reason in [
              :invalid_json,
              :invalid_utf8,
              :unexpected_eof,
              :out_of_memory,
              :not_owner,
              :closed,
              :cursor_consumed,
              :cancelled,
              :index_out_of_bounds,
              :incorrect_type,
              :number_out_of_range,
              :batch_too_large
            ],
       do: reason

  defp stable_reason(_), do: :native_failure

  defp safe_non_negative(value) when is_integer(value) and value >= 0, do: value
  defp safe_non_negative(_), do: nil
  defp safe_integer(value) when is_integer(value), do: value
  defp safe_integer(_), do: nil

  defp message(:no_such_field), do: "projected field does not exist"
  defp message(:incorrect_type), do: "JSON value has the wrong type"
  defp message(:index_out_of_bounds), do: "JSON array index is out of bounds"
  defp message(:number_out_of_range), do: "JSON number is out of range"
  defp message(:batch_too_large), do: "projected row exceeds the batch byte limit"
  defp message(:invalid_json), do: "invalid JSON"
  defp message(:invalid_utf8), do: "invalid UTF-8 in JSON input"
  defp message(:unexpected_eof), do: "unexpected end of JSON input"
  defp message(:out_of_memory), do: "native JSON allocation failed"
  defp message(:not_owner), do: "stream belongs to another process"
  defp message(:closed), do: "stream source is closed"
  defp message(:cursor_consumed), do: "stream source was already consumed"
  defp message(:cancelled), do: "stream operation was cancelled"
  defp message(:native_failure), do: "native JSON operation failed"

  defp error(reason)
       when reason in [:not_owner, :closed, :cursor_consumed, :cancelled, :out_of_memory],
       do: %Error{reason: reason, message: Atom.to_string(reason)}

  defp error(_reason),
    do: %Error{reason: :native_failure, message: "native JSON operation failed"}
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
