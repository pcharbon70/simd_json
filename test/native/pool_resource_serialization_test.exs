defmodule SimdJson.Native.PoolResourceSerializationTest do
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

  # covers: simd_json.native_pool.resource_serialization simd_json.native_pool.cancellation
  test "one resource rejects overlap while independent resources run concurrently" do
    assert BuildSmoke.native_pool_start(2, 2) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)
    first_resource = BuildSmoke.native_pool_serialization_fixture()
    second_resource = BuildSmoke.native_pool_serialization_fixture()

    first = BuildSmoke.native_pool_submit_serialized_fixture("first", first_resource)

    assert_raise ErlangError, "Erlang error: :resource_busy", fn ->
      BuildSmoke.native_pool_submit_serialized_fixture("conflict", first_resource)
    end

    second = BuildSmoke.native_pool_submit_serialized_fixture("second", second_resource)
    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 2 end)
    assert BuildSmoke.native_pool_serialization_state_fixture(first_resource) == :reserved
    assert BuildSmoke.native_pool_serialization_state_fixture(second_resource) == :reserved

    assert BuildSmoke.native_pool_pause_workers(false)
    first_ref = first.request_ref
    second_ref = second.request_ref
    assert_receive {SimdJson.Native, ^first_ref, {:ok, _}}, 2_000
    assert_receive {SimdJson.Native, ^second_ref, {:ok, _}}, 2_000
    await(fn -> BuildSmoke.native_pool_snapshot().completed_jobs == 2 end)
    assert BuildSmoke.native_pool_serialization_state_fixture(first_resource) == :ready
    assert BuildSmoke.native_pool_serialization_state_fixture(second_resource) == :ready
  end

  # covers: simd_json.native_pool.resource_serialization simd_json.native_pool.shutdown
  test "close prevents admission and the final job owns closing-to-closed" do
    assert BuildSmoke.native_pool_start(1, 1) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)
    resource = BuildSmoke.native_pool_serialization_fixture()
    submission = BuildSmoke.native_pool_submit_serialized_fixture("last", resource)
    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 1 end)

    assert BuildSmoke.native_pool_close_serialization_fixture(resource) == :closing
    assert BuildSmoke.native_pool_serialization_state_fixture(resource) == :closing

    assert_raise ErlangError, "Erlang error: :resource_closed", fn ->
      BuildSmoke.native_pool_submit_serialized_fixture("late", resource)
    end

    assert BuildSmoke.native_pool_pause_workers(false)
    assert_receive {SimdJson.Native, request_ref, {:ok, _}}, 2_000
    assert request_ref == submission.request_ref
    await(fn -> BuildSmoke.native_pool_serialization_state_fixture(resource) == :closed end)
    assert BuildSmoke.native_pool_close_serialization_fixture(resource) == :already_closed
  end

  # covers: simd_json.native_pool.resource_serialization simd_json.native_pool.cancellation
  test "cancellation releases a reservation exactly once" do
    assert BuildSmoke.native_pool_start(1, 1) == :ok
    assert BuildSmoke.native_pool_pause_workers(true)
    resource = BuildSmoke.native_pool_serialization_fixture()
    submission = BuildSmoke.native_pool_submit_serialized_fixture("cancel", resource)
    await(fn -> BuildSmoke.native_pool_snapshot().running_jobs == 1 end)

    assert BuildSmoke.native_pool_cancel_fixture(submission.request)
    assert BuildSmoke.native_pool_pause_workers(false)
    await(fn -> BuildSmoke.native_pool_snapshot().cancelled_jobs == 1 end)
    assert BuildSmoke.native_pool_serialization_state_fixture(resource) == :ready

    retry = BuildSmoke.native_pool_submit_serialized_fixture("retry", resource)
    assert_receive {SimdJson.Native, request_ref, {:ok, _}}, 2_000
    assert request_ref == retry.request_ref
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
