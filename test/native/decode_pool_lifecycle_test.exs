defmodule SimdJson.Native.DecodePoolLifecycleTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  setup do
    configured = OperationCoordinator.pool_snapshot()
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()
    _ = BuildSmoke.native_pool_stop()
    assert BuildSmoke.native_pool_start(1, 1) == :ok

    on_exit(fn ->
      _ = BuildSmoke.native_pool_pause_workers(false)
      _ = BuildSmoke.native_pool_stop()

      assert BuildSmoke.native_pool_start(configured.worker_count, configured.queue_capacity) ==
               :ok

      wait_for_quiescence()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.decode.pool_job simd_json.decode.caller_cancellation simd_json.decode.cleanup
  test "caller death cancels a decode job and restores lifecycle gauges", %{baseline: baseline} do
    assert BuildSmoke.native_pool_pause_workers(true)
    parent = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        send(parent, :decode_started)
        ThreadedOperation.decode(Jason.encode!(Enum.to_list(1..20_000)))
      end)

    assert_receive :decode_started
    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 1 end)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}
    assert BuildSmoke.native_pool_pause_workers(false)
    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 0 end)
    wait_for_quiescence()

    pool = BuildSmoke.native_pool_snapshot()
    snapshot = BuildSmoke.execution_snapshot()
    assert pool.cancelled_jobs == 1
    assert pool.queued_jobs == 0
    assert pool.running_jobs == 0
    assert pool.retained_bytes == 0
    assert snapshot.live_operations == baseline.live_operations
    assert snapshot.live_documents == baseline.live_documents
  end

  # covers: simd_json.decode.saturation simd_json.decode.no_fallback
  test "decode rejects immediately when its bounded queue is saturated" do
    assert BuildSmoke.native_pool_pause_workers(true)
    first = Task.async(fn -> ThreadedOperation.decode("[1]") end)
    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 1 end)
    second = Task.async(fn -> ThreadedOperation.decode("[2]") end)
    await(fn -> BuildSmoke.native_pool_snapshot().queued_jobs == 1 end)

    assert {:error, %{reason: :busy}} = ThreadedOperation.decode("[3]")
    assert BuildSmoke.native_pool_pause_workers(false)
    assert {:ok, [1]} = Task.await(first)
    assert {:ok, [2]} = Task.await(second)
  end

  defp wait_for_quiescence do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))

    await(fn ->
      OperationCoordinator.snapshot().live_requests == 0
    end)
  end

  defp await(predicate, attempts \\ 2_000)
  defp await(_predicate, 0), do: flunk("native decode pool did not quiesce")

  defp await(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(1)
      await(predicate, attempts - 1)
    end
  end
end
