defmodule SimdJson.Native.Telemetry do
  @moduledoc false

  @start [:simd_json, :job, :start]
  @stop [:simd_json, :job, :stop]
  @exception [:simd_json, :job, :exception]
  @rejected [:simd_json, :queue, :rejected]
  @cancelled [:simd_json, :job, :cancelled]

  def start(operation, input_bytes, capacity) do
    measurements = %{
      system_time: System.system_time(),
      input_bytes: input_bytes,
      queue_length: capacity.queued_jobs,
      worker_count: capacity.worker_count,
      queue_capacity: capacity.queue_capacity
    }

    :telemetry.execute(@start, measurements, %{operation: operation})
  end

  def stop(operation, started_at, native, conversion_duration, response) do
    measurements = %{
      duration: System.monotonic_time() - started_at,
      queue_duration: native_to_native_time(native.queue_duration),
      execution_duration: native_to_native_time(native.execution_duration),
      conversion_duration: conversion_duration,
      output_rows: output_rows(response),
      output_bytes: output_bytes(response)
    }

    metadata = %{operation: operation, outcome: outcome(response)}
    :telemetry.execute(@stop, measurements, metadata)

    case metadata.outcome do
      :cancelled -> :telemetry.execute(@cancelled, measurements, metadata)
      :native_failure -> :telemetry.execute(@exception, measurements, metadata)
      _outcome -> :ok
    end
  end

  def rejected(operation, capacity) do
    :telemetry.execute(
      @rejected,
      %{
        queue_length: capacity.queued_jobs,
        worker_count: capacity.worker_count,
        queue_capacity: capacity.queue_capacity
      },
      %{operation: operation, outcome: :busy}
    )
  end

  defp native_to_native_time(microseconds),
    do: System.convert_time_unit(microseconds, :microsecond, :native)

  defp outcome({:ok, _value}), do: :ok
  defp outcome(:ok), do: :ok
  defp outcome({:error, %{reason: reason}}), do: reason
  defp outcome({:error, _error}), do: :native_failure

  defp output_rows({:ok, %{produced_rows: rows}}) when is_integer(rows), do: rows
  defp output_rows(_response), do: 0

  defp output_bytes({:ok, %{encoded_bytes: bytes}}) when is_integer(bytes), do: bytes
  defp output_bytes(_response), do: 0
end
