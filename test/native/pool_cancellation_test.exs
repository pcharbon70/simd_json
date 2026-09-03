defmodule SimdJson.Native.PoolCancellationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  setup do
    configured = OperationCoordinator.pool_snapshot()
    _ = BuildSmoke.native_pool_stop()

    on_exit(fn ->
      _ = BuildSmoke.native_pool_pause_workers(false)
      _ = BuildSmoke.native_pool_stop()

      assert BuildSmoke.native_pool_start(configured.worker_count, configured.queue_capacity) ==
               :ok
    end)

    :ok
  end

  # covers: simd_json.native_pool.cancellation simd_json.native_pool.owned_jobs
  test "explicit cancellation wins once at a running checkpoint" do
    assert BuildSmoke.native_pool_start(1, 1) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)
    submission = BuildSmoke.native_pool_submit_monitored_fixture("cancel-me")

    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 1 end)
    assert BuildSmoke.native_pool_cancel_fixture(submission.request)
    refute BuildSmoke.native_pool_cancel_fixture(submission.request)
    assert BuildSmoke.native_pool_pause_workers(false)

    await(fn -> BuildSmoke.native_pool_snapshot().cancelled_jobs == 1 end)

    assert %{completed_jobs: 0, cancelled_jobs: 1, retained_bytes: 0} =
             BuildSmoke.native_pool_snapshot()
  end

  # covers: simd_json.native_pool.cancellation simd_json.native_pool.owned_jobs
  test "caller death cancels its monitored job" do
    assert BuildSmoke.native_pool_start(1, 1) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)
    parent = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        submission = BuildSmoke.native_pool_submit_monitored_fixture("caller-owned")
        send(parent, {:submitted, submission.request_id})

        receive do
          :keep_request_alive -> send(parent, submission.request)
        end
      end)

    assert_receive {:submitted, 1}, 2_000
    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 1 end)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 2_000
    assert BuildSmoke.native_pool_pause_workers(false)

    await(fn -> BuildSmoke.native_pool_snapshot().cancelled_jobs == 1 end)

    assert %{completed_jobs: 0, cancelled_jobs: 1, retained_bytes: 0} =
             BuildSmoke.native_pool_snapshot()
  end

  # covers: simd_json.native_pool.cancellation simd_json.native_pool.shutdown
  test "shutdown cancels queued and running monitored jobs without delivery" do
    assert BuildSmoke.native_pool_start(2, 2) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)

    running =
      for payload <- ["running-a", "running-b"] do
        BuildSmoke.native_pool_submit_monitored_fixture(payload)
      end

    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 2 end)

    queued =
      for payload <- ["queued-a", "queued-b"] do
        BuildSmoke.native_pool_submit_monitored_fixture(payload)
      end

    assert BuildSmoke.native_pool_stop()

    for submission <- running ++ queued do
      assert BuildSmoke.native_pool_request_state_fixture(submission.request) == :cancelled
    end

    refute_receive {SimdJson.Native, _, _}, 20
  end

  defp await(predicate, attempts \\ 1_000)

  defp await(predicate, 0),
    do: flunk("native pool did not reach expected state: #{inspect(predicate.())}")

  defp await(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(1)
      await(predicate, attempts - 1)
    end
  end
end
