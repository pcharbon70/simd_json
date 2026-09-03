defmodule SimdJson.Native.PoolOptionsTest do
  use ExUnit.Case, async: false

  alias SimdJson.Error
  alias SimdJson.Native.Diagnostics
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.PoolOptions

  # covers: simd_json.native_pool.fixed_configuration
  test "normalizes deterministic finite defaults and exact boundaries" do
    assert %PoolOptions{
             worker_count: 1,
             queue_capacity: 256,
             workers_explicit?: false,
             queue_explicit?: false,
             executor: :preproduction_threaded
           } = PoolOptions.normalize([], 1)

    assert PoolOptions.default_worker_count(2) == 1
    assert PoolOptions.default_worker_count(3) == 2
    assert PoolOptions.default_worker_count(64) == 32
    assert PoolOptions.default_worker_count(65_536) == 32

    assert %PoolOptions{worker_count: 1, queue_capacity: 1} =
             PoolOptions.normalize([native_workers: 1, native_queue_size: 1], 8)

    assert %PoolOptions{
             worker_count: 64,
             queue_capacity: 4096,
             workers_explicit?: true,
             queue_explicit?: true
           } = PoolOptions.normalize([native_queue_size: 4096, native_workers: 64], 8)
  end

  # covers: simd_json.native_pool.fixed_configuration simd_json.native_pool.startup_validation
  test "rejects every non-integer, out-of-range, duplicate, unknown, and malformed value" do
    invalid_workers = [nil, false, 0, -1, 65, 1.0, "1", self(), fn -> 1 end]
    invalid_queues = [nil, false, 0, -1, 4097, 1.0, "256", self(), fn -> 256 end]

    for value <- invalid_workers do
      assert_raise ArgumentError, fn -> PoolOptions.normalize([native_workers: value], 8) end
    end

    for value <- invalid_queues do
      assert_raise ArgumentError, fn -> PoolOptions.normalize([native_queue_size: value], 8) end
    end

    invalid_options = [
      :invalid,
      [unknown: 1],
      [native_workers: 1, native_workers: 2],
      [{:native_workers, 1}, :invalid],
      [{:native_workers, 1} | :improper]
    ]

    for options <- invalid_options do
      assert_raise ArgumentError, fn -> PoolOptions.normalize(options, 8) end
    end

    for schedulers <- [nil, false, 0, -1, 1.0, "8"] do
      assert_raise ArgumentError, fn -> PoolOptions.normalize([], schedulers) end
    end
  end

  # covers: simd_json.native_pool.fixed_configuration simd_json.native_pool.startup_validation
  test "reads the two application keys once and preserves explicit identity" do
    application = :simd_json_pool_options_test
    Application.delete_env(application, :native_workers)
    Application.delete_env(application, :native_queue_size)

    on_exit(fn ->
      Application.delete_env(application, :native_workers)
      Application.delete_env(application, :native_queue_size)
    end)

    assert %PoolOptions{
             worker_count: 4,
             queue_capacity: 256,
             workers_explicit?: false,
             queue_explicit?: false
           } = PoolOptions.from_application_env(application, 8)

    Application.put_env(application, :native_workers, 7)
    Application.put_env(application, :native_queue_size, 33)

    assert %PoolOptions{
             worker_count: 7,
             queue_capacity: 33,
             workers_explicit?: true,
             queue_explicit?: true
           } = PoolOptions.from_application_env(application, 8)
  end

  # covers: simd_json.native_pool.startup_validation simd_json.native_pool.redacted_snapshot
  test "invalid application startup stops before coordinator or native admission" do
    coordinator = Process.whereis(OperationCoordinator)
    Application.put_env(:simd_json, :native_workers, 0)

    on_exit(fn -> Application.delete_env(:simd_json, :native_workers) end)

    assert_raise ArgumentError, ~r/:native_workers must be an integer in 1\.\.64/, fn ->
      SimdJson.Application.start(:normal, [])
    end

    assert Process.whereis(OperationCoordinator) == coordinator
  end

  # covers: simd_json.native_pool.redacted_snapshot
  test "effective diagnostics are immutable, bounded, and honest about the executor" do
    before = OperationCoordinator.snapshot()
    pool_before = OperationCoordinator.pool_snapshot()

    assert Diagnostics.execution() == pool_before
    assert pool_before.worker_count in 1..64
    assert pool_before.queue_capacity in 1..4096
    assert pool_before.executor == :preproduction_threaded

    _normalized = PoolOptions.normalize([native_workers: 64, native_queue_size: 4096], 1)

    assert OperationCoordinator.snapshot() == before
    assert OperationCoordinator.pool_snapshot() == pool_before
  end

  # covers: simd_json.native_pool.redacted_snapshot
  test "inspection bounds forged configuration and reveals no supplied terms" do
    secret = "pool-secret-#{System.unique_integer([:positive])}"

    forged = %PoolOptions{
      worker_count: secret,
      queue_capacity: List.duplicate(secret, 10_000),
      workers_explicit?: self(),
      queue_explicit?: {secret, self()},
      executor: secret
    }

    assert PoolOptions.snapshot(forged) == %{
             worker_count: nil,
             queue_capacity: nil,
             workers_explicit?: false,
             queue_explicit?: false,
             executor: :preproduction_threaded
           }

    rendered = inspect(PoolOptions.snapshot(forged))
    refute rendered =~ secret
    refute rendered =~ inspect(self())
    assert byte_size(rendered) < 220
  end

  # covers: simd_json.native_pool.nonblocking_bounded_admission simd_json.native_pool.redacted_snapshot
  test "busy is a stable redacted reserved error and pool controls remain private" do
    error = %Error{reason: :busy, message: "native execution capacity is busy"}

    assert inspect(error) ==
             "#SimdJson.Error<reason: :busy, byte_offset: nil, native_code: nil>"

    assert error.byte_offset == nil
    assert error.native_code == nil
    assert error.path == nil
    assert error.array_index == nil

    for function <- [:native_pool, :native_pool_options, :configure_pool, :resize_pool] do
      refute function_exported?(SimdJson, function, 0)
      refute function_exported?(SimdJson, function, 1)
      refute function_exported?(SimdJson, function, 2)
    end
  end
end
