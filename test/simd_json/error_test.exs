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
      native_failure: "native JSON operation failed"
    }

    for {reason, message} <- expected do
      error = %Error{reason: reason, message: message}
      assert error.reason == reason
      assert error.message == message
      assert error.byte_offset == nil
      assert error.native_code == nil
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
