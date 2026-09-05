defmodule SimdJson.DecodeSchedulerQualificationTest do
  use ExUnit.Case, async: false

  @heartbeat_ms 2

  # covers: simd_json.decode_api.pool_execution simd_json.decode_api.bounded_failure
  test "large concurrent decode keeps normal scheduler heartbeat bounded" do
    input = Jason.encode!(Enum.map(1..50_000, &%{"id" => &1, "name" => "item-#{&1}"}))

    heartbeat =
      spawn_link(fn -> heartbeat_loop(self(), System.monotonic_time(:microsecond), []) end)

    tasks = for _ <- 1..4, do: Task.async(fn -> SimdJson.decode(input) end)
    assert Enum.all?(Task.await_many(tasks, 120_000), &match?({:ok, [_ | _]}, &1))

    reference = make_ref()
    send(heartbeat, {:stop, self(), reference})
    assert_receive {:heartbeat, ^reference, intervals}
    sorted = Enum.sort(intervals)
    p95 = percentile(sorted, 95)
    p99 = percentile(sorted, 99)
    maximum = List.last(sorted)

    assert length(sorted) >= 2
    assert p95 <= 50_000
    assert p99 <= 250_000
    assert maximum <= 500_000

    directory = System.get_env("SIMD_JSON_QUALIFICATION_DIR", "_build/qualification/decode")
    File.mkdir_p!(directory)

    File.write!(
      Path.join(directory, "decode-scheduler.json"),
      :json.encode(%{
        schema_version: 1,
        input_bytes: byte_size(input),
        concurrency: 4,
        samples: length(sorted),
        heartbeat_microseconds: %{p95: p95, p99: p99, maximum: maximum}
      })
    )
  end

  defp heartbeat_loop(owner, previous, intervals) do
    receive do
      {:stop, caller, reference} -> send(caller, {:heartbeat, reference, Enum.reverse(intervals)})
    after
      @heartbeat_ms ->
        now = System.monotonic_time(:microsecond)
        heartbeat_loop(owner, now, [now - previous | intervals])
    end
  end

  defp percentile(sorted, percent),
    do: Enum.at(sorted, max(ceil(length(sorted) * percent / 100) - 1, 0))
end
