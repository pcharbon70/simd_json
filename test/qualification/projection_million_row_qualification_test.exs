defmodule SimdJson.Qualification.ProjectionMillionRowQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  @fixture_path "bench/stream_fixtures/million.json.gz"
  @fixture_bytes 45_666_793
  @fixture_sha256 "2171d30d6e247aede4318ba732e60e41af513be04b3d148cd26b92f218042ea7"
  @heartbeat_period_ms 2
  @p95_budget_us 50_000
  @p99_budget_us 250_000
  @maximum_budget_us 500_000
  @maximum_select_peak_bytes 134_217_728
  @maximum_select_fraction_of_jason 0.30
  @projection [
    first_id: [0, "id"],
    middle_value: [499_999, "value"],
    last_id: [999_999, "id"]
  ]
  @idle_gauges [
    :live_operations,
    :retained_inputs,
    :queued_operations,
    :running_operations,
    :live_projection_operations,
    :retained_projection_binaries,
    :retained_projection_documents,
    :live_projection_environments,
    :live_projection_plans,
    :live_projection_slots,
    :live_projection_temporary_document_graphs
  ]

  # covers: simd_json.projection_execution.large_projection_responsiveness simd_json.projection_execution.sparse_allocation_advantage simd_json.projection_execution.native_memory_baseline simd_json.projection_execution.threaded_projection simd_json.projection_api.binary_multi_select
  @tag timeout: 180_000
  test "selects sparse values across the exact million-row stream fixture" do
    {:ok, _applications} = Application.ensure_all_started(:simd_json)
    source = @fixture_path |> File.read!() |> :zlib.gunzip()

    assert byte_size(source) == @fixture_bytes
    assert sha256(source) == @fixture_sha256

    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()
    heartbeat = start_heartbeat()

    {select_result, select_elapsed_us, select_peak_bytes} =
      measure_peak(fn -> {SimdJson.select(source, @projection), nil} end)

    intervals = stop_heartbeat(heartbeat)
    percentiles = percentiles(intervals)

    assert {:ok, %{first_id: 1, middle_value: 500_000, last_id: 1_000_000}} = select_result
    assert length(intervals) > 0
    assert percentiles.p95 <= @p95_budget_us
    assert percentiles.p99 <= @p99_budget_us
    assert percentiles.maximum <= @maximum_budget_us

    {jason_result, jason_elapsed_us, jason_peak_bytes} =
      measure_peak(fn ->
        decoded = Jason.decode!(source)

        result = %{
          first_id: get_in(decoded, [Access.at(0), "id"]),
          middle_value: get_in(decoded, [Access.at(499_999), "value"]),
          last_id: get_in(decoded, [Access.at(999_999), "id"])
        }

        {result, decoded}
      end)

    assert %{first_id: 1, middle_value: 500_000, last_id: 1_000_000} = jason_result
    assert select_peak_bytes <= @maximum_select_peak_bytes
    assert select_peak_bytes / max(jason_peak_bytes, 1) <= @maximum_select_fraction_of_jason

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()

    Enum.each(@idle_gauges, fn gauge ->
      assert Map.fetch!(final, gauge) == Map.fetch!(baseline, gauge),
             "native gauge #{gauge} did not return to baseline"
    end)

    write_evidence(%{
      "schema_version" => 1,
      "fixture" => %{
        "path" => @fixture_path,
        "bytes" => byte_size(source),
        "rows" => 1_000_000,
        "sha256" => sha256(source)
      },
      "projection" => ["0.id", "499999.value", "999999.id"],
      "result" => %{"first_id" => 1, "middle_value" => 500_000, "last_id" => 1_000_000},
      "select" => %{
        "elapsed_microseconds" => select_elapsed_us,
        "process_peak_bytes" => select_peak_bytes
      },
      "jason_decode_and_lookup" => %{
        "elapsed_microseconds" => jason_elapsed_us,
        "process_peak_bytes" => jason_peak_bytes
      },
      "memory_acceptance" => %{
        "select_fraction_of_jason" => select_peak_bytes / max(jason_peak_bytes, 1),
        "maximum_fraction" => @maximum_select_fraction_of_jason,
        "maximum_select_peak_bytes" => @maximum_select_peak_bytes
      },
      "heartbeat" => %{
        "period_milliseconds" => @heartbeat_period_ms,
        "samples" => length(intervals),
        "p95_microseconds" => percentiles.p95,
        "p99_microseconds" => percentiles.p99,
        "maximum_microseconds" => percentiles.maximum
      },
      "native_baseline" => stringify_map(baseline),
      "native_final" => stringify_map(final),
      "status" => "pass"
    })
  end

  defp start_heartbeat do
    spawn_link(fn -> heartbeat_loop(System.monotonic_time(:microsecond), []) end)
  end

  defp measure_peak(work) do
    parent = self()
    started = System.monotonic_time(:microsecond)

    {worker, monitor} =
      spawn_monitor(fn ->
        {reported, retained} = work.()
        send(parent, {:measured_result, self(), reported})
        receive do: ({:release, ^parent} -> :erlang.phash2(retained))
      end)

    sampler = spawn_link(fn -> sample_memory(parent, worker, 0) end)

    assert_receive {:measured_result, ^worker, value}, 120_000
    elapsed_us = System.monotonic_time(:microsecond) - started
    send(sampler, {:stop, self()})
    assert_receive {:memory_peak, ^sampler, peak_bytes}, 5_000
    send(worker, {:release, self()})
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000
    {value, elapsed_us, peak_bytes}
  end

  defp sample_memory(parent, worker, peak) do
    receive do
      {:stop, caller} ->
        current = process_memory(worker)
        send(caller, {:memory_peak, self(), max(peak, current)})
    after
      1 -> sample_memory(parent, worker, max(peak, process_memory(worker)))
    end
  end

  defp process_memory(pid) do
    case Process.info(pid, :memory) do
      {:memory, bytes} -> bytes
      nil -> 0
    end
  end

  defp heartbeat_loop(previous, intervals) do
    receive do
      {:stop, caller, reference} ->
        send(caller, {:heartbeat_stopped, reference, Enum.reverse(intervals)})
    after
      @heartbeat_period_ms ->
        now = System.monotonic_time(:microsecond)
        heartbeat_loop(now, [now - previous | intervals])
    end
  end

  defp stop_heartbeat(pid) do
    reference = make_ref()
    send(pid, {:stop, self(), reference})
    assert_receive {:heartbeat_stopped, ^reference, intervals}, 5_000
    intervals
  end

  defp percentiles(values) do
    sorted = Enum.sort(values)
    %{p95: percentile(sorted, 95), p99: percentile(sorted, 99), maximum: List.last(sorted)}
  end

  defp percentile(sorted, percent) do
    Enum.at(sorted, max(ceil(length(sorted) * percent / 100) - 1, 0))
  end

  defp wait_for_quiescence(attempts \\ 2_000)

  defp wait_for_quiescence(0) do
    flunk(
      "million-row projection did not return to baseline: " <>
        "#{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and
         Enum.all?(@idle_gauges, &(Map.fetch!(snapshot, &1) == 0)) do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end

  defp write_evidence(report) do
    if directory = System.get_env("SIMD_JSON_QUALIFICATION_DIR") do
      File.mkdir_p!(directory)

      File.write!(Path.join(directory, "projection-million-row.json"), [
        :json.encode(report),
        "\n"
      ])
    end
  end

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  defp stringify_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
