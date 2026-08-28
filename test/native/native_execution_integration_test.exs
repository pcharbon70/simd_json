defmodule SimdJson.Native.ExecutionIntegrationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  @fixture_bytes 4 * 1_024 * 1_024
  @rounds 3
  @heartbeat_period_ms 5
  @heartbeat_budget_microseconds 500_000
  @dirty_scheduler_budget 0.25

  setup do
    {:ok, _applications} = Application.ensure_all_started(:simd_json)
    true = BuildSmoke.execution_set_cleanup_rejection(false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
    wait_for_quiescence()

    on_exit(fn ->
      {:ok, _applications} = Application.ensure_all_started(:simd_json)
      true = BuildSmoke.execution_set_cleanup_rejection(false)
      :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
      :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
      wait_for_quiescence()
    end)

    :ok
  end

  # covers: simd_json.native_execution.threaded_submission_failure simd_json.native_execution.no_fallback simd_json.native_execution.threaded_parse simd_json.native_execution.threaded_cleanup
  test "parse and cleanup submission rejection never enters native worker code" do
    baseline = BuildSmoke.execution_snapshot()
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, true)

    assert {:error, %{reason: :native_failure, stage: :threaded_submission}} =
             ThreadedOperation.open(large_json(@fixture_bytes))

    wait_for_operations()
    rejected_open = BuildSmoke.execution_snapshot()
    assert rejected_open.worker_entries == baseline.worker_entries
    assert rejected_open.live_documents == baseline.live_documents
    assert rejected_open.live_operations == baseline.live_operations
    assert rejected_open.retained_inputs == baseline.retained_inputs

    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
    assert {:ok, document} = ThreadedOperation.open("null")

    before_cleanup = BuildSmoke.execution_snapshot()
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, true)

    assert {:error, %{reason: :native_failure, stage: :threaded_submission}} =
             ThreadedOperation.cleanup(document)

    wait_for_operations()
    rejected_cleanup = BuildSmoke.execution_snapshot()
    assert rejected_cleanup.worker_entries == before_cleanup.worker_entries
    assert rejected_cleanup.live_documents == before_cleanup.live_documents
    assert BuildSmoke.document_lifecycle(document) == :open

    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
    assert :ok = ThreadedOperation.cleanup(document)
    document = nil
    wait_for_quiescence()
    assert document == nil

    final = BuildSmoke.execution_snapshot()
    assert final.live_documents == baseline.live_documents
    assert final.live_document_controls == baseline.live_document_controls
  end

  # covers: simd_json.native_execution.large_parse_responsiveness simd_json.native_execution.scheduler_qualification simd_json.native_execution.threaded_parse simd_json.native_execution.threaded_cleanup simd_json.native_execution.bounded_nif_entry simd_json.native_execution.no_fallback simd_json.native_execution.preproduction_boundary
  test "large valid and invalid parses preserve heartbeat and dirty scheduler budgets" do
    valid = large_json(@fixture_bytes)
    invalid = binary_part(valid, 0, byte_size(valid) - 1)
    concurrency = min(max(System.schedulers_online(), 2), 8)
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
          |> Task.await_many(30_000)

        heartbeat = stop_heartbeat(heartbeat_pid)
        after_wall_time = scheduler_wall_time_snapshot()
        utilization = scheduler_utilization(before_wall_time, after_wall_time)
        {results, heartbeat, utilization}
      after
        :erlang.system_flag(:scheduler_wall_time, previous_wall_time_flag)
      end

    assert Enum.count(results, &(&1 == :valid)) == concurrency
    assert Enum.count(results, &(&1 == :invalid)) == concurrency
    assert heartbeat.samples > 0
    assert heartbeat.max_interval_microseconds < @heartbeat_budget_microseconds
    assert utilization.normal.total_microseconds > 0
    assert utilization.dirty_cpu.total_microseconds > 0
    assert utilization.dirty_io.total_microseconds > 0
    assert utilization.dirty_cpu.ratio < @dirty_scheduler_budget
    assert utilization.dirty_io.ratio < @dirty_scheduler_budget

    expected_worker_entries = concurrency * @rounds * 3
    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert final.worker_entries == baseline.worker_entries + expected_worker_entries
    assert final.live_documents == baseline.live_documents
    assert final.live_document_controls == baseline.live_document_controls

    IO.puts(
      "phase4_scheduler " <>
        "otp=#{System.otp_release()} elixir=#{System.version()} " <>
        "target=#{BuildSmoke.target_triple()} concurrency=#{concurrency} " <>
        "fixture_bytes=#{@fixture_bytes} rounds=#{@rounds} " <>
        "heartbeat_samples=#{heartbeat.samples} " <>
        "heartbeat_max_us=#{heartbeat.max_interval_microseconds} " <>
        "normal_pct=#{format_percent(utilization.normal.ratio)} " <>
        "dirty_cpu_pct=#{format_percent(utilization.dirty_cpu.ratio)} " <>
        "dirty_io_pct=#{format_percent(utilization.dirty_io.ratio)}"
    )
  end

  defp run_parse_rounds(kind, valid, invalid) do
    Enum.each(1..@rounds, fn _round ->
      case kind do
        :valid ->
          assert {:ok, document} = ThreadedOperation.open(valid)
          assert :ok = ThreadedOperation.cleanup(document)

        :invalid ->
          assert {:error, %{reason: :unexpected_eof}} = ThreadedOperation.open(invalid)
      end
    end)

    kind
  end

  defp start_heartbeat do
    spawn_link(fn ->
      heartbeat_loop(System.monotonic_time(:microsecond), 0, 0)
    end)
  end

  defp heartbeat_loop(previous, max_interval, samples) do
    receive do
      {:stop, caller, reference} ->
        send(caller, {
          :heartbeat_stopped,
          reference,
          %{max_interval_microseconds: max_interval, samples: samples}
        })
    after
      @heartbeat_period_ms ->
        now = System.monotonic_time(:microsecond)
        heartbeat_loop(now, max(max_interval, now - previous), samples + 1)
    end
  end

  defp stop_heartbeat(heartbeat_pid) do
    reference = make_ref()
    send(heartbeat_pid, {:stop, self(), reference})

    assert_receive {:heartbeat_stopped, ^reference, heartbeat}, 2_000
    heartbeat
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
        utilization_for(
          before_snapshot,
          after_snapshot,
          normal_count + 1,
          dirty_cpu_count
        ),
      dirty_io:
        utilization_for(
          before_snapshot,
          after_snapshot,
          normal_count + dirty_cpu_count + 1,
          dirty_io_count
        )
    }
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

  defp format_percent(ratio) do
    ratio
    |> Kernel.*(100)
    |> Float.round(3)
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
        native.queued_operations == 0 and native.running_operations == 0 and
        native.live_documents == 0 and native.live_document_controls == 0 and
        native.dispatcher_queued_cleanup == 0 and
        native.dispatcher_active_cleanup == 0 and
        native.retained_failed_cleanup == 0
    end)
  end

  defp wait_for_operations do
    wait_until(fn ->
      native = BuildSmoke.execution_snapshot()

      OperationCoordinator.snapshot().live_requests == 0 and
        native.live_operations == 0 and native.retained_inputs == 0 and
        native.queued_operations == 0 and native.running_operations == 0
    end)
  end

  defp wait_until(predicate, attempts \\ 600)

  defp wait_until(_predicate, 0) do
    flunk(
      "native execution did not reach expected state: " <>
        "#{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_until(predicate, attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))

    if predicate.() do
      :ok
    else
      Process.sleep(5)
      wait_until(predicate, attempts - 1)
    end
  end
end
