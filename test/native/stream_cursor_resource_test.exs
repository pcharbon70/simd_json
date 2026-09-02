defmodule SimdJson.Native.StreamCursorResourceTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke

  # covers: simd_json.stream_cursor.opaque_cursor simd_json.stream_cursor.parent_retention simd_json.document_resource.parent_retention
  test "private cursor resource retains and deterministically releases its genuine parent" do
    {:ok, document} = SimdJson.open(~s({"rows":[]}))
    baseline = BuildSmoke.execution_snapshot()

    cursor = BuildSmoke.stream_cursor_resource_fixture(document.__resource__)
    assert is_reference(cursor)

    retained = BuildSmoke.execution_snapshot()
    assert retained.live_stream_cursor_resources == baseline.live_stream_cursor_resources + 1
    assert retained.retained_stream_cursor_parents == baseline.retained_stream_cursor_parents + 1
    assert BuildSmoke.document_lifecycle(document.__resource__) == :open

    assert BuildSmoke.stream_cursor_resource_close(cursor)
    assert BuildSmoke.stream_cursor_resource_close(cursor)

    released = BuildSmoke.execution_snapshot()
    assert released.live_stream_cursor_resources == baseline.live_stream_cursor_resources
    assert released.retained_stream_cursor_parents == baseline.retained_stream_cursor_parents
    assert SimdJson.close(document) == :ok
  end

  test "non-owner cursor construction is rejected before parent state changes" do
    {:ok, document} = SimdJson.open(~s({"rows":[]}))
    baseline = BuildSmoke.execution_snapshot()

    task =
      Task.async(fn ->
        try do
          BuildSmoke.stream_cursor_resource_fixture(document.__resource__)
        rescue
          error -> {:raised, error}
        catch
          kind, value -> {:caught, kind, value}
        end
      end)

    result = Task.await(task)
    assert match?({:raised, _}, result) or match?({:caught, _, _}, result)

    after_rejection = BuildSmoke.execution_snapshot()

    for gauge <- [:live_stream_cursor_resources, :retained_stream_cursor_parents] do
      assert Map.fetch!(after_rejection, gauge) == Map.fetch!(baseline, gauge)
    end

    assert BuildSmoke.document_lifecycle(document.__resource__) == :open
    assert BuildSmoke.document_projection_owner_state(document.__resource__) == :fresh
    assert SimdJson.close(document) == :ok
  end

  # covers: simd_json.stream_execution.cursor_state_machine simd_json.stream_execution.single_in_flight_batch simd_json.stream_execution.no_prefetch
  test "cursor demand admits one exact sequence and advances only after delivery" do
    {:ok, document} = SimdJson.open(~s({"rows":[]}))
    cursor = BuildSmoke.stream_cursor_resource_fixture(document.__resource__)

    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:ready, 0}
    assert BuildSmoke.stream_cursor_demand_reserve(cursor, 0)
    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:running, 0}
    refute BuildSmoke.stream_cursor_demand_reserve(cursor, 0)
    refute BuildSmoke.stream_cursor_demand_reserve(cursor, 1)

    assert BuildSmoke.stream_cursor_demand_complete(cursor, 0, false)
    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:ready, 1}
    refute BuildSmoke.stream_cursor_demand_reserve(cursor, 0)
    assert BuildSmoke.stream_cursor_demand_reserve(cursor, 1)
    assert BuildSmoke.stream_cursor_demand_complete(cursor, 1, true)
    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:done, 2}
    refute BuildSmoke.stream_cursor_demand_reserve(cursor, 2)

    assert BuildSmoke.stream_cursor_resource_close(cursor)
    assert SimdJson.close(document) == :ok
  end

  # covers: simd_json.stream_execution.early_halt_cleanup simd_json.stream_execution.cursor_state_machine
  test "cancellation is monotonic and repeated halt is idempotent" do
    {:ok, document} = SimdJson.open(~s({"rows":[]}))
    cursor = BuildSmoke.stream_cursor_resource_fixture(document.__resource__)

    assert BuildSmoke.stream_cursor_demand_reserve(cursor, 0)
    assert BuildSmoke.stream_cursor_demand_cancel(cursor)
    assert BuildSmoke.stream_cursor_demand_cancel(cursor)
    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:cancelled, 0}
    refute BuildSmoke.stream_cursor_demand_complete(cursor, 0, false)
    refute BuildSmoke.stream_cursor_demand_reserve(cursor, 0)

    assert BuildSmoke.stream_cursor_resource_close(cursor)
    assert SimdJson.close(document) == :ok
  end
end
