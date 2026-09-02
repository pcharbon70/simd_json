defmodule SimdJson.Qualification.StreamRuntimeQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  @heartbeat_period_ms 2
  @p95_budget_us 50_000
  @p99_budget_us 250_000
  @maximum_budget_us 500_000

  setup do
    {:ok, _} = Application.ensure_all_started(:simd_json)
    wait_for_quiescence()

    on_exit(fn ->
      {:ok, _} = Application.ensure_all_started(:simd_json)
      wait_for_quiescence()
    end)

    :ok
  end

  # covers: simd_json.stream_execution.threaded_stream_work simd_json.stream_execution.scheduler_qualification simd_json.stream_execution.single_in_flight_batch simd_json.stream_execution.no_prefetch
  test "concurrent public streams preserve heartbeat budgets and native accounting" do
    rows = 20_000
    valid = array_fixture(rows)
    malformed = binary_part(valid, 0, byte_size(valid) - 1)
    heartbeat = start_heartbeat()
    baseline = BuildSmoke.execution_snapshot()

    results =
      [
        fn -> reduce_sum(valid) end,
        fn -> reduce_sum(valid, 137) end,
        fn -> capture_error(malformed) end,
        fn -> capture_error(~s({"rows":{"value":1}}), path: ["rows"]) end,
        fn ->
          capture_error(~s([{"value":"#{String.duplicate("x", 512)}"}]), max_batch_bytes: 64)
        end
      ]
      |> Enum.map(&Task.async/1)
      |> Task.await_many(120_000)

    heartbeat = stop_heartbeat(heartbeat)
    percentiles = percentiles(heartbeat.intervals)

    assert Enum.at(results, 0) == div(rows * (rows + 1), 2)
    assert Enum.at(results, 1) == div(137 * 138, 2)
    assert Enum.at(results, 2) == :unexpected_eof
    assert Enum.at(results, 3) == :incorrect_type
    assert Enum.at(results, 4) == :batch_too_large
    assert heartbeat.samples > 0
    assert percentiles.p95 <= @p95_budget_us
    assert percentiles.p99 <= @p99_budget_us
    assert percentiles.maximum <= @maximum_budget_us

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert_stream_baseline(final, baseline)
    assert final.stream_setup_worker_entries == baseline.stream_setup_worker_entries + 5
    assert final.stream_batch_worker_entries > baseline.stream_batch_worker_entries

    write_evidence("stream-scheduler.json", %{
      "schema_version" => 1,
      "source_revision" => source_revision(),
      "fixture_rows" => rows,
      "fixture_bytes" => byte_size(valid),
      "fixture_sha256" => sha256(valid),
      "heartbeat_period_ms" => @heartbeat_period_ms,
      "heartbeat_samples" => heartbeat.samples,
      "raw_intervals_us" => heartbeat.intervals,
      "percentiles_us" => stringify(percentiles),
      "budgets_us" => %{
        "p95" => @p95_budget_us,
        "p99" => @p99_budget_us,
        "maximum" => @maximum_budget_us
      },
      "native_baseline" => stringify(baseline),
      "native_final" => stringify(final),
      "result" => "pass"
    })
  end

  # covers: simd_json.stream_execution.lazy_setup simd_json.stream_execution.no_prefetch simd_json.stream_execution.single_in_flight_batch simd_json.stream_execution.early_halt_cleanup
  test "suspension is a native demand boundary within and between batches" do
    input = array_fixture(6)
    baseline = BuildSmoke.execution_snapshot()
    mailbox_before = mailbox_length()

    stream =
      SimdJson.stream(input,
        path: [],
        fields: [value: ["value"]],
        batch_size: 2,
        max_batch_bytes: 1_024
      )

    Process.sleep(20)
    assert BuildSmoke.execution_snapshot() == baseline
    assert mailbox_length() == mailbox_before

    reducer = fn row, acc -> {:suspend, [row.value | acc]} end
    {:suspended, [1], continuation} = Enumerable.reduce(stream, {:cont, []}, reducer)
    first_pause = BuildSmoke.execution_snapshot()
    assert first_pause.stream_setup_worker_entries == baseline.stream_setup_worker_entries + 1
    assert first_pause.stream_batch_worker_entries == baseline.stream_batch_worker_entries + 1

    Process.sleep(20)

    assert BuildSmoke.execution_snapshot().stream_batch_worker_entries ==
             first_pause.stream_batch_worker_entries

    assert mailbox_length() == mailbox_before
    {:suspended, [2, 1], continuation} = continuation.({:cont, [1]})
    within_batch = BuildSmoke.execution_snapshot()
    assert within_batch.stream_batch_worker_entries == first_pause.stream_batch_worker_entries

    {:suspended, [3, 2, 1], continuation} = continuation.({:cont, [2, 1]})
    between_batches = BuildSmoke.execution_snapshot()

    assert between_batches.stream_batch_worker_entries ==
             first_pause.stream_batch_worker_entries + 1

    assert {:halted, [3, 2, 1]} = continuation.({:halt, [3, 2, 1]})

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert_stream_baseline(final, baseline)

    write_evidence("stream-demand.json", %{
      "schema_version" => 1,
      "source_revision" => source_revision(),
      "batch_size" => 2,
      "unreduced_setup_entries" => 0,
      "first_pause_batch_entries" => 1,
      "within_batch_additional_entries" => 0,
      "between_batch_additional_entries" => 1,
      "mailbox_growth" => 0,
      "observed_prefix" => [1, 2, 3],
      "scope" => "per-stream demand only; no global admission or fairness claim",
      "result" => "pass"
    })
  end

  defp reduce_sum(input, take \\ :all) do
    enumerable =
      SimdJson.stream(input,
        path: [],
        fields: [value: ["value"]],
        batch_size: 64,
        max_batch_bytes: 64 * 1_024
      )

    enumerable = if take == :all, do: enumerable, else: Enum.take(enumerable, take)
    Enum.reduce(enumerable, 0, fn row, total -> total + row.value end)
  end

  defp capture_error(input, overrides \\ []) do
    options =
      Keyword.merge(
        [path: [], fields: [value: ["value"]], batch_size: 32, max_batch_bytes: 1_024],
        overrides
      )

    try do
      input |> SimdJson.stream(options) |> Enum.to_list()
      :unexpected_success
    rescue
      error in Error -> error.reason
    end
  end

  defp array_fixture(rows) do
    body = Enum.map_join(1..rows, ",", &~s({"value":#{&1},"ignored":"payload"}))
    ["[", body, "]"] |> IO.iodata_to_binary()
  end

  defp start_heartbeat do
    spawn_link(fn -> heartbeat_loop(System.monotonic_time(:microsecond), []) end)
  end

  defp heartbeat_loop(previous, intervals) do
    receive do
      {:stop, caller, reference} ->
        send(caller, {:heartbeat, reference, Enum.reverse(intervals)})
    after
      @heartbeat_period_ms ->
        now = System.monotonic_time(:microsecond)
        heartbeat_loop(now, [now - previous | intervals])
    end
  end

  defp stop_heartbeat(pid) do
    reference = make_ref()
    send(pid, {:stop, self(), reference})
    assert_receive {:heartbeat, ^reference, intervals}, 2_000
    %{samples: length(intervals), intervals: intervals}
  end

  defp percentiles(intervals) do
    sorted = Enum.sort(intervals)

    %{
      p50: percentile(sorted, 50),
      p95: percentile(sorted, 95),
      p99: percentile(sorted, 99),
      maximum: List.last(sorted)
    }
  end

  defp percentile(sorted, percentage) do
    Enum.at(sorted, max(ceil(length(sorted) * percentage / 100) - 1, 0))
  end

  defp assert_stream_baseline(snapshot, baseline) do
    for gauge <- [
          :live_stream_setup_operations,
          :live_stream_batch_operations,
          :live_stream_cursor_resources,
          :retained_stream_cursor_parents,
          :live_operations,
          :retained_inputs,
          :queued_operations,
          :running_operations
        ] do
      assert Map.fetch!(snapshot, gauge) == Map.fetch!(baseline, gauge),
             "#{gauge} did not return to baseline"
    end
  end

  defp wait_for_quiescence(attempts \\ 800)

  defp wait_for_quiescence(0),
    do: flunk("stream runtime did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}")

  defp wait_for_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and snapshot.live_operations == 0 and
         snapshot.live_stream_setup_operations == 0 and
         snapshot.live_stream_batch_operations == 0 and
         snapshot.live_stream_cursor_resources == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end

  defp mailbox_length, do: self() |> Process.info(:message_queue_len) |> elem(1)
  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp source_revision do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {revision, 0} -> String.trim(revision)
      _ -> "unavailable"
    end
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp write_evidence(filename, report) do
    if directory = System.get_env("SIMD_JSON_QUALIFICATION_DIR") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, filename), [:json.encode(report), "\n"])
    end
  end
end
