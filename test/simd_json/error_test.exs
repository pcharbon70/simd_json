defmodule SimdJson.ErrorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  setup do
    :ok = OperationCoordinator.set_open_failure_for_test(nil)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn ->
      :ok = OperationCoordinator.set_open_failure_for_test(nil)
      :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
      wait_for_quiescence()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.document_api.structured_error simd_json.document_api.initial_error_reasons
  test "defines the complete stable reason and message contract" do
    expected = %{
      invalid_json: "invalid JSON",
      invalid_utf8: "invalid UTF-8 in JSON input",
      unexpected_eof: "unexpected end of JSON input",
      out_of_memory: "native JSON allocation failed",
      closed: "document is closed",
      not_owner: "document belongs to another process",
      invalid_projection: "invalid projection",
      no_such_field: "requested field does not exist",
      index_out_of_bounds: "requested array index is out of bounds",
      incorrect_type: "selected value has an incorrect type",
      number_out_of_range: "selected number is out of range",
      batch_too_large: "projected row exceeds max_batch_bytes",
      busy: "native execution capacity is busy",
      cursor_consumed: "document cursor has already been consumed",
      cancelled: "JSON operation was cancelled",
      native_failure: "native JSON operation failed"
    }

    for {reason, message} <- expected do
      error = %Error{reason: reason, message: message}
      assert error.reason == reason
      assert error.message == message
      assert error.byte_offset == nil
      assert error.native_code == nil
      assert error.path == nil
      assert error.array_index == nil
    end
  end

  # covers: simd_json.document_api.invalid_input_errors simd_json.document_api.logical_offsets simd_json.document_api.error_redaction
  test "malformed corpus returns stable redacted reasons and logical offsets" do
    cases = [
      {<<>>, :unexpected_eof},
      {" \n\t", :unexpected_eof},
      {"?", :invalid_json},
      {~s({"a": truX}), :invalid_json},
      {"[1,", :unexpected_eof},
      {<<34, 255, 34>>, :invalid_utf8},
      {<<34, 97, 0, 98, 34>>, :invalid_json},
      {"null null", :invalid_json}
    ]

    for {input, expected_reason} <- cases do
      assert {:error, %Error{} = error} = SimdJson.open(input)
      assert error.reason == expected_reason
      assert error.message in safe_messages()

      if error.byte_offset do
        assert error.byte_offset >= 0
        assert error.byte_offset <= byte_size(input)
      end

      if input != "" do
        refute error.message =~ input
        refute inspect(error) =~ input
        refute inspect({:error, error}) =~ input
      end
    end
  end

  # covers: simd_json.document_api.initial_error_reasons simd_json.document_api.logical_offsets simd_json.document_api.error_redaction simd_json.native_execution.no_fallback
  test "test-injected native statuses use one closed translator", %{baseline: baseline} do
    input = ~s({"translator":true})

    cases = [
      {%{status: :invalid_json, native_code: 101, byte_offset: 1}, {:invalid_json, 101, 1}},
      {%{status: :invalid_utf8, native_code: 102, byte_offset: 2}, {:invalid_utf8, 102, 2}},
      {%{status: :unexpected_eof, native_code: 103, byte_offset: byte_size(input)},
       {:unexpected_eof, 103, byte_size(input)}},
      {%{status: :out_of_memory, native_code: nil, byte_offset: nil}, {:out_of_memory, nil, nil}},
      {%{status: :invalid_argument, native_code: 104, byte_offset: nil},
       {:native_failure, 104, nil}},
      {%{status: :internal_failure, native_code: 2_147_483_000, byte_offset: 999_999},
       {:native_failure, 2_147_483_000, nil}},
      {%{status: :execution_unavailable, native_code: nil, byte_offset: nil},
       {:native_failure, nil, nil}},
      {%{status: :cancelled, native_code: nil, byte_offset: nil}, {:native_failure, nil, nil}}
    ]

    for {injected, {reason, native_code, byte_offset}} <- cases do
      assert :ok = OperationCoordinator.set_open_failure_for_test(injected)

      assert {:error,
              %Error{
                reason: ^reason,
                native_code: ^native_code,
                byte_offset: ^byte_offset
              }} = SimdJson.open(input)
    end

    :ok = OperationCoordinator.set_open_failure_for_test(nil)
    wait_for_quiescence()
    snapshot = BuildSmoke.execution_snapshot()
    assert snapshot.live_documents == baseline.live_documents
    assert snapshot.live_document_controls == baseline.live_document_controls
  end

  # covers: simd_json.document_api.redacted_failure simd_json.document_api.error_redaction simd_json.native_execution.threaded_submission_failure
  test "input and caught submission exception text stay out of errors and logs" do
    secret = "phase5-secret-7f95122d"
    injected_exception = "injected Zigler threaded submission rejection"
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, true)

    assert {:error, %Error{reason: :native_failure} = error} =
             SimdJson.open(~s("#{secret}"))

    rendered = inspect(error)

    log =
      capture_log(fn ->
        require Logger
        Logger.error("simd_json open failed: #{rendered}")
      end)

    for output <- [error.message, rendered, inspect({:error, error}), log] do
      refute output =~ secret
      refute output =~ injected_exception
      refute output =~ "0x"
    end
  end

  # covers: simd_json.document_api.error_redaction
  test "error inspection omits even a forged sensitive message" do
    secret = "phase5-forged-message-secret"

    error = %Error{
      reason: :native_failure,
      byte_offset: 12,
      native_code: 42,
      message: secret
    }

    assert inspect(error) ==
             "#SimdJson.Error<reason: :native_failure, byte_offset: 12, native_code: 42>"

    refute inspect(error) =~ secret
  end

  # covers: simd_json.projection_api.projection_error_reasons simd_json.projection_api.error_path
  test "projection path metadata preserves caller terms but inspection redacts its contents" do
    secret = "caller-path-secret-4892"
    path = [secret, "", 0, 18_446_744_073_709_551_615]

    error = %Error{
      reason: :no_such_field,
      path: path,
      message: "requested field does not exist"
    }

    assert error.path === path

    assert inspect(error) ==
             "#SimdJson.Error<reason: :no_such_field, byte_offset: nil, native_code: nil, " <>
               "path: <caller-supplied>>"

    refute inspect(error) =~ secret
  end

  # covers: simd_json.streaming_api.indexed_errors simd_json.streaming_api.runtime_exceptions
  test "stream row indexes use a controlled message and bounded redacted inspection" do
    secret = "indexed-path-secret-9382"

    error = %Error{
      reason: :batch_too_large,
      path: [secret],
      array_index: 18_446_744_073_709_551_615,
      message: "projected row exceeds max_batch_bytes"
    }

    assert error.array_index == 18_446_744_073_709_551_615
    assert error.path == [secret]
    assert error.message == "projected row exceeds max_batch_bytes"

    assert inspect(error) ==
             "#SimdJson.Error<reason: :batch_too_large, byte_offset: nil, native_code: nil, " <>
               "array_index: 18446744073709551615, path: <caller-supplied>>"

    refute inspect(error) =~ secret
  end

  # covers: simd_json.document_api.error_redaction simd_json.projection_api.error_path
  test "inspection stays bounded and redacted for forged fields" do
    secret = "forged-path-and-exception-secret-7741"

    error = %Error{
      reason: self(),
      byte_offset: secret,
      native_code: self(),
      path: List.duplicate(secret, 100_000),
      array_index: {self(), secret, 18_446_744_073_709_551_616},
      message: "C++ exception at 0x7ffee123: #{secret}"
    }

    rendered = inspect(error)

    assert rendered ==
             "#SimdJson.Error<reason: :native_failure, byte_offset: nil, native_code: nil, " <>
               "path: <caller-supplied>>"

    assert byte_size(rendered) < 160
    refute rendered =~ secret
    refute rendered =~ inspect(self())
    refute rendered =~ "0x"
    refute rendered =~ "C++"
  end

  defp safe_messages do
    [
      "invalid JSON",
      "invalid UTF-8 in JSON input",
      "unexpected end of JSON input",
      "native JSON allocation failed",
      "document is closed",
      "document belongs to another process",
      "native JSON operation failed"
    ]
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
         native.live_document_controls == 0 and native.dispatcher_queued_cleanup == 0 and
         native.dispatcher_active_cleanup == 0 and native.retained_failed_cleanup == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end
end
