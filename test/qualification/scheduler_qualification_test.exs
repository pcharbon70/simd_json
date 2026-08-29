defmodule SimdJson.Qualification.SchedulerQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  @fixture_bytes 4 * 1_024 * 1_024
  @rounds 20
  @heartbeat_period_ms 2
  @minimum_heartbeat_samples 40
  @p95_budget_microseconds 50_000
  @p99_ci_threshold_microseconds 250_000
  @maximum_ci_threshold_microseconds 500_000
  @dirty_scheduler_budget 0.25

  setup do
    {:ok, _applications} = Application.ensure_all_started(:simd_json)
    wait_for_quiescence()

    on_exit(fn ->
      {:ok, _applications} = Application.ensure_all_started(:simd_json)
      wait_for_quiescence()
    end)

    :ok
  end

  # covers: simd_json.native_execution.large_parse_responsiveness simd_json.native_execution.scheduler_qualification simd_json.native_execution.threaded_parse simd_json.native_execution.threaded_cleanup simd_json.native_execution.bounded_nif_entry simd_json.native_execution.no_fallback simd_json.native_execution.preproduction_boundary
  test "formal public scheduler profile preserves percentile and dirty scheduler budgets" do
    valid = large_json(@fixture_bytes)
    invalid = binary_part(valid, 0, byte_size(valid) - 1)
    concurrency = min(max(System.schedulers_online(), 2), 8)

    warm_up(valid, invalid)
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()
    previous_wall_time_flag = :erlang.system_flag(:scheduler_wall_time, true)

    {results, heartbeat, utilization} =
      try do
        before_wall_time = scheduler_wall_time_snapshot()
        heartbeat_pid = start_heartbeat()

        results =
          [:valid, :invalid]
          |> Enum.flat_map(fn kind -> List.duplicate(kind, concurrency) end)
          |> Enum.map(fn kind ->
            Task.async(fn -> run_parse_rounds(kind, valid, invalid) end)
          end)
          |> Task.await_many(120_000)

        heartbeat = stop_heartbeat(heartbeat_pid)
        after_wall_time = scheduler_wall_time_snapshot()
        {results, heartbeat, scheduler_utilization(before_wall_time, after_wall_time)}
      after
        :erlang.system_flag(:scheduler_wall_time, previous_wall_time_flag)
      end

    percentiles = heartbeat_percentiles(heartbeat.intervals_microseconds)

    assert Enum.count(results, &(&1 == :valid)) == concurrency
    assert Enum.count(results, &(&1 == :invalid)) == concurrency
    assert heartbeat.samples >= @minimum_heartbeat_samples
    assert percentiles.p95 <= @p95_budget_microseconds
    assert percentiles.p99 <= @p99_ci_threshold_microseconds
    assert percentiles.maximum <= @maximum_ci_threshold_microseconds
    assert utilization.normal.total_microseconds > 0
    assert utilization.dirty_cpu.total_microseconds > 0
    assert utilization.dirty_io.total_microseconds > 0
    assert utilization.dirty_cpu.ratio < @dirty_scheduler_budget
    assert utilization.dirty_io.ratio < @dirty_scheduler_budget

    expected_worker_entries = concurrency * @rounds * 3
    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert final.worker_entries == baseline.worker_entries + expected_worker_entries
    assert_idle(final, baseline)

    report =
      qualification_report(
        concurrency,
        heartbeat,
        percentiles,
        utilization,
        baseline,
        final
      )

    write_evidence(report)

    IO.puts(
      "phase6_scheduler " <>
        "samples=#{heartbeat.samples} p50_us=#{percentiles.p50} " <>
        "p95_us=#{percentiles.p95} p99_us=#{percentiles.p99} " <>
        "max_us=#{percentiles.maximum} normal_pct=#{percent(utilization.normal.ratio)} " <>
        "dirty_cpu_pct=#{percent(utilization.dirty_cpu.ratio)} " <>
        "dirty_io_pct=#{percent(utilization.dirty_io.ratio)}"
    )
  end

  defp warm_up(valid, invalid) do
    assert {:ok, document} = SimdJson.open(valid)
    assert :ok = SimdJson.close(document)
    assert {:error, %Error{reason: :unexpected_eof}} = SimdJson.open(invalid)
  end

  defp run_parse_rounds(kind, valid, invalid) do
    Enum.each(1..@rounds, fn _round ->
      case kind do
        :valid ->
          assert {:ok, document} = SimdJson.open(valid)
          assert :ok = SimdJson.close(document)

        :invalid ->
          assert {:error, %Error{reason: :unexpected_eof}} = SimdJson.open(invalid)
      end
    end)

    kind
  end

  defp start_heartbeat do
    spawn_link(fn -> heartbeat_loop(System.monotonic_time(:microsecond), []) end)
  end

  defp heartbeat_loop(previous, intervals) do
    receive do
      {:stop, caller, reference} ->
        send(caller, {
          :heartbeat_stopped,
          reference,
          %{
            intervals_microseconds: Enum.reverse(intervals),
            samples: length(intervals)
          }
        })
    after
      @heartbeat_period_ms ->
        now = System.monotonic_time(:microsecond)
        heartbeat_loop(now, [now - previous | intervals])
    end
  end

  defp stop_heartbeat(heartbeat_pid) do
    reference = make_ref()
    send(heartbeat_pid, {:stop, self(), reference})
    assert_receive {:heartbeat_stopped, ^reference, heartbeat}, 2_000
    heartbeat
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
    index = max(ceil(length(sorted) * percentage / 100) - 1, 0)
    Enum.at(sorted, index)
  end

  defp scheduler_wall_time_snapshot do
    :scheduler_wall_time_all
    |> :erlang.statistics()
    |> Map.new(fn {scheduler, active, total} -> {scheduler, {active, total}} end)
  end

  defp scheduler_utilization(before_snapshot, after_snapshot) do
    normal_count = :erlang.system_info(:schedulers)
    dirty_cpu_count = :erlang.system_info(:dirty_cpu_schedulers)
    dirty_io_count = :erlang.system_info(:dirty_io_schedulers)

    %{
      normal: utilization_for(before_snapshot, after_snapshot, 1, normal_count),
      dirty_cpu:
        utilization_for(before_snapshot, after_snapshot, normal_count + 1, dirty_cpu_count),
      dirty_io:
        utilization_for(
          before_snapshot,
          after_snapshot,
          normal_count + dirty_cpu_count + 1,
          dirty_io_count
        )
    }
  end

  defp utilization_for(_before_snapshot, _after_snapshot, _first_scheduler, 0) do
    %{active_microseconds: 0, total_microseconds: 0, ratio: 0.0}
  end

  defp utilization_for(before_snapshot, after_snapshot, first_scheduler, count) do
    {active, total} =
      first_scheduler..(first_scheduler + count - 1)
      |> Enum.reduce({0, 0}, fn scheduler, {active_acc, total_acc} ->
        {before_active, before_total} = Map.fetch!(before_snapshot, scheduler)
        {after_active, after_total} = Map.fetch!(after_snapshot, scheduler)

        {
          active_acc + max(after_active - before_active, 0),
          total_acc + max(after_total - before_total, 0)
        }
      end)

    %{
      active_microseconds: active,
      total_microseconds: total,
      ratio: if(total == 0, do: 0.0, else: active / total)
    }
  end

  defp qualification_report(concurrency, heartbeat, percentiles, utilization, baseline, final) do
    %{
      "schema_version" => 1,
      "source_revision" => source_revision(),
      "environment" => %{
        "otp" => otp_version(),
        "erts" => :erlang.system_info(:version) |> List.to_string(),
        "elixir" => System.version(),
        "os" => os_description(),
        "architecture" => :erlang.system_info(:system_architecture) |> List.to_string(),
        "cpu" => cpu_description(),
        "normal_schedulers" => :erlang.system_info(:schedulers),
        "normal_schedulers_online" => System.schedulers_online(),
        "dirty_cpu_schedulers" => :erlang.system_info(:dirty_cpu_schedulers),
        "dirty_io_schedulers" => :erlang.system_info(:dirty_io_schedulers),
        "virtualization" => virtualization(),
        "power_assumption" => power_assumption(),
        "ci" => System.get_env("CI") == "true"
      },
      "profile" => %{
        "fixture_bytes" => @fixture_bytes,
        "valid_callers" => concurrency,
        "invalid_callers" => concurrency,
        "rounds_per_caller" => @rounds,
        "warm_up_valid" => 1,
        "warm_up_invalid" => 1,
        "heartbeat_period_ms" => @heartbeat_period_ms,
        "percentile_method" => "nearest-rank",
        "minimum_samples" => @minimum_heartbeat_samples
      },
      "budgets_microseconds" => %{
        "p95_qualification" => @p95_budget_microseconds,
        "p99_ci_regression" => @p99_ci_threshold_microseconds,
        "maximum_ci_regression" => @maximum_ci_threshold_microseconds
      },
      "heartbeat" => %{
        "samples" => heartbeat.samples,
        "p50" => percentiles.p50,
        "p95" => percentiles.p95,
        "p99" => percentiles.p99,
        "maximum" => percentiles.maximum,
        "raw_intervals_microseconds" => heartbeat.intervals_microseconds
      },
      "scheduler_utilization" => %{
        "normal" => utilization_json(utilization.normal),
        "dirty_cpu" => utilization_json(utilization.dirty_cpu),
        "dirty_io" => utilization_json(utilization.dirty_io),
        "dirty_ratio_limit" => @dirty_scheduler_budget
      },
      "native_baseline" => stringify_map(baseline),
      "native_final" => stringify_map(final)
    }
  end

  defp utilization_json(value) do
    %{
      "active_microseconds" => value.active_microseconds,
      "total_microseconds" => value.total_microseconds,
      "ratio" => value.ratio
    }
  end

  defp write_evidence(report) do
    case System.get_env("SIMD_JSON_QUALIFICATION_DIR") do
      nil ->
        :ok

      directory ->
        File.mkdir_p!(directory)
        File.write!(Path.join(directory, "scheduler.json"), [:json.encode(report), "\n"])
    end
  end

  defp source_revision do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {revision, 0} -> String.trim(revision)
      _other -> "unavailable"
    end
  end

  defp otp_version do
    otp_release = System.otp_release()
    path = Path.join([to_string(:code.root_dir()), "releases", otp_release, "OTP_VERSION"])

    case File.read(path) do
      {:ok, version} -> String.trim(version)
      _other -> otp_release
    end
  end

  defp os_description do
    case File.read("/etc/os-release") do
      {:ok, contents} ->
        case Regex.run(~r/^PRETTY_NAME="?([^"\n]+)"?$/m, contents) do
          [_, description] -> description
          _other -> inspect(:os.type())
        end

      _other ->
        inspect(:os.type())
    end
  end

  defp cpu_description do
    case File.read("/proc/cpuinfo") do
      {:ok, contents} ->
        case Regex.run(~r/^model name\s*:\s*(.+)$/m, contents) do
          [_, model] -> String.trim(model)
          _other -> "unavailable"
        end

      _other ->
        "unavailable"
    end
  end

  defp virtualization do
    case System.cmd("systemd-detect-virt", [], stderr_to_stdout: true) do
      {value, _status} -> String.trim(value)
    end
  rescue
    _error -> "unavailable"
  end

  defp power_assumption do
    if System.get_env("GITHUB_ACTIONS") == "true" do
      "shared GitHub-hosted runner; power management and neighboring load are uncontrolled"
    else
      "developer host; power management and neighboring load are uncontrolled"
    end
  end

  defp stringify_map(map) do
    Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp percent(ratio), do: ratio |> Kernel.*(100) |> Float.round(3)

  defp assert_idle(snapshot, baseline) do
    for gauge <- [
          :live_operations,
          :retained_inputs,
          :queued_operations,
          :queued_cleanup,
          :running_operations,
          :live_documents,
          :live_document_controls,
          :dispatcher_queued_cleanup,
          :dispatcher_active_cleanup,
          :retained_failed_cleanup
        ] do
      assert Map.fetch!(snapshot, gauge) == Map.fetch!(baseline, gauge),
             "native gauge #{gauge} did not return to baseline"
    end
  end

  defp large_json(minimum_bytes) do
    element = ~s("0123456789abcdef",)
    repetitions = div(minimum_bytes, byte_size(element)) + 1
    "[" <> String.duplicate(element, repetitions) <> ~s("end"])
  end

  defp wait_for_quiescence do
    wait_until(fn ->
      native = BuildSmoke.execution_snapshot()

      OperationCoordinator.snapshot().live_requests == 0 and
        native.live_operations == 0 and native.retained_inputs == 0 and
        native.queued_operations == 0 and native.queued_cleanup == 0 and
        native.running_operations == 0 and native.live_documents == 0 and
        native.live_document_controls == 0 and
        native.dispatcher_queued_cleanup == 0 and
        native.dispatcher_active_cleanup == 0 and
        native.retained_failed_cleanup == 0
    end)
  end

  defp wait_until(predicate, attempts \\ 2_000)

  defp wait_until(_predicate, 0) do
    flunk(
      "native execution did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_until(predicate, attempts) do
    :erlang.garbage_collect(self())

    if coordinator = Process.whereis(OperationCoordinator) do
      :erlang.garbage_collect(coordinator)
    end

    if predicate.() do
      :ok
    else
      Process.sleep(5)
      wait_until(predicate, attempts - 1)
    end
  end
end
