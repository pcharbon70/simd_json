defmodule SimdJson.Projection do
  @moduledoc false

  alias SimdJson.Error

  @tag :simd_json_projection_v1
  @max_array_index 18_446_744_073_709_551_615
  @invalid_projection_message "invalid projection"
  @test_hooks Mix.env() == :test

  @typedoc false
  @type output_key :: atom() | binary()

  @typedoc false
  @type object_segment :: binary()

  @typedoc false
  @type array_segment :: 0..18_446_744_073_709_551_615

  @typedoc false
  @type segment :: object_segment() | array_segment()

  @typedoc false
  @type path :: nonempty_list(segment())

  @typedoc false
  @type output_slot :: non_neg_integer()

  @typedoc false
  @type path_slot :: non_neg_integer()

  @typedoc false
  @type normalized_entry :: {output_slot(), output_key(), path_slot()}

  @typedoc false
  @type normalized_path :: {path_slot(), path()}

  @typedoc false
  @opaque t ::
            {:simd_json_projection_v1, nonempty_list(normalized_entry()),
             nonempty_list(normalized_path())}

  @doc false
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(projection) do
    case normalize(projection) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, invalid_projection()}
    end
  end

  if @test_hooks do
    @doc false
    @spec preflight_for_test(term(), term()) :: {:ok, t()} | {:error, Error.t()}
    def preflight_for_test(_source, projection), do: validate(projection)

    @doc false
    @spec snapshot_for_test(t()) :: %{
            entries: nonempty_list(normalized_entry()),
            paths: nonempty_list(normalized_path())
          }
    def snapshot_for_test({@tag, entries, paths}) do
      %{entries: entries, paths: paths}
    end
  end

  defp normalize([_entry | _tail] = projection) do
    normalize_entries(projection, 0, MapSet.new(), %{}, 0, [], [])
  end

  defp normalize(_projection), do: :error

  defp normalize_entries([], _slot, _keys, _path_slots, _next_path_slot, entries, paths) do
    {:ok, {@tag, Enum.reverse(entries), Enum.reverse(paths)}}
  end

  defp normalize_entries(
         [{output_key, path} | rest],
         slot,
         keys,
         path_slots,
         next_path_slot,
         entries,
         paths
       ) do
    with true <- valid_output_key?(output_key),
         false <- MapSet.member?(keys, output_key),
         :ok <- validate_path(path) do
      {path_slot, path_slots, next_path_slot, paths} =
        intern_path(path, path_slots, next_path_slot, paths)

      normalize_entries(
        rest,
        slot + 1,
        MapSet.put(keys, output_key),
        path_slots,
        next_path_slot,
        [{slot, output_key, path_slot} | entries],
        paths
      )
    else
      _invalid -> :error
    end
  end

  defp normalize_entries(
         _improper_or_invalid,
         _slot,
         _keys,
         _path_slots,
         _next_path_slot,
         _entries,
         _paths
       ),
       do: :error

  defp valid_output_key?(key), do: is_atom(key) or is_binary(key)

  defp validate_path([segment | rest]) do
    with :ok <- validate_segment(segment), do: validate_path_tail(rest)
  end

  defp validate_path(_path), do: :error

  defp validate_path_tail([]), do: :ok

  defp validate_path_tail([segment | rest]) do
    with :ok <- validate_segment(segment), do: validate_path_tail(rest)
  end

  defp validate_path_tail(_improper), do: :error

  defp validate_segment(segment) when is_binary(segment) do
    if String.valid?(segment), do: :ok, else: :error
  end

  defp validate_segment(segment)
       when is_integer(segment) and segment >= 0 and segment <= @max_array_index,
       do: :ok

  defp validate_segment(_segment), do: :error

  defp intern_path(path, path_slots, next_path_slot, paths) do
    case Map.fetch(path_slots, path) do
      {:ok, path_slot} ->
        {path_slot, path_slots, next_path_slot, paths}

      :error ->
        {next_path_slot, Map.put(path_slots, path, next_path_slot), next_path_slot + 1,
         [{next_path_slot, path} | paths]}
    end
  end

  defp invalid_projection do
    %Error{reason: :invalid_projection, message: @invalid_projection_message}
  end
end
