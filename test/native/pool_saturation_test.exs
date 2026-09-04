defmodule SimdJson.Native.PoolSaturationTest do
  use ExUnit.Case, async: false
  import Bitwise

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

  # covers: simd_json.native_pool.saturation simd_json.native_pool.nonblocking_bounded_admission
  test "sustained excess demand preserves exact capacity and FIFO progress" do
    workers = 4
    queue_capacity = 8
    assert BuildSmoke.native_pool_start(workers, queue_capacity) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)

    accepted = fill_until_busy(1, [])

    saturated = BuildSmoke.native_pool_snapshot()
    assert length(accepted) == workers + queue_capacity
    assert length(accepted) == saturated.running_jobs + saturated.queued_jobs
    assert saturated.worker_count == workers

    retained_before = saturated.retained_bytes

    rejection_latencies =
      for _ <- 1..32 do
        started = System.monotonic_time(:microsecond)
        assert %{status: :busy, request_id: 0} = BuildSmoke.native_pool_submit_fixture("rejected")
        System.monotonic_time(:microsecond) - started
      end

    assert BuildSmoke.native_pool_snapshot().retained_bytes == retained_before
    assert Enum.max(rejection_latencies) < 50_000

    assert BuildSmoke.native_pool_pause_workers(false)
    await(fn -> BuildSmoke.native_pool_snapshot().completed_jobs == length(accepted) end)

    expected_hash =
      Enum.reduce(accepted, 0, fn id, hash -> band(hash * 131 + id, 0xFFFFFFFFFFFFFFFF) end)

    assert %{
             dequeue_order_hash: ^expected_hash,
             retained_bytes: 0,
             queued_jobs: 0,
             running_jobs: 0
           } = BuildSmoke.native_pool_snapshot()
  end

  defp fill_until_busy(id, accepted) do
    case BuildSmoke.native_pool_submit_fixture(Integer.to_string(id)) do
      %{status: :accepted, request_id: ^id} ->
        fill_until_busy(id + 1, [id | accepted])

      %{status: :busy, request_id: 0} ->
        if BuildSmoke.native_pool_snapshot().running_jobs < 4 do
          Process.sleep(1)
          fill_until_busy(id, accepted)
        else
          Enum.reverse(accepted)
        end
    end
  end

  defp await(predicate, attempts \\ 2_000)
  defp await(_predicate, 0), do: flunk("native pool did not reach expected state")

  defp await(predicate, attempts) do
    if predicate.(),
      do: :ok,
      else:
        (
          Process.sleep(1)
          await(predicate, attempts - 1)
        )
  end
end
