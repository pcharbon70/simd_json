defmodule SimdJson.Benchmarks.WideProjection do
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  def run do
    root = File.cwd!()
    policy = eval!(Path.join(root, "bench/wide_projection_policy.exs"))
    manifest = eval!(Path.join(root, policy.fixture_manifest))
    fixture = manifest.fixture
    source = root |> Path.join(fixture.path) |> File.read!() |> :zlib.gunzip()
    verify_fixture!(source, fixture, policy)
    {:ok, _} = Application.ensure_all_started(:simd_json)

    reports = Enum.map(policy.selection_widths, &measure_width(source, manifest, policy, &1))

    report = %{
      "schema_version" => 1,
      "source_revision" => git("HEAD"),
      "source_tree" => git("HEAD^{tree}"),
      "fixture" => json_safe(fixture),
      "policy" => json_safe(policy),
      "reports" => reports
    }

    directory =
      System.get_env("SIMD_JSON_QUALIFICATION_DIR", "_build/qualification/wide-projection")

    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "wide-projection.json"), [:json.encode(report), "\n"])
    File.write!(Path.join(directory, "wide-projection.md"), markdown(report))
    print_summary(reports)
  end

  defp measure_width(source, manifest, policy, width) do
    projection = projection(manifest.field_names, policy.selected_row_index, width)
    row_number = policy.selected_row_index + 1

    expected =
      projection
      |> Enum.with_index()
      |> Map.new(fn {{key, _path}, offset} -> {key, row_number + offset} end)

    Enum.each(policy.workflows, fn workflow ->
      Enum.each(1..policy.warmup_samples_per_workflow, fn _sample ->
        ^expected = execute(workflow, source, projection)
        wait_for_quiescence!()
      end)
    end)

    samples =
      for sample <- 1..policy.measured_samples_per_workflow,
          workflow <- workflow_order(sample) do
        measurement = measure(workflow, source, projection, policy)
        ^expected = measurement.result
        wait_for_quiescence!()
        {workflow, measurement}
      end

    grouped = Enum.group_by(samples, &elem(&1, 0), &elem(&1, 1))

    %{
      "selected_fields" => width,
      "selected_row_index" => policy.selected_row_index,
      "simd_json_select" => summarize(grouped.simd_json_select),
      "jason_decode_and_lookup" => summarize(grouped.jason_decode_and_lookup)
    }
  end

  defp projection(field_names, row_index, width) do
    field_names
    |> Enum.take(width)
    |> Enum.map(fn field -> {field, [row_index, field]} end)
  end

  defp workflow_order(sample) when rem(sample, 2) == 1,
    do: [:simd_json_select, :jason_decode_and_lookup]

  defp workflow_order(_sample), do: [:jason_decode_and_lookup, :simd_json_select]

  defp measure(workflow, source, projection, policy) do
    parent = self()
    rss_baseline = rss_bytes()

    {worker, monitor} =
      spawn_monitor(fn ->
        :erlang.garbage_collect(self(), [{:type, :major}])
        started = System.monotonic_time(:microsecond)
        result = execute(workflow, source, projection)
        elapsed = System.monotonic_time(:microsecond) - started
        send(parent, {:result, self(), result, elapsed})
        receive do: ({:release, ^parent} -> :ok)
      end)

    sampler =
      spawn_link(fn ->
        sample_memory(
          parent,
          worker,
          policy.memory_sampling_interval_milliseconds,
          0,
          rss_baseline
        )
      end)

    receive do
      {:result, ^worker, result, elapsed} ->
        send(sampler, {:stop, self()})
        {process_peak, rss_peak} = receive do: ({:sample, ^sampler, peaks} -> peaks)
        send(worker, {:release, self()})
        receive do: ({:DOWN, ^monitor, :process, ^worker, :normal} -> :ok)

        %{
          result: result,
          latency_microseconds: elapsed,
          process_peak_bytes: process_peak,
          rss_increase_bytes: max(rss_peak - rss_baseline, 0)
        }
    after
      300_000 -> raise "wide projection sample timed out"
    end
  end

  defp execute(:simd_json_select, source, projection) do
    {:ok, result} = SimdJson.select(source, projection)
    result
  end

  defp execute(:jason_decode_and_lookup, source, projection) do
    decoded = Jason.decode!(source)

    Map.new(projection, fn {key, [row_index, field]} ->
      {key, get_in(decoded, [Access.at(row_index), field])}
    end)
  end

  defp sample_memory(parent, worker, interval, process_peak, rss_peak) do
    receive do
      {:stop, caller} -> send(caller, {:sample, self(), {process_peak, rss_peak}})
    after
      interval ->
        process_bytes =
          case Process.info(worker, :memory) do
            {:memory, bytes} -> bytes
            nil -> 0
          end

        sample_memory(
          parent,
          worker,
          interval,
          max(process_peak, process_bytes),
          max(rss_peak, rss_bytes())
        )
    end
  end

  defp summarize(samples) do
    %{
      "samples" => length(samples),
      "latency_microseconds" => summarize_values(samples, & &1.latency_microseconds),
      "process_peak_bytes" => summarize_values(samples, & &1.process_peak_bytes),
      "rss_increase_bytes" => summarize_values(samples, & &1.rss_increase_bytes)
    }
  end

  defp summarize_values(samples, mapper) do
    values = Enum.map(samples, mapper)

    %{
      "p50" => percentile(values, 50),
      "minimum" => Enum.min(values),
      "maximum" => Enum.max(values)
    }
  end

  defp percentile(values, percentage) do
    sorted = Enum.sort(values)
    Enum.at(sorted, max(ceil(length(sorted) * percentage / 100) - 1, 0))
  end

  defp verify_fixture!(source, fixture, policy) do
    digest = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

    unless Application.spec(:jason, :vsn) |> to_string() == policy.jason_version do
      raise "Jason pin changed"
    end

    unless byte_size(source) == fixture.bytes and digest == fixture.sha256 do
      raise "wide projection fixture does not match its manifest"
    end
  end

  defp wait_for_quiescence!(attempts \\ 2_000)
  defp wait_for_quiescence!(0), do: raise("native projection did not quiesce")

  defp wait_for_quiescence!(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and snapshot.live_operations == 0 and
         snapshot.retained_inputs == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence!(attempts - 1)
    end
  end

  defp markdown(report) do
    rows =
      Enum.map(report["reports"], fn row ->
        simd = row["simd_json_select"]
        jason = row["jason_decode_and_lookup"]
        simd_latency = get_in(simd, ["latency_microseconds", "p50"])
        jason_latency = get_in(jason, ["latency_microseconds", "p50"])

        "| #{row["selected_fields"]} | #{milliseconds(simd_latency)} | " <>
          "#{milliseconds(jason_latency)} | " <>
          "#{Float.round(jason_latency / max(simd_latency, 1), 2)}× | " <>
          "#{mebibytes(get_in(simd, ["process_peak_bytes", "p50"]))} | " <>
          "#{mebibytes(get_in(jason, ["process_peak_bytes", "p50"]))} | " <>
          "#{mebibytes(get_in(simd, ["rss_increase_bytes", "p50"]))} | " <>
          "#{mebibytes(get_in(jason, ["rss_increase_bytes", "p50"]))} |\n"
      end)

    [
      "# Million-row wide projection benchmark\n\n",
      "Source revision: `#{report["source_revision"]}`  \n",
      "Jason version: `#{get_in(report, ["policy", "jason_version"])}`  \n",
      "Fixture: #{report["fixture"]["rows"]} rows × ",
      "#{report["fixture"]["fields_per_row"]} fields, ",
      "#{report["fixture"]["bytes"]} uncompressed bytes\n\n",
      "Each width selects fields from zero-based row ",
      "#{get_in(report, ["policy", "selected_row_index"])}. Jason fully decodes the same ",
      "document and performs equivalent lookups. Decompression is outside the timed region.\n\n",
      "Unlike the earlier million-row supplement, which selected scalar paths distributed ",
      "across a narrow three-field row shape (`id`, `value`, and unselected `ignored`), ",
      "this benchmark holds the row and document constant while increasing the number of ",
      "fields returned from one genuinely wide row.\n\n",
      "| Selected fields | SimdJson.select p50 (ms) | Jason decode + lookup p50 (ms) | SimdJson speedup | SimdJson worker peak (MiB) | Jason worker peak (MiB) | SimdJson RSS increase (MiB) | Jason RSS increase (MiB) |\n",
      "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n",
      rows,
      "\nWorker peak measures the isolated caller. RSS increase is whole-VM peak minus its per-sample baseline and remains allocator/host contextual.\n"
    ]
  end

  defp print_summary(reports) do
    Enum.each(reports, fn row ->
      simd = get_in(row, ["simd_json_select", "latency_microseconds", "p50"])
      jason = get_in(row, ["jason_decode_and_lookup", "latency_microseconds", "p50"])

      IO.puts(
        "wide_projection fields=#{row["selected_fields"]} " <>
          "simd_p50_ms=#{milliseconds(simd)} jason_p50_ms=#{milliseconds(jason)} " <>
          "speedup=#{Float.round(jason / max(simd, 1), 2)}"
      )
    end)
  end

  defp rss_bytes do
    case File.read("/proc/self/statm") do
      {:ok, value} ->
        value |> String.split() |> Enum.at(1) |> String.to_integer() |> Kernel.*(4096)

      _ ->
        0
    end
  end

  defp milliseconds(microseconds), do: Float.round(microseconds / 1_000, 3)
  defp mebibytes(bytes), do: Float.round(bytes / 1_048_576, 2)
  defp eval!(path), do: Code.eval_file(path) |> elem(0)
  defp git(ref), do: System.cmd("git", ["rev-parse", ref]) |> elem(0) |> String.trim()

  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value) when is_struct(value, Date), do: Date.to_iso8601(value)

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_safe(v)} end)

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(value), do: value
end

SimdJson.Benchmarks.WideProjection.run()
