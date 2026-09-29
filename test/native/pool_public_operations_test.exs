defmodule SimdJson.Native.PoolPublicOperationsTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke

  # covers: simd_json.native_pool.fixed_workers simd_json.native_pool.owned_jobs simd_json.native_pool.nonblocking_bounded_admission
  test "public open, select, and cleanup complete on fixed pool workers" do
    before = BuildSmoke.native_pool_snapshot()

    assert {:ok, document} = SimdJson.open(~s({"name":"Ada","active":true}))
    assert {:ok, %{"name" => "Ada"}} = SimdJson.select(document, [{"name", ["name"]}])
    assert :ok = SimdJson.close(document)

    await_completion(before, 3)
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

    await_completion(before, 1)
    after_projection = BuildSmoke.native_pool_snapshot()
    assert after_projection.completed_jobs == before.completed_jobs + 1
    assert after_projection.delivered_jobs == before.delivered_jobs + 1
  end

  defp await_completion(before, count, attempts \\ 1_000)

  defp await_completion(_before, _count, 0),
    do: flunk("native pool did not publish the expected completed jobs")

  defp await_completion(before, count, attempts) do
    snapshot = BuildSmoke.native_pool_snapshot()

    if snapshot.completed_jobs == before.completed_jobs + count and
         snapshot.delivered_jobs == before.delivered_jobs + count and
         snapshot.queued_jobs == 0 and snapshot.running_jobs == 0 do
      :ok
    else
      Process.sleep(1)
      await_completion(before, count, attempts - 1)
    end
  end
end
