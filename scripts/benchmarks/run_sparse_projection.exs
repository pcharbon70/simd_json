defmodule SimdJson.Benchmarks.SparseProjection do
  @moduledoc false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  @projection [
    id: ["customer", "id"],
    name: ["customer", "name"],
    sku: ["orders", 0, "sku"],
    active: ["meta", "active"],
    nothing: ["meta", "nothing"]
  ]

  def run do
    repository_root = File.cwd!()
    policy = eval_policy!(Path.join(repository_root, "bench/sparse_projection_policy.exs"))
    manifest = read_json!(Path.join(repository_root, policy.fixture_manifest))
    verify_manifest!(manifest, policy, repository_root)
    {:ok, _applications} = Application.ensure_all_started(:simd_json)
    wait_for_quiescence!()

    fixtures =
      Enum.map(manifest["fixtures"], fn fixture ->
        source = File.read!(Path.join(repository_root, fixture["path"]))
        expected = expected_result(fixture["expected"])

        %{
          name: String.to_atom(fixture["name"]),
          source: source,
          expected: expected,
          meta: fixture
        }
      end)

    warm_up(fixtures, policy)
    previous_wall_time = :erlang.system_flag(:scheduler_wall_time, true)

    {fixture_reports, scheduler_utilization} =
      try do
        wall_before = scheduler_wall_time_snapshot()
        reports = Enum.map(fixtures, &measure_fixture(&1, policy))
        wall_after = scheduler_wall_time_snapshot()
        {reports, scheduler_utilization(wall_before, wall_after)}
      after
        :erlang.system_flag(:scheduler_wall_time, previous_wall_time)
      end

    acceptance = allocation_acceptance(fixture_reports, policy)
    report = report(policy, manifest, fixture_reports, scheduler_utilization, acceptance)
    write_report(report)
    print_summary(fixture_reports, acceptance)

    unless acceptance["pass"] do
      raise "sparse projection allocation threshold failed"
    end
  end

  defp warm_up(fixtures, policy) do
    Enum.each(fixtures, fn fixture ->
      for sample <- 1..policy.warmup_samples_per_workflow_and_fixture,
          workflow <- workflow_order(sample) do
        assert_result!(workflow(workflow, fixture.source), fixture.expected)
      end
    end)

    wait_for_quiescence!()
  end

  defp measure_fixture(fixture, policy) do
    samples =
      for sample <- 1..policy.measured_samples_per_workflow_and_fixture,
          workflow <- workflow_order(sample) do
        measure_sample(workflow, fixture, policy)
      end

    grouped = Enum.group_by(samples, & &1["workflow"])

    %{
      "name" => Atom.to_string(fixture.name),
      "bytes" => fixture.meta["bytes"],
      "sha256" => fixture.meta["sha256"],
      "workflows" =>
        Map.new(grouped, fn {workflow, workflow_samples} ->
          {workflow, summarize_samples(workflow_samples)}
        end),
      "raw_samples" => samples
    }
  end

  defp workflow_order(sample) when rem(sample, 2) == 1,
    do: [:simd_json_select, :jason_decode_and_lookup]

  defp workflow_order(_sample), do: [:jason_decode_and_lookup, :simd_json_select]

  defp measure_sample(workflow_name, fixture, policy) do
    parent = self()
    native_baseline = BuildSmoke.execution_snapshot()

    {worker, monitor} =
      spawn_monitor(fn -> measurement_worker(parent, workflow_name, fixture) end)

    send(worker, :prepare)
    initial = receive_message!({:measurement_ready, worker}, 5_000)
    1 = :erlang.trace(worker, true, [:garbage_collection, :timestamp])
    sampler = start_sampler(worker, native_baseline, policy.memory_sampling_interval_milliseconds)
    send(worker, :measure)

    {measurement, gc_trace} = await_measurement(worker, empty_gc_trace())
    delivered = :erlang.trace_delivered(worker)
    gc_trace = drain_trace(worker, delivered, gc_trace)
    1 = :erlang.trace(worker, false, [:garbage_collection, :timestamp])
    sampler_result = stop_sampler(sampler)
    send(worker, :release)
    assert_down!(monitor, worker)

    assert_result!(measurement.result, fixture.expected)
    wait_for_quiescence!()
    native_final = BuildSmoke.execution_snapshot()
    assert_native_baseline!(native_final, native_baseline)

    live_delta = max(measurement.final.live_words - initial.live_words, 0)
    allocated_words = gc_trace.reclaimed_words + live_delta
    word_bytes = :erlang.system_info(:wordsize)

    %{
      "workflow" => Atom.to_string(workflow_name),
      "latency_nanoseconds" => measurement.latency_nanoseconds,
      "estimated_beam_allocated_words" => allocated_words,
      "estimated_beam_allocated_bytes" => allocated_words * word_bytes,
      "allocation_method" =>
        "caller GC reclaimed words plus post-fullsweep retained live-word delta",
      "process_initial_bytes" => initial.memory_bytes,
      "process_final_bytes" => measurement.final.memory_bytes,
      "process_peak_bytes" => sampler_result.process_peak_bytes,
      "binary_initial_bytes" => initial.binary_bytes,
      "binary_final_bytes" => measurement.final.binary_bytes,
      "binary_peak_bytes" => sampler_result.binary_peak_bytes,
      "retained_result_referenced_binary_bytes" => measurement.result_referenced_binary_bytes,
      "garbage_collections" => gc_trace.collections,
      "garbage_collection_microseconds" => gc_trace.total_microseconds,
      "reductions" => max(measurement.final.reductions - initial.reductions, 0),
      "rss_peak_bytes" => sampler_result.rss_peak_bytes,
      "native_baseline" => stringify_map(native_baseline),
      "native_peak" => stringify_map(sampler_result.native_peak),
      "native_final" => stringify_map(native_final)
    }
  end

  defp measurement_worker(parent, workflow_name, fixture) do
    receive do
      :prepare -> :ok
    end

    :erlang.garbage_collect(self(), [{:type, :major}])
    initial = process_metrics(self())
    send(parent, {:measurement_ready, self(), initial})

    receive do
      :measure -> :ok
    end

    started = System.monotonic_time(:nanosecond)
    result = workflow(workflow_name, fixture.source)
    latency = System.monotonic_time(:nanosecond) - started
    :erlang.garbage_collect(self(), [{:type, :major}])
    final = process_metrics(self())

    send(parent, {
      :measurement_done,
      self(),
      %{
        result: result,
        latency_nanoseconds: latency,
        final: final,
        result_referenced_binary_bytes: referenced_binary_bytes(result)
      }
    })

    receive do
      :release -> :ok
    end
  end

  defp workflow(:simd_json_select, source), do: SimdJson.select(source, @projection)

  defp workflow(:jason_decode_and_lookup, source) do
    decoded = Jason.decode!(source)

    {:ok,
     %{
       id: get_in(decoded, ["customer", "id"]),
       name: get_in(decoded, ["customer", "name"]),
       sku: get_in(decoded, ["orders", Access.at(0), "sku"]),
       active: get_in(decoded, ["meta", "active"]),
       nothing: get_in(decoded, ["meta", "nothing"])
     }}
  end

  defp start_sampler(worker, native_baseline, interval_ms) do
    parent = self()

    spawn_link(fn ->
      sample_loop(
        parent,
        worker,
        interval_ms,
        %{
          process_peak_bytes: 0,
          binary_peak_bytes: 0,
          rss_peak_bytes: rss_bytes(),
          native_peak: native_baseline
        }
      )
    end)
  end

  defp sample_loop(parent, worker, interval_ms, peaks) do
    receive do
      {:stop, reference} ->
        send(parent, {:sampler_stopped, reference, peaks})
    after
      interval_ms ->
        metrics = process_metrics(worker)
        native = BuildSmoke.execution_snapshot()

        peaks = %{
          process_peak_bytes: max(peaks.process_peak_bytes, metrics.memory_bytes),
          binary_peak_bytes: max(peaks.binary_peak_bytes, metrics.binary_bytes),
          rss_peak_bytes: max(peaks.rss_peak_bytes, rss_bytes()),
          native_peak: max_map(peaks.native_peak, native)
        }

        sample_loop(parent, worker, interval_ms, peaks)
    end
  end

  defp stop_sampler(sampler) do
    reference = make_ref()
    send(sampler, {:stop, reference})

    receive do
      {:sampler_stopped, ^reference, peaks} -> peaks
    after
      5_000 -> raise "benchmark memory sampler did not stop"
    end
  end

  defp process_metrics(pid) do
    case :erlang.process_info(pid, [
           :memory,
           :binary,
           :reductions,
           :garbage_collection_info
         ]) do
      nil ->
        %{memory_bytes: 0, binary_bytes: 0, reductions: 0, live_words: 0}

      info ->
        gc = Keyword.fetch!(info, :garbage_collection_info)

        %{
          memory_bytes: Keyword.fetch!(info, :memory),
          binary_bytes: info |> Keyword.fetch!(:binary) |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
          reductions: Keyword.fetch!(info, :reductions),
          live_words:
            Keyword.get(gc, :heap_size, 0) + Keyword.get(gc, :old_heap_size, 0) +
              Keyword.get(gc, :mbuf_size, 0)
        }
    end
  end

  defp empty_gc_trace do
    %{starts: %{}, reclaimed_words: 0, collections: 0, total_microseconds: 0}
  end

  defp await_measurement(worker, trace) do
    receive do
      {:measurement_done, ^worker, measurement} ->
        {measurement, trace}

      {:trace_ts, ^worker, event, info, timestamp} ->
        await_measurement(worker, update_gc_trace(trace, event, info, timestamp))
    after
      120_000 -> raise "benchmark sample timed out"
    end
  end

  defp drain_trace(worker, delivered, trace) do
    receive do
      {:trace_delivered, ^worker, ^delivered} ->
        trace

      {:trace_ts, ^worker, event, info, timestamp} ->
        drain_trace(worker, delivered, update_gc_trace(trace, event, info, timestamp))
    after
      5_000 -> raise "garbage-collection trace did not drain"
    end
  end

  defp update_gc_trace(trace, event, _info, timestamp)
       when event in [:gc_minor_start, :gc_major_start] do
    kind = if(event == :gc_minor_start, do: :minor, else: :major)
    %{trace | starts: Map.put(trace.starts, kind, timestamp)}
  end

  defp update_gc_trace(trace, event, info, timestamp)
       when event in [:gc_minor_end, :gc_major_end] do
    kind = if(event == :gc_minor_end, do: :minor, else: :major)
    started = Map.get(trace.starts, kind, timestamp)

    %{
      trace
      | starts: Map.delete(trace.starts, kind),
        reclaimed_words: trace.reclaimed_words + Keyword.get(info, :wordsize, 0),
        collections: trace.collections + 1,
        total_microseconds: trace.total_microseconds + max(:timer.now_diff(timestamp, started), 0)
    }
  end

  defp update_gc_trace(trace, _event, _info, _timestamp), do: trace

  defp summarize_samples(samples) do
    latencies = Enum.map(samples, & &1["latency_nanoseconds"])
    allocations = Enum.map(samples, & &1["estimated_beam_allocated_bytes"])
    median_latency = percentile(latencies, 50)

    %{
      "samples" => length(samples),
      "latency_nanoseconds" => %{
        "p50" => median_latency,
        "p95" => percentile(latencies, 95),
        "p99" => percentile(latencies, 99),
        "minimum" => Enum.min(latencies),
        "maximum" => Enum.max(latencies)
      },
      "throughput_operations_per_second_at_p50" =>
        Float.round(1_000_000_000 / max(median_latency, 1), 3),
      "median_estimated_beam_allocated_words" =>
        div(percentile(allocations, 50), :erlang.system_info(:wordsize)),
      "median_estimated_beam_allocated_bytes" => percentile(allocations, 50),
      "maximum_process_peak_bytes" =>
        Enum.max_by(samples, & &1["process_peak_bytes"])["process_peak_bytes"],
      "maximum_binary_peak_bytes" =>
        Enum.max_by(samples, & &1["binary_peak_bytes"])["binary_peak_bytes"],
      "maximum_rss_peak_bytes" => Enum.max_by(samples, & &1["rss_peak_bytes"])["rss_peak_bytes"],
      "median_garbage_collections" =>
        samples |> Enum.map(& &1["garbage_collections"]) |> percentile(50),
      "median_garbage_collection_microseconds" =>
        samples |> Enum.map(& &1["garbage_collection_microseconds"]) |> percentile(50),
      "median_reductions" => samples |> Enum.map(& &1["reductions"]) |> percentile(50),
      "maximum_retained_result_referenced_binary_bytes" =>
        samples
        |> Enum.map(& &1["retained_result_referenced_binary_bytes"])
        |> Enum.max()
    }
  end

  defp allocation_acceptance(fixture_reports, policy) do
    threshold = policy.allocation_acceptance.maximum_simd_json_fraction_of_jason
    required = Enum.map(policy.allocation_acceptance.fixtures, &Atom.to_string/1)

    fixture_results =
      fixture_reports
      |> Enum.filter(&(&1["name"] in required))
      |> Enum.map(fn fixture ->
        simd =
          get_in(fixture, [
            "workflows",
            "simd_json_select",
            "median_estimated_beam_allocated_bytes"
          ])

        jason =
          get_in(fixture, [
            "workflows",
            "jason_decode_and_lookup",
            "median_estimated_beam_allocated_bytes"
          ])

        fraction = if jason == 0, do: 1.0, else: simd / jason

        %{
          "fixture" => fixture["name"],
          "simd_json_bytes" => simd,
          "jason_bytes" => jason,
          "simd_json_fraction_of_jason" => fraction,
          "reduction_percent" => Float.round((1.0 - fraction) * 100, 3),
          "pass" => fraction <= threshold
        }
      end)

    %{
      "metric" => Atom.to_string(policy.allocation_acceptance.metric),
      "maximum_simd_json_fraction_of_jason" => threshold,
      "required_reduction_percent" => policy.allocation_acceptance.required_reduction_percent,
      "fixtures" => fixture_results,
      "pass" =>
        length(fixture_results) == length(required) and Enum.all?(fixture_results, & &1["pass"])
    }
  end

  defp report(policy, manifest, fixtures, utilization, acceptance) do
    %{
      "schema_version" => 1,
      "source_revision" => git_identity("HEAD"),
      "source_tree" => git_identity("HEAD^{tree}"),
      "command" => "bash scripts/ci/qualify_projection_benchmark.sh",
      "environment" => environment(),
      "dependency" => %{"jason" => "1.4.5"},
      "policy" => json_safe(policy),
      "fixture_manifest_sha256" => sha256(File.read!(policy.fixture_manifest)),
      "fixture_generator_seed" => manifest["seed"],
      "scheduler_utilization" => stringify_scheduler_utilization(utilization),
      "fixtures" => fixtures,
      "allocation_acceptance" => acceptance,
      "latency_interpretation" => "measured context on this host; no universal superiority claim",
      "result" => if(acceptance["pass"], do: "pass", else: "fail")
    }
  end

  defp write_report(report) do
    directory =
      System.get_env("SIMD_JSON_QUALIFICATION_DIR") ||
        Path.expand("../../_build/qualification/benchmark", __DIR__)

    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "projection-benchmark.json"), [:json.encode(report), "\n"])

    rows =
      Enum.flat_map(report["fixtures"], fn fixture ->
        Enum.map(fixture["workflows"], fn {workflow, summary} ->
          "| #{fixture["name"]} | #{workflow} | #{summary["latency_nanoseconds"]["p50"]} | " <>
            "#{summary["throughput_operations_per_second_at_p50"]} | " <>
            "#{summary["median_estimated_beam_allocated_bytes"]} |"
        end)
      end)

    acceptance = report["allocation_acceptance"]

    markdown = [
      "# Sparse projection benchmark\n\n",
      "Source revision: `#{report["source_revision"]}`\n\n",
      "| Fixture | Workflow | p50 ns | ops/s at p50 | median estimated BEAM bytes |\n",
      "| --- | --- | ---: | ---: | ---: |\n",
      Enum.join(rows, "\n"),
      "\n\nAllocation threshold: **#{if acceptance["pass"], do: "PASS", else: "FAIL"}**. ",
      "Latency and throughput are context only.\n"
    ]

    File.write!(Path.join(directory, "projection-benchmark.md"), markdown)
  end

  defp print_summary(fixtures, acceptance) do
    Enum.each(fixtures, fn fixture ->
      simd = fixture["workflows"]["simd_json_select"]
      jason = fixture["workflows"]["jason_decode_and_lookup"]

      IO.puts(
        "projection_benchmark fixture=#{fixture["name"]} " <>
          "simd_p50_us=#{Float.round(simd["latency_nanoseconds"]["p50"] / 1_000, 3)} " <>
          "jason_p50_us=#{Float.round(jason["latency_nanoseconds"]["p50"] / 1_000, 3)} " <>
          "simd_alloc=#{simd["median_estimated_beam_allocated_bytes"]} " <>
          "jason_alloc=#{jason["median_estimated_beam_allocated_bytes"]}"
      )
    end)

    IO.puts("projection_benchmark allocation_threshold_pass=#{acceptance["pass"]}")
  end

  defp percentile(values, percentage) do
    sorted = Enum.sort(values)
    Enum.at(sorted, max(ceil(length(sorted) * percentage / 100) - 1, 0))
  end

  defp scheduler_wall_time_snapshot do
    :scheduler_wall_time_all
    |> :erlang.statistics()
    |> Map.new(fn {scheduler, active, total} -> {scheduler, {active, total}} end)
  end

  defp scheduler_utilization(before_snapshot, after_snapshot) do
    normal = :erlang.system_info(:schedulers)
    dirty_cpu = :erlang.system_info(:dirty_cpu_schedulers)
    dirty_io = :erlang.system_info(:dirty_io_schedulers)

    %{
      normal: utilization_for(before_snapshot, after_snapshot, 1, normal),
      dirty_cpu: utilization_for(before_snapshot, after_snapshot, normal + 1, dirty_cpu),
      dirty_io: utilization_for(before_snapshot, after_snapshot, normal + dirty_cpu + 1, dirty_io)
    }
  end

  defp utilization_for(_before, _after, _first, 0), do: %{active: 0, total: 0, ratio: 0.0}

  defp utilization_for(before_snapshot, after_snapshot, first, count) do
    {active, total} =
      first..(first + count - 1)
      |> Enum.reduce({0, 0}, fn scheduler, {active_acc, total_acc} ->
        {before_active, before_total} = Map.fetch!(before_snapshot, scheduler)
        {after_active, after_total} = Map.fetch!(after_snapshot, scheduler)

        {active_acc + max(after_active - before_active, 0),
         total_acc + max(after_total - before_total, 0)}
      end)

    %{active: active, total: total, ratio: if(total == 0, do: 0.0, else: active / total)}
  end

  defp stringify_scheduler_utilization(utilization) do
    Map.new(utilization, fn {name, values} ->
      {to_string(name),
       %{
         "active_microseconds" => values.active,
         "total_microseconds" => values.total,
         "ratio" => values.ratio
       }}
    end)
  end

  defp referenced_binary_bytes({:ok, result}) do
    result
    |> Map.values()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&:binary.referenced_byte_size/1)
    |> Enum.sum()
  end

  defp referenced_binary_bytes(_result), do: 0

  defp expected_result(expected) do
    %{
      id: expected["id"],
      name: expected["name"],
      sku: expected["sku"],
      active: expected["active"],
      nothing: expected["nothing"]
    }
  end

  defp assert_result!({:ok, result}, expected) when result == expected, do: :ok

  defp assert_result!(result, expected) do
    raise "benchmark workflows are not equivalent: result=#{inspect(result)} expected=#{inspect(expected)}"
  end

  defp receive_message!({tag, pid}, timeout) do
    receive do
      {^tag, ^pid, value} -> value
    after
      timeout -> raise "benchmark worker did not become ready"
    end
  end

  defp assert_down!(monitor, worker) do
    receive do
      {:DOWN, ^monitor, :process, ^worker, :normal} ->
        :ok

      {:DOWN, ^monitor, :process, ^worker, reason} ->
        raise "benchmark worker failed: #{inspect(reason)}"
    after
      5_000 -> raise "benchmark worker did not exit"
    end
  end

  defp assert_native_baseline!(final, baseline) do
    fields = [
      :live_operations,
      :retained_inputs,
      :queued_operations,
      :queued_cleanup,
      :running_operations,
      :live_documents,
      :live_document_controls,
      :dispatcher_queued_cleanup,
      :dispatcher_active_cleanup,
      :retained_failed_cleanup,
      :live_projection_operations,
      :retained_projection_binaries,
      :retained_projection_documents,
      :live_projection_environments,
      :live_projection_plans,
      :live_projection_slots,
      :live_projection_temporary_document_graphs
    ]

    Enum.each(fields, fn field ->
      if Map.fetch!(final, field) != Map.fetch!(baseline, field) do
        raise "native gauge #{field} did not return to benchmark baseline"
      end
    end)
  end

  defp wait_for_quiescence!(attempts \\ 2_000)
  defp wait_for_quiescence!(0), do: raise("projection benchmark did not reach native baseline")

  defp wait_for_quiescence!(attempts) do
    if coordinator = Process.whereis(OperationCoordinator) do
      :erlang.garbage_collect(coordinator)
    end

    snapshot = BuildSmoke.execution_snapshot()

    idle? =
      OperationCoordinator.snapshot().live_requests == 0 and snapshot.live_operations == 0 and
        snapshot.live_documents == 0 and snapshot.live_projection_operations == 0 and
        snapshot.live_projection_plans == 0 and snapshot.live_projection_slots == 0 and
        snapshot.live_projection_environments == 0 and
        snapshot.live_projection_temporary_document_graphs == 0

    if idle? do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence!(attempts - 1)
    end
  end

  defp verify_manifest!(manifest, policy, repository_root) do
    names = Enum.map(manifest["fixtures"], & &1["name"])
    required = Enum.map(policy.required_fixtures, &Atom.to_string/1)

    unless manifest["seed"] == policy.fixture_generator_seed and
             Enum.sort(names) == Enum.sort(required) do
      raise "fixture manifest does not match frozen benchmark policy"
    end

    Enum.each(manifest["fixtures"], fn fixture ->
      source = File.read!(Path.join(repository_root, fixture["path"]))

      unless byte_size(source) == fixture["bytes"] and sha256(source) == fixture["sha256"] do
        raise "fixture digest mismatch: #{fixture["name"]}"
      end

      Jason.decode!(source)
    end)
  end

  defp eval_policy!(path) do
    {policy, _binding} = Code.eval_file(path)
    policy
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()

  defp environment do
    %{
      "otp" => System.otp_release(),
      "erts" => :erlang.system_info(:version) |> List.to_string(),
      "elixir" => System.version(),
      "os" => os_description(),
      "architecture" => :erlang.system_info(:system_architecture) |> List.to_string(),
      "cpu" => cpu_description(),
      "normal_schedulers" => :erlang.system_info(:schedulers),
      "normal_schedulers_online" => System.schedulers_online(),
      "dirty_cpu_schedulers" => :erlang.system_info(:dirty_cpu_schedulers),
      "dirty_io_schedulers" => :erlang.system_info(:dirty_io_schedulers),
      "word_bytes" => :erlang.system_info(:wordsize),
      "ci" => System.get_env("CI") == "true"
    }
  end

  defp os_description do
    with {:ok, contents} <- File.read("/etc/os-release"),
         [_, description] <- Regex.run(~r/^PRETTY_NAME="?([^"\n]+)"?$/m, contents) do
      description
    else
      _other -> inspect(:os.type())
    end
  end

  defp cpu_description do
    with {:ok, contents} <- File.read("/proc/cpuinfo"),
         [_, model] <- Regex.run(~r/^model name\s*:\s*(.+)$/m, contents) do
      String.trim(model)
    else
      _other -> "unavailable"
    end
  end

  defp rss_bytes do
    with {:ok, status} <- File.read("/proc/self/status"),
         [_, kibibytes] <- Regex.run(~r/^VmRSS:\s+(\d+)\s+kB$/m, status) do
      String.to_integer(kibibytes) * 1_024
    else
      _other -> 0
    end
  end

  defp git_identity(revision) do
    case System.cmd("git", ["rev-parse", revision], stderr_to_stdout: true) do
      {value, 0} -> String.trim(value)
      _other -> "unavailable"
    end
  end

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp stringify_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp max_map(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value -> max(left_value, right_value) end)
  end

  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%Date{} = date), do: Date.to_iso8601(date)

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(value), do: value
end

SimdJson.Benchmarks.SparseProjection.run()
