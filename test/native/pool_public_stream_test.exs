defmodule SimdJson.Native.PoolPublicStreamTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke

  # covers: simd_json.native_pool.fixed_workers simd_json.native_pool.owned_jobs simd_json.native_pool.resource_serialization
  test "lazy setup and demand-driven batches use fixed pool workers" do
    stream =
      SimdJson.stream(~s([{"id":1},{"id":2},{"id":3}]),
        path: [],
        fields: [{:id, ["id"]}],
        batch_size: 2,
        max_batch_bytes: 1_024
      )

    before = BuildSmoke.native_pool_snapshot()
    assert Enum.to_list(stream) == [%{id: 1}, %{id: 2}, %{id: 3}]
    after_stream = BuildSmoke.native_pool_snapshot()

    assert after_stream.worker_count == before.worker_count
    assert after_stream.live_workers == before.live_workers
    assert after_stream.completed_jobs == before.completed_jobs + 3
    assert after_stream.delivered_jobs == before.delivered_jobs + 3
    assert after_stream.queued_jobs == 0
    assert after_stream.running_jobs == 0
    assert after_stream.retained_bytes == 0
  end

  # covers: simd_json.native_pool.cancellation simd_json.native_pool.owned_jobs simd_json.stream_execution.early_halt
  test "early halt leaves no queued or running stream work" do
    stream =
      SimdJson.stream(~s([{"id":1},{"id":2},{"id":3}]),
        path: [],
        fields: [{:id, ["id"]}],
        batch_size: 1,
        max_batch_bytes: 1_024
      )

    assert Enum.take(stream, 1) == [%{id: 1}]
    snapshot = BuildSmoke.native_pool_snapshot()
    assert snapshot.queued_jobs == 0
    assert snapshot.running_jobs == 0
    assert snapshot.retained_bytes == 0
  end
end
