defmodule SimdJson.Benchmarks.Decode do
  @warmups 2
  @samples 5

  def run do
    {:ok, _} = Application.ensure_all_started(:simd_json)
    wait_for_quiescence!()
    baseline = SimdJson.Native.BuildSmoke.execution_snapshot()
    fixtures = fixtures()

    reports =
      for {name, input, expected} <- fixtures,
          {decoder, function} <- decoders() do
        samples =
          for _ <- 1..(@warmups + @samples) do
            measure(function, input, expected)
          end
          |> Enum.drop(@warmups)

        %{
          "fixture" => name,
          "decoder" => decoder,
          "input_bytes" => byte_size(input),
          "latency_us" => summarize(samples, "latency_us"),
          "throughput_bytes_per_second" => throughput(input, samples),
          "reductions" => summarize(samples, "reductions"),
          "process_memory_delta_bytes" => summarize(samples, "memory_delta_bytes"),
          "garbage_collections" => summarize(samples, "garbage_collections"),
          "raw_samples" => samples
        }
      end

    wait_for_quiescence!()
    final = SimdJson.Native.BuildSmoke.execution_snapshot()
    assert_native_baseline!(baseline, final)

    report = %{
      "schema_version" => 1,
      "source_revision" => revision(),
      "source_tree" => tree(),
      "jason_version" => Application.spec(:jason, :vsn) |> to_string(),
      "warmups" => @warmups,
      "samples" => @samples,
      "reports" => reports,
      "native_baseline" => native_gauges(baseline),
      "native_final" => native_gauges(final),
      "acceptance" => %{"correctness" => true, "pass" => true}
    }

    directory = System.get_env("SIMD_JSON_QUALIFICATION_DIR", "_build/qualification/decode")
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "decode-benchmark.json"), [:json.encode(report), "\n"])
    IO.puts("decode_benchmark acceptance=true profiles=#{length(reports)}")
  end

  defp fixtures do
    medium = Map.new(1..500, &{"key-#{&1}", [&1, "value-#{&1}", rem(&1, 2) == 0]})
    large_array = Enum.map(1..20_000, &%{"id" => &1, "value" => &1 * 2})
    nested = Enum.reduce(1..128, nil, fn depth, value -> %{"depth" => depth, "next" => value} end)
    strings = Enum.map(1..2_000, &String.duplicate(Integer.to_string(rem(&1, 10)), 64))
    numbers = Enum.map(1..20_000, &(&1 * 1.25))

    [
      {"small", ~S({"ready":true,"count":3}), %{"ready" => true, "count" => 3}},
      {"medium", Jason.encode!(medium), medium},
      {"large_array", Jason.encode!(large_array), large_array},
      {"nested", Jason.encode!(nested), nested},
      {"strings", Jason.encode!(strings), strings},
      {"numbers", Jason.encode!(numbers), numbers},
      {"malformed", "[1,2,", :error}
    ]
  end

  defp decoders do
    [
      {"simd_json", &SimdJson.decode/1},
      {"jason_1_4_5", &Jason.decode/1}
    ]
  end

  defp measure(function, input, expected) do
    :erlang.garbage_collect(self(), [{:type, :major}])
    before = metrics()
    {latency, result} = :timer.tc(function, [input])
    after_metrics = metrics()

    case expected do
      :error -> match?({:error, _}, result) || raise("malformed fixture unexpectedly succeeded")
      value -> result === {:ok, value} || raise("decode benchmark result mismatch")
    end

    %{
      "latency_us" => latency,
      "reductions" => max(after_metrics.reductions - before.reductions, 0),
      "memory_delta_bytes" => max(after_metrics.memory - before.memory, 0),
      "garbage_collections" => max(after_metrics.gcs - before.gcs, 0)
    }
  end

  defp metrics do
    info = Process.info(self(), [:memory, :reductions, :garbage_collection])
    gc = Keyword.fetch!(info, :garbage_collection)

    %{
      memory: Keyword.fetch!(info, :memory),
      reductions: Keyword.fetch!(info, :reductions),
      gcs: Keyword.get(gc, :minor_gcs, 0)
    }
  end

  defp summarize(samples, key) do
    sorted = samples |> Enum.map(& &1[key]) |> Enum.sort()

    %{
      "p50" => percentile(sorted, 50),
      "p95" => percentile(sorted, 95),
      "p99" => percentile(sorted, 99),
      "max" => List.last(sorted)
    }
  end

  defp percentile(sorted, percent),
    do: Enum.at(sorted, max(ceil(length(sorted) * percent / 100) - 1, 0))

  defp throughput(input, samples) do
    p50 = summarize(samples, "latency_us")["p50"]
    round(byte_size(input) * 1_000_000 / max(p50, 1))
  end

  defp revision, do: System.cmd("git", ["rev-parse", "HEAD"]) |> elem(0) |> String.trim()
  defp tree, do: System.cmd("git", ["rev-parse", "HEAD^{tree}"]) |> elem(0) |> String.trim()

  defp wait_for_quiescence!(attempts \\ 1_000)
  defp wait_for_quiescence!(0), do: raise("decode native state did not quiesce")

  defp wait_for_quiescence!(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(SimdJson.Native.OperationCoordinator))
    snapshot = SimdJson.Native.BuildSmoke.execution_snapshot()

    if SimdJson.Native.OperationCoordinator.snapshot().live_requests == 0 and
         snapshot.live_operations == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence!(attempts - 1)
    end
  end

  defp native_gauges(snapshot),
    do: Map.take(snapshot, [:live_operations, :retained_inputs, :live_documents])

  defp assert_native_baseline!(baseline, final) do
    native_gauges(baseline) == native_gauges(final) ||
      raise("decode native lifecycle gauges did not return to baseline")
  end
end

SimdJson.Benchmarks.Decode.run()
