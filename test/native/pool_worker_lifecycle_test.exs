defmodule SimdJson.Native.PoolWorkerLifecycleTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  setup do
    configured = OperationCoordinator.pool_snapshot()

    on_exit(fn ->
      _ = BuildSmoke.native_pool_stop()

      assert BuildSmoke.native_pool_start(configured.worker_count, configured.queue_capacity) ==
               :ok
    end)

    %{configured: configured}
  end

  # covers: simd_json.native_pool.fixed_workers
  test "starts exactly the configured fixed idle workers", %{configured: configured} do
    assert %{
             worker_count: workers,
             queue_capacity: capacity,
             live_workers: workers,
             accepting: true
           } =
             BuildSmoke.native_pool_snapshot()

    assert workers == configured.worker_count
    assert capacity == configured.queue_capacity
    assert BuildSmoke.native_pool_start(workers, capacity) == :already_started
    assert BuildSmoke.native_pool_start(workers, capacity + 1) == :conflicting_configuration
  end

  # covers: simd_json.native_pool.fixed_workers simd_json.native_pool.shutdown
  test "partial startup rolls back every created worker", %{configured: configured} do
    assert BuildSmoke.native_pool_stop()
    assert BuildSmoke.native_pool_snapshot() == nil
    assert BuildSmoke.native_pool_start_with_failure(4, 8, 2) == :startup_failed
    assert BuildSmoke.native_pool_snapshot() == nil
    assert BuildSmoke.native_pool_start(configured.worker_count, configured.queue_capacity) == :ok
  end

  # covers: simd_json.native_pool.fixed_workers simd_json.native_pool.shutdown
  test "repeated stop and start joins before state disappears" do
    for workers <- 1..4 do
      _ = BuildSmoke.native_pool_stop()
      assert BuildSmoke.native_pool_snapshot() == nil
      assert BuildSmoke.native_pool_start(workers, 16) == :ok
      assert %{worker_count: ^workers, live_workers: ^workers} = BuildSmoke.native_pool_snapshot()
    end
  end

  # covers: simd_json.native_pool.shutdown simd_json.release.ci_native_reliability
  test "concurrent snapshots cannot observe a pool after its mutexes are retired", %{
    configured: configured
  } do
    readers =
      for _ <- 1..4 do
        Task.async(fn ->
          for _ <- 1..300 do
            case BuildSmoke.native_pool_snapshot() do
              nil -> :ok
              %{accepting: accepting} when is_boolean(accepting) -> :ok
            end
          end
        end)
      end

    for _ <- 1..30 do
      _ = BuildSmoke.native_pool_stop()

      assert BuildSmoke.native_pool_start(
               configured.worker_count,
               configured.queue_capacity
             ) == :ok
    end

    Enum.each(readers, &Task.await(&1, 10_000))
  end
end
