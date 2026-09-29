defmodule SimdJson.FileInputTest do
  use ExUnit.Case, async: false

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  setup do
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()
    on_exit(fn -> wait_for_quiescence() end)
    %{baseline: baseline}
  end

  # covers: simd_json.file_input.native_path_boundary simd_json.file_input.mapped_document simd_json.file_input.open_file_contract simd_json.file_input.no_complete_source_copy simd_json.file_input.pool_and_cleanup
  @tag :tmp_dir
  test "opens a large file through one native mapping and no padded source copy", %{
    tmp_dir: tmp_dir,
    baseline: baseline
  } do
    path = Path.join(tmp_dir, "large.json")
    write_large_json_string!(path, 4 * 1024 * 1024)

    assert {:ok, %Document{} = document} = SimdJson.open_file(path)
    assert inspect(document) == "#SimdJson.Document<opaque>"
    refute inspect(document) =~ path

    mapped = BuildSmoke.execution_snapshot()
    assert mapped.live_document_mapped_inputs == baseline.live_document_mapped_inputs + 1
    assert mapped.live_document_padded_buffers == baseline.live_document_padded_buffers
    assert mapped.live_documents == baseline.live_documents + 1

    assert :ok = SimdJson.close(document)
    assert :ok = SimdJson.close(document)
    document = nil
    wait_for_quiescence()
    assert document == nil

    released = BuildSmoke.execution_snapshot()
    assert released.live_document_mapped_inputs == baseline.live_document_mapped_inputs
    assert released.live_document_padded_buffers == baseline.live_document_padded_buffers
  end

  # covers: simd_json.file_input.native_path_boundary simd_json.file_input.open_file_contract
  test "rejects invalid paths before native admission", %{baseline: baseline} do
    for invalid <- [nil, :path, 1, [], %{}, <<>>, "bad\0path"] do
      assert_raise ArgumentError,
                   "expected file path to be a non-empty binary without NUL bytes",
                   fn ->
                     SimdJson.open_file(invalid)
                   end
    end

    after_rejection = BuildSmoke.execution_snapshot()
    assert after_rejection.worker_entries == baseline.worker_entries
    assert after_rejection.live_operations == baseline.live_operations
    assert after_rejection.live_document_mapped_inputs == baseline.live_document_mapped_inputs
  end

  # covers: simd_json.file_input.open_file_contract simd_json.file_input.immutable_source simd_json.file_input.pool_and_cleanup
  @tag :tmp_dir
  test "returns stable redacted errors for missing, non-regular, empty, and malformed files", %{
    tmp_dir: tmp_dir,
    baseline: baseline
  } do
    missing = Path.join(tmp_dir, "missing-secret-name.json")
    empty = Path.join(tmp_dir, "empty-secret-name.json")
    malformed = Path.join(tmp_dir, "malformed-secret-name.json")
    File.write!(empty, "")
    File.write!(malformed, "[1,")

    cases = [
      {missing, :file_not_found, "JSON file was not found"},
      {tmp_dir, :not_regular_file, "JSON path is not a regular file"},
      {empty, :unexpected_eof, "unexpected end of JSON input"},
      {malformed, :unexpected_eof, "unexpected end of JSON input"}
    ]

    for {path, reason, message} <- cases do
      assert {:error, %Error{reason: ^reason, message: ^message} = error} =
               SimdJson.open_file(path)

      rendered = inspect(error)
      refute rendered =~ path
      refute rendered =~ Path.basename(path)
    end

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert final.live_document_mapped_inputs == baseline.live_document_mapped_inputs
    assert final.live_document_padded_buffers == baseline.live_document_padded_buffers
    assert final.live_documents == baseline.live_documents
  end

  # covers: simd_json.file_input.open_file_contract simd_json.file_input.immutable_source
  @tag :tmp_dir
  test "returns a stable unreadable-file error", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "unreadable-secret-name.json")
    File.write!(path, "null")
    File.chmod!(path, 0o000)

    try do
      assert {:error,
              %Error{
                reason: :file_unreadable,
                message: "JSON file could not be read"
              } = error} = SimdJson.open_file(path)

      refute inspect(error) =~ path
      refute inspect(error) =~ Path.basename(path)
    after
      File.chmod!(path, 0o600)
    end
  end

  # covers: simd_json.file_input.open_file_contract simd_json.file_input.pool_and_cleanup
  @tag :tmp_dir
  test "owner death closes the mapped input exactly once", %{
    tmp_dir: tmp_dir,
    baseline: baseline
  } do
    path = Path.join(tmp_dir, "owner-death.json")
    File.write!(path, ~s({"ready":true}))
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        assert {:ok, %Document{} = document} = SimdJson.open_file(path)
        send(parent, {:opened, self(), document})

        receive do
          :exit -> :ok
        end
      end)

    assert_receive {:opened, ^pid, %Document{}}, 5_000
    active = BuildSmoke.execution_snapshot()
    assert active.live_document_mapped_inputs == baseline.live_document_mapped_inputs + 1

    send(pid, :exit)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
    wait_for_quiescence()

    final = BuildSmoke.execution_snapshot()
    assert final.live_document_mapped_inputs == baseline.live_document_mapped_inputs
    assert final.live_document_padded_buffers == baseline.live_document_padded_buffers
    assert final.live_documents == baseline.live_documents
  end

  # covers: simd_json.file_input.native_path_boundary simd_json.file_input.select_file_contract simd_json.file_input.no_complete_source_copy simd_json.file_input.pool_and_cleanup
  @tag :tmp_dir
  test "selects sparse scalars from a large mapped file and closes it before return", %{
    tmp_dir: tmp_dir,
    baseline: baseline
  } do
    path = Path.join(tmp_dir, "large-selection.json")
    write_large_selection_fixture!(path, 4 * 1024 * 1024)

    assert {:ok, %{selected: selected, count: 7}} =
             SimdJson.select_file(path, selected: ["selected"], count: ["count"])

    assert selected == "copied-result"
    File.write!(path, "null")
    assert selected == "copied-result"

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert final.live_document_mapped_inputs == baseline.live_document_mapped_inputs
    assert final.live_document_padded_buffers == baseline.live_document_padded_buffers
    assert final.live_documents == baseline.live_documents
  end

  # covers: simd_json.file_input.select_file_contract simd_json.file_input.native_path_boundary
  test "validates a file projection before native file admission", %{baseline: baseline} do
    assert {:error, %Error{reason: :invalid_projection}} =
             SimdJson.select_file("missing-and-must-not-be-opened.json", [])

    after_rejection = BuildSmoke.execution_snapshot()
    assert after_rejection.worker_entries == baseline.worker_entries
    assert after_rejection.live_operations == baseline.live_operations
    assert after_rejection.live_document_mapped_inputs == baseline.live_document_mapped_inputs
  end

  # covers: simd_json.file_input.select_file_contract simd_json.file_input.immutable_source simd_json.file_input.pool_and_cleanup
  @tag :tmp_dir
  test "fails closed when a mapped document changes before selection", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "changed.json")
    File.write!(path, ~s({"selected":"before"}))
    assert {:ok, %Document{} = document} = SimdJson.open_file(path)

    File.write!(path, " ", [:append])

    assert {:error,
            %Error{
              reason: :file_changed,
              message: "JSON file changed while mapped",
              path: nil
            }} = SimdJson.select(document, selected: ["selected"])

    assert :ok = SimdJson.close(document)
  end

  defp write_large_json_string!(path, payload_bytes) do
    {:ok, file} = File.open(path, [:write, :binary])

    try do
      IO.binwrite(file, "\"")
      chunk = :binary.copy("x", 4_096)

      for _ <- 1..div(payload_bytes, byte_size(chunk)) do
        IO.binwrite(file, chunk)
      end

      IO.binwrite(file, "\"")
    after
      File.close(file)
    end
  end

  defp write_large_selection_fixture!(path, ignored_bytes) do
    {:ok, file} = File.open(path, [:write, :binary])

    try do
      IO.binwrite(file, ~s({"selected":"copied-result","count":7,"ignored":"))
      chunk = :binary.copy("x", 4_096)

      for _ <- 1..div(ignored_bytes, byte_size(chunk)) do
        IO.binwrite(file, chunk)
      end

      IO.binwrite(file, ~s("}))
    after
      File.close(file)
    end
  end

  defp wait_for_quiescence(attempts \\ 400)

  defp wait_for_quiescence(0) do
    flunk(
      "native execution did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    native = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and native.live_operations == 0 and
         native.retained_inputs == 0 and native.queued_operations == 0 and
         native.running_operations == 0 and native.live_documents == 0 and
         native.live_document_controls == 0 and native.live_document_mapped_inputs == 0 and
         native.dispatcher_queued_cleanup == 0 and native.dispatcher_active_cleanup == 0 and
         native.retained_failed_cleanup == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end
end
