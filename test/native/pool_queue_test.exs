defmodule SimdJson.Native.PoolQueueTest do
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

  # covers: simd_json.native_pool.nonblocking_bounded_admission simd_json.native_pool.owned_jobs
  test "capacity is exact and busy rejects before retaining bytes" do
    assert BuildSmoke.native_pool_start(2, 3) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)

    for payload <- ["a", "bb"] do
      assert %{status: :accepted} = BuildSmoke.native_pool_submit_fixture(payload)
    end

    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 2 end)

    for payload <- ["ccc", "dddd", "eeeee"] do
      assert %{status: :accepted} = BuildSmoke.native_pool_submit_fixture(payload)
    end

    before = BuildSmoke.native_pool_snapshot()
    started = System.monotonic_time(:microsecond)
    assert %{status: :busy, request_id: 0} = BuildSmoke.native_pool_submit_fixture("not-retained")
    elapsed = System.monotonic_time(:microsecond) - started
    after_rejection = BuildSmoke.native_pool_snapshot()

    assert elapsed < 50_000
    assert before.queued_jobs == 3
    assert before.running_jobs == 2
    assert after_rejection.retained_bytes == before.retained_bytes
    assert after_rejection.rejected_jobs == before.rejected_jobs + 1

    assert BuildSmoke.native_pool_pause_workers(false)
    await(fn -> BuildSmoke.native_pool_snapshot().completed_jobs == 5 end)

    assert %{queued_jobs: 0, running_jobs: 0, retained_bytes: 0} =
             BuildSmoke.native_pool_snapshot()
  end

  # covers: simd_json.native_pool.nonblocking_bounded_admission simd_json.native_pool.owned_jobs
  test "one worker dequeues owned jobs in FIFO order" do
    assert BuildSmoke.native_pool_start(1, 4) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)

    for payload <- ["first", "second", "third", "fourth"] do
      assert %{status: :accepted} = BuildSmoke.native_pool_submit_fixture(payload)
    end

    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 1 end)
    assert BuildSmoke.native_pool_pause_workers(false)
    await(fn -> BuildSmoke.native_pool_snapshot().completed_jobs == 4 end)

    expected_hash = Enum.reduce(1..4, 0, fn id, hash -> hash * 131 + id end)

    assert %{dequeue_order_hash: ^expected_hash, retained_bytes: 0} =
             BuildSmoke.native_pool_snapshot()
  end

  # covers: simd_json.native_pool.owned_jobs simd_json.native_pool.shutdown
  test "shutdown drains paused running and queued ownership" do
    assert BuildSmoke.native_pool_start(2, 4) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)

    for _ <- 1..2,
        do: assert(%{status: :accepted} = BuildSmoke.native_pool_submit_fixture("owned"))

    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 2 end)

    for _ <- 1..4,
        do: assert(%{status: :accepted} = BuildSmoke.native_pool_submit_fixture("owned"))

    assert BuildSmoke.native_pool_stop()
    assert BuildSmoke.native_pool_snapshot() == nil
    assert BuildSmoke.native_pool_start(1, 1) == :ok

    assert %{queued_jobs: 0, running_jobs: 0, retained_bytes: 0} =
             BuildSmoke.native_pool_snapshot()
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
