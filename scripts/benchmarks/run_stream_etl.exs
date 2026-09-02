defmodule SimdJson.Benchmarks.StreamEtl do
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  def run do
    root = File.cwd!()
    policy = eval!(Path.join(root, "bench/stream_etl_policy.exs"))
    manifest = eval!(Path.join(root, policy.fixture_manifest))
    verify!(policy, manifest, root)
    {:ok, _} = Application.ensure_all_started(:simd_json)

    reports =
      for fixture <- manifest.fixtures,
          batch_size <- policy.batch_sizes do
        source = root |> Path.join(fixture.path) |> File.read!() |> :zlib.gunzip()
        measure_fixture(fixture, source, batch_size, policy)
      end
      |> List.flatten()

    acceptance = acceptance(reports, policy)

    report = %{
      "schema_version" => 1,
      "source_revision" => revision(),
      "source_tree" => tree(),
      "policy" => json_safe(policy),
      "manifest" => json_safe(manifest),
      "reports" => reports,
      "acceptance" => acceptance
    }

    directory = System.get_env("SIMD_JSON_QUALIFICATION_DIR", "_build/qualification/stream-etl")
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "stream-etl.json"), [:json.encode(report), "\n"])
    File.write!(Path.join(directory, "stream-etl.md"), markdown(report))
    IO.puts("stream_etl acceptance=#{acceptance["pass"]} fixtures=#{length(reports)}")
    unless acceptance["pass"], do: raise("stream ETL acceptance threshold failed")
  end

  defp measure_fixture(fixture, source, batch_size, policy) do
    samples = Map.fetch!(policy.measured_samples, fixture.name)

    for workflow <- policy.workflows do
      workflow_samples =
        for _ <- 1..(policy.warmup_samples + samples) do
          measure(workflow, fixture, source, batch_size, policy)
        end
        |> Enum.drop(policy.warmup_samples)

      %{
        "fixture" => Atom.to_string(fixture.name),
        "rows" => fixture.rows,
        "bytes" => fixture.bytes,
        "sha256" => fixture.sha256,
        "nested" => fixture.nested,
        "batch_size" => batch_size,
        "workflow" => Atom.to_string(workflow),
        "latency_us" => summarize(workflow_samples, "latency_us"),
        "time_to_first_row_us" => summarize(workflow_samples, "first_row_us"),
        "process_peak_bytes" => summarize(workflow_samples, "process_peak_bytes"),
        "rss_peak_bytes" => summarize(workflow_samples, "rss_peak_bytes"),
        "reductions" => summarize(workflow_samples, "reductions"),
        "garbage_collections" => summarize(workflow_samples, "garbage_collections"),
        "rows_per_second_p50" => throughput(fixture.rows, workflow_samples),
        "raw_samples" => workflow_samples
      }
    end
    |> List.flatten()
  end

  defp measure(workflow, fixture, source, batch_size, policy) do
    parent = self()
    baseline = BuildSmoke.execution_snapshot()

    {pid, monitor} =
      spawn_monitor(fn ->
        :erlang.garbage_collect(self(), [{:type, :major}])
        before = metrics(self())
        started = System.monotonic_time(:microsecond)

        {sum, first_row_us} =
          execute(workflow, source, fixture.nested, batch_size, policy, started)

        finished = System.monotonic_time(:microsecond)
        after_metrics = metrics(self())

        send(
          parent,
          {:result, self(), sum, first_row_us, finished - started, before, after_metrics}
        )
      end)

    sampler =
      spawn_link(fn ->
        sample(parent, pid, policy.memory_sampling_interval_milliseconds, 0, rss())
      end)

    receive do
      {:result, ^pid, sum, first_row, latency, before, after_metrics} ->
        send(sampler, {:stop, self()})
        assert_equal!(sum, fixture.expected_sum)
        assert_down!(monitor, pid)
        {peak, rss_peak} = receive do: ({:sample, ^sampler, values} -> values)
        wait_for_quiescence!()
        assert_native!(BuildSmoke.execution_snapshot(), baseline)

        %{
          "latency_us" => latency,
          "first_row_us" => first_row,
          "process_peak_bytes" => peak,
          "rss_peak_bytes" => rss_peak,
          "reductions" => max(after_metrics.reductions - before.reductions, 0),
          "garbage_collections" => max(after_metrics.gcs - before.gcs, 0)
        }
    after
      300_000 -> raise "stream ETL sample timed out"
    end
  end

  defp execute(:simd_json_stream_reduce, source, nested, batch_size, policy, started) do
    path = if nested, do: ["payload", "rows"], else: []

    source
    |> SimdJson.stream(
      path: path,
      fields: [id: ["id"], value: ["value"]],
      batch_size: batch_size,
      max_batch_bytes: policy.max_batch_bytes
    )
    |> Enum.reduce({0, nil}, fn row, {sum, first} ->
      {sum + row.id + row.value, first || System.monotonic_time(:microsecond) - started}
    end)
  end

  defp execute(:jason_decode_lookup_reduce, source, nested, _batch_size, _policy, started) do
    decoded = Jason.decode!(source)
    rows = if nested, do: get_in(decoded, ["payload", "rows"]), else: decoded
    first = System.monotonic_time(:microsecond) - started
    {Enum.reduce(rows, 0, &(&2 + &1["id"] + &1["value"])), first}
  end

  defp sample(parent, pid, interval, peak, rss_peak) do
    receive do
      {:stop, caller} -> send(caller, {:sample, self(), {peak, rss_peak}})
    after
      interval ->
        memory =
          case Process.info(pid, :memory) do
            nil -> 0
            {:memory, bytes} -> bytes
          end

        sample(parent, pid, interval, max(peak, memory), max(rss_peak, rss()))
    end
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

  defp throughput(rows, samples),
    do: round(rows * 1_000_000 / summarize(samples, "latency_us")["p50"])

  defp acceptance(reports, policy) do
    million = Enum.filter(reports, &(&1["fixture"] == "million" and &1["batch_size"] == 1_000))
    stream_million = workflow_peak(million, "simd_json_stream_reduce")
    jason_million = workflow_peak(million, "jason_decode_lookup_reduce")
    fraction = stream_million / max(jason_million, 1)

    %{
      "million_stream_peak_fraction_of_jason" => fraction,
      "million_stream_process_peak_bytes" => stream_million,
      "maximum_fraction" => policy.acceptance.million_stream_peak_fraction_of_jason,
      "maximum_process_peak_bytes" => policy.acceptance.million_stream_process_peak_bytes,
      "pass" =>
        fraction <= policy.acceptance.million_stream_peak_fraction_of_jason and
          stream_million <= policy.acceptance.million_stream_process_peak_bytes
    }
  end

  defp workflow_peak(reports, name),
    do: reports |> Enum.find(&(&1["workflow"] == name)) |> get_in(["process_peak_bytes", "p50"])

  defp verify!(policy, manifest, root) do
    unless Application.spec(:jason, :vsn) |> to_string() == policy.jason_version,
      do: raise("Jason pin changed")

    Enum.each(manifest.fixtures, fn fixture ->
      source = root |> Path.join(fixture.path) |> File.read!() |> :zlib.gunzip()
      digest = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

      unless byte_size(source) == fixture.bytes and digest == fixture.sha256,
        do: raise("fixture digest mismatch")
    end)
  end

  defp metrics(pid) do
    info = Process.info(pid, [:reductions, :garbage_collection])
    gc = Keyword.fetch!(info, :garbage_collection)
    %{reductions: Keyword.fetch!(info, :reductions), gcs: Keyword.get(gc, :minor_gcs, 0)}
  end

  defp rss do
    case File.read("/proc/self/statm") do
      {:ok, value} ->
        value |> String.split() |> Enum.at(1) |> String.to_integer() |> Kernel.*(4096)

      _ ->
        0
    end
  end

  defp wait_for_quiescence!(attempts \\ 1_000)
  defp wait_for_quiescence!(0), do: raise("native stream graph did not quiesce")

  defp wait_for_quiescence!(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and snapshot.live_operations == 0 and
         snapshot.live_stream_cursor_resources == 0,
       do: :ok,
       else:
         (
           Process.sleep(5)
           wait_for_quiescence!(attempts - 1)
         )
  end

  defp assert_native!(snapshot, baseline) do
    for key <- [
          :live_operations,
          :retained_inputs,
          :live_stream_cursor_resources,
          :retained_stream_cursor_parents
        ],
        Map.fetch!(snapshot, key) != Map.fetch!(baseline, key),
        do: raise("native gauge #{key} did not return to baseline")
  end

  defp assert_equal!(actual, expected), do: actual == expected || raise("ETL result mismatch")

  defp assert_down!(monitor, pid),
    do: receive(do: ({:DOWN, ^monitor, :process, ^pid, :normal} -> :ok))

  defp eval!(path), do: Code.eval_file(path) |> elem(0)
  defp revision, do: System.cmd("git", ["rev-parse", "HEAD"]) |> elem(0) |> String.trim()
  defp tree, do: System.cmd("git", ["rev-parse", "HEAD^{tree}"]) |> elem(0) |> String.trim()
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value) when is_struct(value, Date), do: Date.to_iso8601(value)
  defp json_safe(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_safe()

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(value), do: value

  defp markdown(report) do
    a = report["acceptance"]

    "# Milestone 3 Stream ETL Result\n\n- Result: #{a["pass"]}\n- Stream/Jason million-row peak fraction: #{Float.round(a["million_stream_peak_fraction_of_jason"], 3)}\n- Million-row stream process peak: #{a["million_stream_process_peak_bytes"]} bytes\n"
  end
end

SimdJson.Benchmarks.StreamEtl.run()
