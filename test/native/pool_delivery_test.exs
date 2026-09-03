defmodule SimdJson.Native.PoolDeliveryTest do
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

  # covers: simd_json.native_pool.owned_jobs simd_json.native_pool.cancellation
  test "workers deliver one result for each unique request reference" do
    assert BuildSmoke.native_pool_start(1, 2) == :ok
    first = BuildSmoke.native_pool_submit_monitored_fixture("abc")
    second = BuildSmoke.native_pool_submit_monitored_fixture("de")

    refute first.request_ref == second.request_ref
    assert_receive {SimdJson.Native, first_ref, {:ok, 294}}, 2_000
    assert_receive {SimdJson.Native, second_ref, {:ok, 201}}, 2_000
    assert first_ref == first.request_ref
    assert second_ref == second.request_ref
    refute_receive {SimdJson.Native, _, _}, 20

    assert %{completed_jobs: 2, delivered_jobs: 2, discarded_jobs: 0} =
             BuildSmoke.native_pool_snapshot()
  end

  # covers: simd_json.native_pool.cancellation simd_json.native_pool.shutdown
  test "a failed send to an orphaned caller is discarded and cleaned" do
    assert BuildSmoke.native_pool_start(1, 1) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)
    parent = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        submission = BuildSmoke.native_pool_submit_monitored_fixture("orphan")
        assert BuildSmoke.native_pool_abandon_monitor_fixture(submission.request)
        send(parent, {:orphan_submitted, submission.request_id})
      end)

    assert_receive {:orphan_submitted, 1}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 2_000
    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 1 end)
    assert BuildSmoke.native_pool_pause_workers(false)
    await(fn -> BuildSmoke.native_pool_snapshot().discarded_jobs == 1 end)

    assert %{
             completed_jobs: 1,
             delivered_jobs: 0,
             discarded_jobs: 1,
             retained_bytes: 0
           } = BuildSmoke.native_pool_snapshot()
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
