defmodule SimdJson.Qualification.FileSelectionMemoryQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  @sizes [1 * 1024 * 1024, 8 * 1024 * 1024, 32 * 1024 * 1024]
  @fixed_rss_allowance 64 * 1024 * 1024
  @source_multiplier 4

  # covers: simd_json.file_input.native_path_boundary simd_json.file_input.select_file_contract simd_json.file_input.no_complete_source_copy simd_json.file_input.pool_and_cleanup
  @tag :tmp_dir
  @tag timeout: 120_000
  test "records mapped sparse-selection RSS across progressively larger files", %{
    tmp_dir: tmp_dir
  } do
    wait_for_quiescence()
    native_baseline = BuildSmoke.execution_snapshot()

    samples =
      for ignored_bytes <- @sizes do
        path = Path.join(tmp_dir, "selection-#{ignored_bytes}.json")
        write_fixture!(path, ignored_bytes)
        source_bytes = File.stat!(path).size
        :erlang.garbage_collect(self())

        rss_before = rss_bytes()
        sampler = start_sampler(rss_before)

        assert {:ok, %{first: 1, selected: "small", last: 3}} =
                 SimdJson.select_file(path,
                   first: ["first"],
                   selected: ["selected"],
                   last: ["last"]
                 )

        peak_rss = stop_sampler(sampler)
        rss_increase = max(peak_rss - rss_before, 0)

        assert rss_increase <= @fixed_rss_allowance + source_bytes * @source_multiplier
        wait_for_quiescence()

        snapshot = BuildSmoke.execution_snapshot()
        assert snapshot.live_document_mapped_inputs == native_baseline.live_document_mapped_inputs

        assert snapshot.live_document_padded_buffers ==
                 native_baseline.live_document_padded_buffers

        %{
          "source_bytes" => source_bytes,
          "rss_before_bytes" => rss_before,
          "rss_peak_bytes" => peak_rss,
          "rss_increase_bytes" => rss_increase,
          "maximum_rss_increase_bytes" => @fixed_rss_allowance + source_bytes * @source_multiplier
        }
      end

    write_evidence(%{
      "schema_version" => 1,
      "operation" => "select_file",
      "source_generation" => "incremental",
      "samples" => samples,
      "memory_contract" =>
        "source bytes are memory-mapped without a BEAM or padded native source copy; " <>
          "simdjson structural indexes may scale with input size",
      "status" => "pass"
    })
  end

  defp write_fixture!(path, ignored_bytes) do
    {:ok, file} = File.open(path, [:write, :binary])

    try do
      IO.binwrite(file, ~s({"first":1,"selected":"small","ignored":"))
      chunk = :binary.copy("x", 4_096)

      for _ <- 1..div(ignored_bytes, byte_size(chunk)) do
        IO.binwrite(file, chunk)
      end

      IO.binwrite(file, ~s(","last":3}))
    after
      File.close(file)
    end
  end

  defp start_sampler(initial) do
    spawn_link(fn -> sample_loop(initial) end)
  end

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

  defp wait_for_quiescence(attempts \\ 2_000)

  defp wait_for_quiescence(0) do
    flunk(
      "file selection did not return to baseline: " <>
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
         snapshot.live_documents == 0 and snapshot.live_document_controls == 0 and
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

      File.write!(Path.join(directory, "file-selection-memory.json"), [
        :json.encode(report),
        "\n"
      ])
    end
  end
end
