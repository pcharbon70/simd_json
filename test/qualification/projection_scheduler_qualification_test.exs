defmodule SimdJson.Qualification.ProjectionSchedulerQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  @fixture_bytes 4 * 1_024 * 1_024
  @rounds 20
  @heartbeat_period_ms 2
  @minimum_samples 40
  @p95_budget_us 50_000
  @p99_budget_us 250_000
  @maximum_budget_us 500_000
  @dirty_scheduler_budget 0.25
  @projection [target: ["payload", "target"]]
  @missing [missing: ["payload", "missing"]]
  @wrong_type [wrong_type: ["payload", "container", "field"]]
  @idle_gauges [
    :live_operations,
    :retained_inputs,
    :queued_operations,
    :queued_cleanup,
    :running_operations,
    :live_documents,
    :live_document_controls,
    :dispatcher_queued_cleanup,
    :dispatcher_active_cleanup,
    :retained_failed_cleanup,
    :live_projection_operations,
    :retained_projection_binaries,
    :retained_projection_documents,
    :live_projection_environments,
    :live_projection_plans,
    :live_projection_slots,
    :live_projection_temporary_document_graphs
  ]

  setup do
    reset_runtime!()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn -> reset_runtime!() end)

    %{baseline: baseline}
  end

  # covers: simd_json.projection_execution.scheduler_qualification simd_json.projection_execution.threaded_projection simd_json.projection_execution.one_correlated_operation simd_json.projection_execution.native_memory_baseline simd_json.projection_execution.large_projection_responsiveness simd_json.native_execution.bounded_nif_entry simd_json.native_execution.no_fallback
  @tag timeout: 180_000
  test "formal public projection profile preserves scheduler and boundary budgets", %{
    baseline: baseline
  } do
    valid = large_sparse_json(@fixture_bytes)
    malformed = binary_part(valid, 0, byte_size(valid) - 1)
    concurrency = min(max(System.schedulers_online(), 2), 4)
    fixture_digest = sha256(valid)

    warm_up(valid, malformed)
    wait_for_quiescence()

    admissions_before = ThreadedOperation.admission_snapshot_for_test()
    counters_before = BuildSmoke.execution_snapshot()
    previous_wall_time = :erlang.system_flag(:scheduler_wall_time, true)

    {case_results, cancelled_count, heartbeat, utilization} =
      try do
        wall_before = scheduler_wall_time_snapshot()
        heartbeat_pid = start_heartbeat()

        cases =
          [
            :binary_valid,
            :binary_malformed,
            :binary_missing,
            :binary_wrong_type,
            :document_valid,
            :document_missing
          ]
          |> Enum.flat_map(&List.duplicate(&1, concurrency))

        case_results =
          cases
          |> Enum.map(fn kind ->
            Task.async(fn -> run_rounds(kind, valid, malformed) end)
          end)
          |> Task.await_many(120_000)

        cancelled_count = run_cancelled_call(valid)
        heartbeat = stop_heartbeat(heartbeat_pid)
        wall_after = scheduler_wall_time_snapshot()

        {case_results, cancelled_count, heartbeat, scheduler_utilization(wall_before, wall_after)}
      after
        :erlang.system_flag(:scheduler_wall_time, previous_wall_time)
      end

    assert Enum.all?(case_results, &(&1 == :ok))
    assert cancelled_count == 1

    percentiles = heartbeat_percentiles(heartbeat.intervals_us)
    assert heartbeat.samples >= @minimum_samples
    assert percentiles.p95 <= @p95_budget_us
    assert percentiles.p99 <= @p99_budget_us
    assert percentiles.maximum <= @maximum_budget_us
    assert utilization.normal.total > 0
    assert utilization.dirty_cpu.total > 0
    assert utilization.dirty_io.total > 0
    assert utilization.dirty_cpu.ratio < @dirty_scheduler_budget
    assert utilization.dirty_io.ratio < @dirty_scheduler_budget

    attempted = 6 * concurrency * @rounds + cancelled_count
    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    admissions_after = ThreadedOperation.admission_snapshot_for_test()

    assert admissions_after.projection == admissions_before.projection + attempted

    assert final.projection_worker_entries ==
             counters_before.projection_worker_entries + attempted

    assert_idle(final, baseline)

    report = %{
      "schema_version" => 1,
      "source_revision" => git_identity("HEAD"),
      "source_tree" => git_identity("HEAD^{tree}"),
      "command" =>
        "mix test test/qualification/projection_scheduler_qualification_test.exs --seed 0",
      "environment" => environment(),
      "profile" => %{
        "fixture_bytes" => byte_size(valid),
        "fixture_sha256" => fixture_digest,
        "projection_topology" => ["payload.target"],
        "case_kinds" => [
          "binary_valid",
          "binary_malformed",
          "binary_missing",
          "binary_wrong_type",
          "document_valid",
          "document_missing",
          "cancelled"
        ],
        "concurrency_per_non_cancelled_kind" => concurrency,
        "rounds_per_caller" => @rounds,
        "warm_up_calls" => 4,
        "attempted_selections" => attempted,
        "heartbeat_period_ms" => @heartbeat_period_ms,
        "percentile_method" => "nearest-rank"
      },
      "thresholds" => %{
        "minimum_heartbeat_samples" => @minimum_samples,
        "p95_microseconds" => @p95_budget_us,
        "p99_microseconds" => @p99_budget_us,
        "maximum_microseconds" => @maximum_budget_us,
        "dirty_scheduler_ratio" => @dirty_scheduler_budget
      },
      "heartbeat" => %{
        "samples" => heartbeat.samples,
        "raw_intervals_microseconds" => heartbeat.intervals_us,
        "p50_microseconds" => percentiles.p50,
        "p95_microseconds" => percentiles.p95,
        "p99_microseconds" => percentiles.p99,
        "maximum_microseconds" => percentiles.maximum
      },
      "scheduler_wall_time" => stringify_scheduler_utilization(utilization),
      "worker_accounting" => %{
        "attempted_selections" => attempted,
        "admission_delta" => admissions_after.projection - admissions_before.projection,
        "worker_entry_delta" =>
          final.projection_worker_entries - counters_before.projection_worker_entries
      },
      "native_baseline" => stringify_map(baseline),
      "native_final" => stringify_map(final),
      "result" => "pass"
    }

    write_evidence("projection-scheduler.json", report)

    IO.puts(
      "projection_scheduler samples=#{heartbeat.samples} p95_us=#{percentiles.p95} " <>
        "p99_us=#{percentiles.p99} max_us=#{percentiles.maximum} attempts=#{attempted}"
    )
  end

  defp warm_up(valid, malformed) do
    assert {:ok, %{target: 42}} = SimdJson.select(valid, @projection)
    assert {:error, %Error{reason: reason}} = SimdJson.select(malformed, @projection)
    assert reason in [:invalid_json, :unexpected_eof]
    assert {:error, %Error{reason: :no_such_field}} = SimdJson.select(valid, @missing)
    assert {:error, %Error{reason: :incorrect_type}} = SimdJson.select(valid, @wrong_type)
  end

  defp run_rounds(kind, valid, malformed) do
    Enum.each(1..@rounds, fn _round -> run_case(kind, valid, malformed) end)
    :ok
  end

  defp run_case(:binary_valid, valid, _malformed) do
    assert {:ok, %{target: 42}} = SimdJson.select(valid, @projection)
  end

  defp run_case(:binary_malformed, _valid, malformed) do
    assert {:error, %Error{reason: reason}} = SimdJson.select(malformed, @projection)
    assert reason in [:invalid_json, :unexpected_eof]
  end

  defp run_case(:binary_missing, valid, _malformed) do
    assert {:error, %Error{reason: :no_such_field}} = SimdJson.select(valid, @missing)
  end

  defp run_case(:binary_wrong_type, valid, _malformed) do
    assert {:error, %Error{reason: :incorrect_type}} = SimdJson.select(valid, @wrong_type)
  end

  defp run_case(:document_valid, valid, _malformed) do
    assert {:ok, document} = SimdJson.open(valid)
    assert {:ok, %{target: 42}} = SimdJson.select(document, @projection)
    assert :ok = SimdJson.close(document)
  end

  defp run_case(:document_missing, valid, _malformed) do
    assert {:ok, document} = SimdJson.open(valid)
    assert {:error, %Error{reason: :no_such_field}} = SimdJson.select(document, @missing)
    assert :ok = SimdJson.close(document)
  end

  defp run_cancelled_call(valid) do
    parent = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        result =
          SimdJson.Native.ProjectionOperation.select_for_test(valid, @projection,
            pause: {:during_traversal, parent}
          )

        send(parent, {:unexpected_cancelled_projection_result, result})
      end)

    assert_receive {:simd_json_native_boundary, _request_ref, :projection, _generation,
                    :during_traversal},
                   5_000

    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 5_000
    refute_receive {:unexpected_cancelled_projection_result, _result}, 10
    1
  end

  defp start_heartbeat do
    spawn_link(fn -> heartbeat_loop(System.monotonic_time(:microsecond), []) end)
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
    %{samples: length(intervals), intervals_us: intervals}
  end

  defp heartbeat_percentiles(intervals) do
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

  defp scheduler_wall_time_snapshot do
    :scheduler_wall_time_all
    |> :erlang.statistics()
    |> Map.new(fn {scheduler, active, total} -> {scheduler, {active, total}} end)
  end

  defp scheduler_utilization(before_snapshot, after_snapshot) do
    normal = :erlang.system_info(:schedulers)
    dirty_cpu = :erlang.system_info(:dirty_cpu_schedulers)
    dirty_io = :erlang.system_info(:dirty_io_schedulers)

    %{
      normal: utilization_for(before_snapshot, after_snapshot, 1, normal),
      dirty_cpu: utilization_for(before_snapshot, after_snapshot, normal + 1, dirty_cpu),
      dirty_io: utilization_for(before_snapshot, after_snapshot, normal + dirty_cpu + 1, dirty_io)
    }
  end

  defp utilization_for(_before, _after, _first, 0), do: %{active: 0, total: 0, ratio: 0.0}

  defp utilization_for(before_snapshot, after_snapshot, first, count) do
    {active, total} =
      first..(first + count - 1)
      |> Enum.reduce({0, 0}, fn scheduler, {active_acc, total_acc} ->
        {before_active, before_total} = Map.fetch!(before_snapshot, scheduler)
        {after_active, after_total} = Map.fetch!(after_snapshot, scheduler)

        {active_acc + max(after_active - before_active, 0),
         total_acc + max(after_total - before_total, 0)}
      end)

    %{active: active, total: total, ratio: if(total == 0, do: 0.0, else: active / total)}
  end

  defp stringify_scheduler_utilization(utilization) do
    Map.new(utilization, fn {kind, values} ->
      {Atom.to_string(kind),
       %{
         "active_microseconds" => values.active,
         "total_microseconds" => values.total,
         "ratio" => values.ratio
       }}
    end)
  end

  defp environment do
    %{
      "otp" => System.otp_release(),
      "erts" => :erlang.system_info(:version) |> List.to_string(),
      "elixir" => System.version(),
      "os" => os_description(),
      "architecture" => :erlang.system_info(:system_architecture) |> List.to_string(),
      "cpu" => cpu_description(),
      "normal_schedulers" => :erlang.system_info(:schedulers),
      "normal_schedulers_online" => System.schedulers_online(),
      "dirty_cpu_schedulers" => :erlang.system_info(:dirty_cpu_schedulers),
      "dirty_io_schedulers" => :erlang.system_info(:dirty_io_schedulers),
      "ci" => System.get_env("CI") == "true"
    }
  end

  defp os_description do
    with {:ok, contents} <- File.read("/etc/os-release"),
         [_, description] <- Regex.run(~r/^PRETTY_NAME="?([^"\n]+)"?$/m, contents) do
      description
    else
      _other -> inspect(:os.type())
    end
  end

  defp cpu_description do
    with {:ok, contents} <- File.read("/proc/cpuinfo"),
         [_, model] <- Regex.run(~r/^model name\s*:\s*(.+)$/m, contents) do
      String.trim(model)
    else
      _other -> "unavailable"
    end
  end

  defp large_sparse_json(minimum_bytes) do
    prefix = ~s({"payload":{"target":42,"container":[],"unused":" ) |> String.trim_trailing()
    suffix = ~s("},"tail":{"valid":true}})
    padding = String.duplicate("x", max(minimum_bytes - byte_size(prefix) - byte_size(suffix), 1))
    prefix <> padding <> suffix
  end

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp git_identity(revision) do
    case System.cmd("git", ["rev-parse", revision], stderr_to_stdout: true) do
      {value, 0} -> String.trim(value)
      _other -> "unavailable"
    end
  end

  defp stringify_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp write_evidence(filename, report) do
    if directory = System.get_env("SIMD_JSON_QUALIFICATION_DIR") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, filename), [:json.encode(report), "\n"])
    end
  end

  defp reset_runtime! do
    {:ok, _applications} = Application.ensure_all_started(:simd_json)
    true = BuildSmoke.execution_set_cleanup_rejection(false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, false)
    :ok = OperationCoordinator.set_open_failure_for_test(nil)
    wait_for_quiescence()
  end

  defp assert_idle(snapshot, baseline) do
    Enum.each(@idle_gauges, fn gauge ->
      assert Map.fetch!(snapshot, gauge) == Map.fetch!(baseline, gauge),
             "native gauge #{gauge} did not return to baseline"
    end)
  end

  defp wait_for_quiescence(attempts \\ 2_000)

  defp wait_for_quiescence(0) do
    flunk(
      "projection runtime did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_quiescence(attempts) do
    :erlang.garbage_collect(self())

    if coordinator = Process.whereis(OperationCoordinator) do
      :erlang.garbage_collect(coordinator)
    end

    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and
         Enum.all?(@idle_gauges, &(Map.fetch!(snapshot, &1) == 0)) do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end
end
