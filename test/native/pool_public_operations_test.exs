defmodule SimdJson.Native.PoolPublicOperationsTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke

  # covers: simd_json.native_pool.fixed_workers simd_json.native_pool.owned_jobs simd_json.native_pool.nonblocking_bounded_admission
  test "public open, select, and cleanup complete on fixed pool workers" do
    before = BuildSmoke.native_pool_snapshot()

    assert {:ok, document} = SimdJson.open(~s({"name":"Ada","active":true}))
    assert {:ok, %{"name" => "Ada"}} = SimdJson.select(document, [{"name", ["name"]}])
    assert :ok = SimdJson.close(document)

    after_operations = BuildSmoke.native_pool_snapshot()

    assert after_operations.worker_count == before.worker_count
    assert after_operations.live_workers == before.live_workers
    assert after_operations.completed_jobs == before.completed_jobs + 3
    assert after_operations.delivered_jobs == before.delivered_jobs + 3
    assert after_operations.queued_jobs == 0
    assert after_operations.running_jobs == 0
    assert after_operations.retained_bytes == 0
  end

  # covers: simd_json.native_pool.fixed_workers simd_json.native_pool.owned_jobs
  test "binary projection uses the pool without publishing a document" do
    before = BuildSmoke.native_pool_snapshot()

    assert {:ok, %{"count" => 7}} =
             SimdJson.select(~s({"count":7}), [{"count", ["count"]}])

    after_projection = BuildSmoke.native_pool_snapshot()
    assert after_projection.completed_jobs == before.completed_jobs + 1
    assert after_projection.delivered_jobs == before.delivered_jobs + 1
  end
end
