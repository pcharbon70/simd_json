defmodule SimdJson.Native.PoolTelemetryTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.OperationCoordinator

  @events [
    [:simd_json, :job, :start],
    [:simd_json, :job, :stop],
    [:simd_json, :job, :exception],
    [:simd_json, :queue, :rejected],
    [:simd_json, :job, :cancelled]
  ]

  setup do
    handler = "simd-json-pool-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach_many(
        handler,
        @events,
        fn event, measurements, metadata, _config ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  # covers: simd_json.native_pool.telemetry simd_json.native_pool.redacted_snapshot
  test "public operations emit bounded redacted start and stop events" do
    secret = "private-key-#{System.unique_integer([:positive])}"
    input = Jason.encode!(%{secret => 7})

    assert {:ok, document} = SimdJson.open(input)
    assert :ok = SimdJson.close(document)

    assert_receive {:telemetry, [:simd_json, :job, :start], start, %{operation: :open}}
    assert start.input_bytes == byte_size(input)
    assert start.worker_count in 1..64
    assert start.queue_capacity in 1..4096
    assert start.queue_length >= 0

    assert_receive {:telemetry, [:simd_json, :job, :stop], stop,
                    %{operation: :open, outcome: :ok}}

    assert stop.duration >= 0
    assert stop.queue_duration >= 0
    assert stop.execution_duration > 0
    assert stop.conversion_duration >= 0

    rendered = inspect({start, stop})
    refute rendered =~ secret
    refute rendered =~ input
    refute rendered =~ inspect(self())
    refute rendered =~ "#Reference<"
  end

  test "private decode jobs emit redacted queue and execution telemetry" do
    secret = "decode-secret-#{System.unique_integer([:positive])}"
    input = Jason.encode!(%{secret => [1, 2, 3]})

    assert {:ok, %{^secret => [1, 2, 3]}} =
             SimdJson.decode(input)

    assert_receive {:telemetry, [:simd_json, :job, :start], start, %{operation: :decode}}

    assert_receive {:telemetry, [:simd_json, :job, :stop], stop,
                    %{operation: :decode, outcome: :ok}}

    assert start.input_bytes == byte_size(input)
    assert stop.queue_duration >= 0
    assert stop.execution_duration > 0
    refute inspect({start, stop}) =~ secret
    refute inspect({start, stop}) =~ input
  end

  # covers: simd_json.native_pool.direct_stream_delivery simd_json.native_pool.telemetry simd_json.stream_execution.single_delivery_handoff
  test "direct stream batches retain bounded timing and lifecycle telemetry" do
    rows =
      SimdJson.stream(~s([{"value":1},{"value":2},{"value":3}]),
        path: [],
        fields: [value: ["value"]],
        batch_size: 2,
        max_batch_bytes: 1_024
      )
      |> Enum.to_list()

    assert rows == [%{value: 1}, %{value: 2}, %{value: 3}]

    for expected_rows <- [2, 1] do
      assert_receive {:telemetry, [:simd_json, :job, :start], _start, %{operation: :next_batch}}

      assert_receive {:telemetry, [:simd_json, :job, :stop], stop,
                      %{operation: :next_batch, outcome: :ok}}

      assert stop.output_rows == expected_rows
      assert stop.queue_duration >= 0
      assert stop.execution_duration > 0
      assert stop.conversion_duration >= 0
    end

    await_no_live_requests()
  end

  defp await_no_live_requests(attempts \\ 100)

  defp await_no_live_requests(0),
    do:
      flunk("direct stream request did not quiesce: #{inspect(OperationCoordinator.snapshot())}")

  defp await_no_live_requests(attempts) do
    if OperationCoordinator.snapshot().live_requests == 0 do
      :ok
    else
      Process.sleep(5)
      await_no_live_requests(attempts - 1)
    end
  end
end
