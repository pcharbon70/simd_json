defmodule SimdJson.Native.PoolOptions do
  @moduledoc false

  @worker_range 1..64
  @queue_range 1..4096
  @default_queue_size 256

  @enforce_keys [
    :worker_count,
    :queue_capacity,
    :workers_explicit?,
    :queue_explicit?,
    :executor
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          worker_count: 1..64,
          queue_capacity: 1..4096,
          workers_explicit?: boolean(),
          queue_explicit?: boolean(),
          executor: :preproduction_threaded | :bounded_native_pool
        }

  @type option :: {:native_workers, term()} | {:native_queue_size, term()}

  @spec normalize([option()], pos_integer()) :: t()
  def normalize(options, schedulers_online)
      when is_list(options) and is_integer(schedulers_online) and schedulers_online > 0 do
    parsed = parse_options(options, %{})
    workers_explicit? = Map.has_key?(parsed, :native_workers)
    queue_explicit? = Map.has_key?(parsed, :native_queue_size)

    workers =
      parsed
      |> Map.get(:native_workers, default_worker_count(schedulers_online))
      |> validate_integer!(:native_workers, @worker_range)

    queue_size =
      parsed
      |> Map.get(:native_queue_size, @default_queue_size)
      |> validate_integer!(:native_queue_size, @queue_range)

    %__MODULE__{
      worker_count: workers,
      queue_capacity: queue_size,
      workers_explicit?: workers_explicit?,
      queue_explicit?: queue_explicit?,
      executor: :preproduction_threaded
    }
  end

  def normalize(options, _schedulers_online) when not is_list(options) do
    raise ArgumentError, "native pool configuration must be a keyword list"
  end

  def normalize(_options, schedulers_online) do
    raise ArgumentError,
          "online scheduler count must be a positive integer, got: #{inspect(schedulers_online)}"
  end

  @spec default_worker_count(pos_integer()) :: 1..32
  def default_worker_count(schedulers_online)
      when is_integer(schedulers_online) and schedulers_online > 0 do
    schedulers_online
    |> Kernel.+(1)
    |> div(2)
    |> min(32)
    |> max(1)
  end

  @spec worker_range() :: Range.t()
  def worker_range, do: @worker_range

  @spec queue_range() :: Range.t()
  def queue_range, do: @queue_range

  @spec default_queue_size() :: 256
  def default_queue_size, do: @default_queue_size

  defp parse_options([], parsed), do: parsed

  defp parse_options([{key, value} | rest], parsed)
       when key in [:native_workers, :native_queue_size] do
    if Map.has_key?(parsed, key) do
      raise ArgumentError, "duplicate native pool configuration key: #{inspect(key)}"
    end

    parse_options(rest, Map.put(parsed, key, value))
  end

  defp parse_options([{key, _value} | _rest], _parsed) do
    raise ArgumentError, "unknown native pool configuration key: #{inspect(key)}"
  end

  defp parse_options([invalid | _rest], _parsed) do
    raise ArgumentError,
          "native pool configuration must contain key-value pairs, got: #{inspect(invalid)}"
  end

  defp parse_options(_improper, _parsed) do
    raise ArgumentError, "native pool configuration must be a proper keyword list"
  end

  defp validate_integer!(value, _key, first..last//_step)
       when is_integer(value) and value >= first and value <= last,
       do: value

  defp validate_integer!(value, key, range) do
    raise ArgumentError,
          "#{inspect(key)} must be an integer in #{range.first}..#{range.last}, got: #{inspect(value)}"
  end
end
