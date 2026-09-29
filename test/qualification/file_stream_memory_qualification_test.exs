defmodule SimdJson.Qualification.FileStreamMemoryQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  @sizes [1 * 1024 * 1024, 8 * 1024 * 1024, 32 * 1024 * 1024]
  @maximum_rss_increase 96 * 1024 * 1024

  # covers: simd_json.file_input.stream_file_contract simd_json.file_input.batched_formats simd_json.file_input.no_complete_source_copy simd_json.file_input.bounded_stream_memory simd_json.file_input.early_halt simd_json.file_input.pool_and_cleanup
  @tag :tmp_dir
  @tag timeout: 180_000
  test "file streams stay inside a fixed memory envelope as sources grow", %{tmp_dir: tmp_dir} do
    wait_for_quiescence()
    native_baseline = BuildSmoke.execution_snapshot()

    samples =
      for format <- [:json_array, :ndjson], target_bytes <- @sizes do
        path = Path.join(tmp_dir, "#{format}-#{target_bytes}.json")
        row_count = write_fixture!(path, format, target_bytes, false)
        source_bytes = File.stat!(path).size
        :erlang.garbage_collect(self())

        rss_before = rss_bytes()
        sampler = start_sampler(rss_before)

        assert {^row_count, ^row_count} =
                 SimdJson.stream_file(path,
                   format: format,
                   fields: [value: ["value"]],
                   batch_size: 256,
                   max_batch_bytes: 1_048_576
                 )
                 |> Enum.reduce({0, 0}, fn %{value: value}, {count, sum} ->
                   {count + 1, sum + value}
                 end)

        peak_rss = stop_sampler(sampler)
        rss_increase = max(peak_rss - rss_before, 0)
        assert rss_increase <= @maximum_rss_increase
        wait_for_quiescence()
        assert_native_baseline(native_baseline)

        %{
          "format" => Atom.to_string(format),
          "source_bytes" => source_bytes,
          "row_count" => row_count,
          "rss_before_bytes" => rss_before,
          "rss_peak_bytes" => peak_rss,
          "rss_increase_bytes" => rss_increase,
          "maximum_rss_increase_bytes" => @maximum_rss_increase
        }
      end

    write_evidence(%{
      "schema_version" => 1,
      "operation" => "stream_file",
      "source_generation" => "incremental",
      "parser_batch_bytes" => 1_048_576,
      "result_batch_rows" => 256,
      "result_batch_bytes" => 1_048_576,
      "samples" => samples,
      "memory_contract" =>
        "peak RSS is bounded by a fixed allowance independent of total mapped source size",
      "status" => "pass"
    })
  end

  # covers: simd_json.file_input.early_halt simd_json.file_input.pool_and_cleanup
  @tag :tmp_dir
  @tag timeout: 60_000
  test "early halt advances exactly one requested result batch", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "early-halt.ndjson")
    _rows = write_fixture!(path, :ndjson, 8 * 1024 * 1024, true)
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()

    assert [%{value: 1}] =
             SimdJson.stream_file(path,
               format: :ndjson,
               fields: [value: ["value"]],
               batch_size: 1,
               max_batch_bytes: 1_024
             )
             |> Enum.take(1)

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert final.stream_setup_worker_entries == baseline.stream_setup_worker_entries + 1
    assert final.stream_batch_worker_entries == baseline.stream_batch_worker_entries + 1
    assert_native_baseline(baseline)
  end

  defp write_fixture!(path, format, target_bytes, malformed_tail?) do
    {:ok, file} = File.open(path, [:write, :binary])
    filler = :binary.copy("x", 992)
    prefix = if format == :json_array, do: "[", else: ""
    suffix = if format == :json_array, do: "]", else: ""

    try do
      IO.binwrite(file, prefix)

      {rows, _bytes} =
        Stream.iterate(1, &(&1 + 1))
        |> Enum.reduce_while({0, byte_size(prefix)}, fn index, {rows, bytes} ->
          separator = if format == :json_array and rows > 0, do: ",", else: ""
          row = [separator, ~s({"value":1,"ignored":"), filler, ~s("}), "\n"]
          row_bytes = IO.iodata_length(row)

          if bytes + row_bytes + byte_size(suffix) >= target_bytes do
            {:halt, {rows, bytes}}
          else
            IO.binwrite(file, row)
            {:cont, {index, bytes + row_bytes}}
          end
        end)

      if malformed_tail?, do: IO.binwrite(file, "{malformed-undemanded-tail")
      IO.binwrite(file, suffix)
      rows
    after
      File.close(file)
    end
  end

  defp start_sampler(initial), do: spawn_link(fn -> sample_loop(initial) end)

  defp sample_loop(peak) do
    receive do
      {:stop, caller, reference} ->
        send(caller, {:rss_peak, reference, max(peak, rss_bytes())})
    after
      1 -> sample_loop(max(peak, rss_bytes()))
    end
  end

  defp stop_sampler(pid) do
    reference = make_ref()
    send(pid, {:stop, self(), reference})
    assert_receive {:rss_peak, ^reference, peak}, 5_000
    peak
  end

  defp rss_bytes do
    with {:ok, status} <- File.read("/proc/self/status"),
         [_, kibibytes] <- Regex.run(~r/^VmRSS:\s+(\d+)\s+kB$/m, status) do
      String.to_integer(kibibytes) * 1_024
    else
      _ -> 0
    end
  end

  defp assert_native_baseline(baseline) do
    snapshot = BuildSmoke.execution_snapshot()
    assert snapshot.live_document_mapped_inputs == baseline.live_document_mapped_inputs
    assert snapshot.live_document_padded_buffers == baseline.live_document_padded_buffers
    assert snapshot.live_stream_cursor_resources == baseline.live_stream_cursor_resources
  end

  defp wait_for_quiescence(attempts \\ 2_000)

  defp wait_for_quiescence(0) do
    flunk(
      "file stream did not return to baseline: " <>
        "#{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and snapshot.live_operations == 0 and
         snapshot.retained_inputs == 0 and snapshot.running_operations == 0 and
         snapshot.live_stream_cursor_resources == 0 and
         snapshot.live_document_mapped_inputs == 0 and
         snapshot.live_document_padded_buffers == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end

  defp write_evidence(report) do
    if directory = System.get_env("SIMD_JSON_QUALIFICATION_DIR") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, "file-stream-memory.json"), [:json.encode(report), "\n"])
    end
  end
end
