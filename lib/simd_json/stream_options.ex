defmodule SimdJson.StreamOptions do
  @moduledoc false

  alias SimdJson.Document
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Projection

  @tag :simd_json_stream_options_v1
  @accepted_options [:path, :fields, :batch_size, :max_batch_bytes]
  @required_options [:path, :fields]
  @default_batch_size 1_000
  @maximum_batch_size 10_000
  @default_max_batch_bytes 8_388_608
  @maximum_max_batch_bytes 67_108_864
  @invalid_source_message "expected JSON input to be a binary or SimdJson.Document"
  @invalid_options_message "invalid stream options"
  @invalid_path_message "invalid stream path"
  @invalid_fields_message "invalid stream fields"
  @invalid_batch_size_message "invalid stream batch_size"
  @invalid_max_batch_bytes_message "invalid stream max_batch_bytes"
  @test_hooks Mix.env() == :test

  @typedoc false
  @type source_kind :: :binary | :document

  @typedoc false
  @type target_path :: [Projection.segment()]

  @typedoc false
  @type batch_size :: 1..10_000

  @typedoc false
  @type max_batch_bytes :: 1..67_108_864

  @typedoc false
  @type explicit_option :: :path | :fields | :batch_size | :max_batch_bytes

  @typedoc false
  @type payload :: %{
          source: binary() | Document.t(),
          owner: pid(),
          target_path: target_path(),
          fields: Projection.t()
        }

  @typedoc false
  @opaque t ::
            {:simd_json_stream_options_v1, source_kind(), batch_size(), max_batch_bytes(),
             [explicit_option()], (-> payload())}

  @doc false
  @spec new(term(), term()) :: t()
  def new(source, options) do
    {source_kind, checked_source} = classify_source(source)
    parsed = parse_options(options)
    target_path = validate_target_path(Map.fetch!(parsed, :path))
    fields = validate_fields(Map.fetch!(parsed, :fields))
    batch_size = validate_batch_size(Map.get(parsed, :batch_size, @default_batch_size))

    max_batch_bytes =
      validate_max_batch_bytes(Map.get(parsed, :max_batch_bytes, @default_max_batch_bytes))

    explicit_options = Enum.filter(@accepted_options, &Map.has_key?(parsed, &1))

    build(
      source_kind,
      checked_source,
      self(),
      target_path,
      fields,
      batch_size,
      max_batch_bytes,
      explicit_options
    )
  end

  @doc false
  @spec inspect_metadata(t()) :: %{
          source_kind: source_kind(),
          batch_size: batch_size(),
          max_batch_bytes: max_batch_bytes()
        }
  def inspect_metadata({@tag, source_kind, batch_size, max_batch_bytes, _explicit, _payload}) do
    %{source_kind: source_kind, batch_size: batch_size, max_batch_bytes: max_batch_bytes}
  end

  if @test_hooks do
    @doc false
    @spec snapshot_for_test(t()) :: %{
            source_kind: source_kind(),
            owner_matches: boolean(),
            target_path: target_path(),
            fields: map(),
            batch_size: batch_size(),
            max_batch_bytes: max_batch_bytes(),
            explicit_options: [explicit_option()]
          }
    def snapshot_for_test(
          {@tag, source_kind, batch_size, max_batch_bytes, explicit_options, payload_fun}
        ) do
      payload = payload_fun.()

      %{
        source_kind: source_kind,
        owner_matches: payload.owner == self(),
        target_path: payload.target_path,
        fields: Projection.snapshot_for_test(payload.fields),
        batch_size: batch_size,
        max_batch_bytes: max_batch_bytes,
        explicit_options: explicit_options
      }
    end
  end

  defp build(
         source_kind,
         source,
         owner,
         target_path,
         fields,
         batch_size,
         max_batch_bytes,
         explicit_options
       ) do
    payload = %{
      source: source,
      owner: owner,
      target_path: target_path,
      fields: fields
    }

    {@tag, source_kind, batch_size, max_batch_bytes, explicit_options, fn -> payload end}
  end

  defp classify_source(source) when is_binary(source), do: {:binary, source}

  defp classify_source(%Document{__resource__: resource} = document)
       when is_reference(resource) do
    try do
      case BuildSmoke.document_owner_state(resource) do
        state when state in [:open, :closing, :closed, :not_owner] -> {:document, document}
        _state -> invalid_source!()
      end
    rescue
      ArgumentError -> invalid_source!()
      ErlangError -> invalid_source!()
    end
  end

  defp classify_source(_source), do: invalid_source!()

  defp parse_options(options) when is_list(options) do
    options
    |> parse_option_entries(MapSet.new(), %{})
    |> require_options()
  end

  defp parse_options(_options), do: invalid_options!()

  defp parse_option_entries([], _seen, parsed), do: parsed

  defp parse_option_entries([{key, value} | rest], seen, parsed)
       when key in @accepted_options do
    if MapSet.member?(seen, key) do
      invalid_options!()
    else
      parse_option_entries(rest, MapSet.put(seen, key), Map.put(parsed, key, value))
    end
  end

  defp parse_option_entries([_invalid | _rest], _seen, _parsed), do: invalid_options!()
  defp parse_option_entries(_improper, _seen, _parsed), do: invalid_options!()

  defp require_options(parsed) do
    if Enum.all?(@required_options, &Map.has_key?(parsed, &1)) do
      parsed
    else
      invalid_options!()
    end
  end

  defp validate_target_path(path) do
    case Projection.validate_target_path(path) do
      {:ok, target_path} -> target_path
      :error -> raise ArgumentError, @invalid_path_message
    end
  end

  defp validate_fields(fields) do
    case Projection.validate(fields) do
      {:ok, normalized} -> normalized
      {:error, _error} -> raise ArgumentError, @invalid_fields_message
    end
  end

  defp validate_batch_size(batch_size)
       when is_integer(batch_size) and batch_size >= 1 and
              batch_size <= @maximum_batch_size,
       do: batch_size

  defp validate_batch_size(_batch_size),
    do: raise(ArgumentError, @invalid_batch_size_message)

  defp validate_max_batch_bytes(max_batch_bytes)
       when is_integer(max_batch_bytes) and max_batch_bytes >= 1 and
              max_batch_bytes <= @maximum_max_batch_bytes,
       do: max_batch_bytes

  defp validate_max_batch_bytes(_max_batch_bytes),
    do: raise(ArgumentError, @invalid_max_batch_bytes_message)

  defp invalid_source!, do: raise(ArgumentError, @invalid_source_message)
  defp invalid_options!, do: raise(ArgumentError, @invalid_options_message)
end
