defmodule SimdJson.Phase5IntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  @idle_gauges [
    :live_operations,
    :retained_inputs,
    :queued_operations,
    :queued_cleanup,
    :running_operations,
    :live_documents,
    :live_document_controls,
    :dispatcher_queued_cleanup,
    :dispatcher_active_cleanup,
    :retained_failed_cleanup
  ]

  setup do
    :ok = OperationCoordinator.set_open_failure_for_test(nil)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn ->
      :ok = OperationCoordinator.set_open_failure_for_test(nil)
      :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
      :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
      wait_for_quiescence()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.document_api.open_and_close simd_json.document_api.all_top_level_values simd_json.document_api.valid_json_values simd_json.native_execution.threaded_parse
  test "public open and close accepts every JSON top-level type with whitespace", %{
    baseline: baseline
  } do
    values = [
      ~s({"object":{"nested":true}}),
      ~s([1,"two",null]),
      ~s("string"),
      "-9223372036854775808",
      "1.25e2",
      "true",
      "false",
      "null"
    ]

    for json <- values do
      assert {:ok, %Document{} = document} = SimdJson.open(" \n\t" <> json <> "\r ")
      assert inspect(document) == "#SimdJson.Document<opaque>"
      assert :ok = SimdJson.close(document)
    end

    wait_for_quiescence()
    assert_idle_gauges(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.document_api.invalid_input_errors simd_json.document_api.initial_error_reasons simd_json.document_api.logical_offsets
  test "public malformed corpus returns stable errors and no partial document", %{
    baseline: baseline
  } do
    cases = [
      {<<>>, :unexpected_eof},
      {" \n\t", :unexpected_eof},
      {"?", :invalid_json},
      {~s({"middle": truX}), :invalid_json},
      {~s({"end": 1}x), :unexpected_eof},
      {"[1,", :unexpected_eof},
      {<<34, 255, 34>>, :invalid_utf8},
      {<<34, 97, 0, 98, 34>>, :invalid_json}
    ]

    for {input, reason} <- cases do
      assert {:error, %Error{reason: ^reason} = error} = SimdJson.open(input)

      if error.byte_offset != nil do
        assert error.byte_offset in 0..byte_size(input)
      end
    end

    wait_for_quiescence()
    assert_idle_gauges(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.document_api.structured_error simd_json.document_api.initial_error_reasons simd_json.native_execution.no_fallback
  test "allocation and unknown native failures never publish a document", %{baseline: baseline} do
    assert :ok =
             OperationCoordinator.set_open_failure_for_test(%{
               status: :out_of_memory,
               native_code: nil,
               byte_offset: nil
             })

    assert {:error, %Error{reason: :out_of_memory}} = SimdJson.open(~s({"safe":true}))

    assert :ok =
             OperationCoordinator.set_open_failure_for_test(%{
               status: :internal_failure,
               native_code: 2_147_483_000,
               byte_offset: 100_000
             })

    assert {:error,
            %Error{
              reason: :native_failure,
              native_code: 2_147_483_000,
              byte_offset: nil
            }} = SimdJson.open("null")

    :ok = OperationCoordinator.set_open_failure_for_test(nil)
    wait_for_quiescence()
    assert_idle_gauges(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.document_api.non_binary_argument simd_json.document_api.invalid_document_argument simd_json.native_execution.bounded_nif_entry
  test "all invalid argument families stop before threaded admission", %{baseline: baseline} do
    invalid_open = [
      nil,
      :null,
      0,
      1.0,
      [],
      ["null"],
      %{},
      {},
      make_ref(),
      self(),
      fn -> :ok end,
      <<1::1>>
    ]

    for value <- invalid_open do
      assert_raise ArgumentError, "expected JSON input to be a binary", fn ->
        SimdJson.open(value)
      end
    end

    invalid_close = [
      nil,
      :document,
      0,
      1.0,
      "document",
      [],
      %{},
      {},
      make_ref(),
      self(),
      fn -> :ok end,
      %Document{__resource__: make_ref()}
    ]

    for value <- invalid_close do
      assert_raise ArgumentError, "expected a SimdJson.Document", fn ->
        SimdJson.close(value)
      end
    end

    assert BuildSmoke.execution_snapshot() == baseline

    other_resource = ThreadedOperation.admit(<<>>, :threaded_smoke)
    before_other_resource = BuildSmoke.execution_snapshot()

    assert_raise ArgumentError, "expected a SimdJson.Document", fn ->
      SimdJson.close(%Document{__resource__: other_resource.resource})
    end

    after_other_resource = BuildSmoke.execution_snapshot()
    assert after_other_resource.worker_entries == before_other_resource.worker_entries
    assert after_other_resource.running_operations == before_other_resource.running_operations
    assert BuildSmoke.operation_finish(other_resource.resource, :discarded)

    other_resource = nil
    wait_for_quiescence()
    assert other_resource == nil
    assert_idle_gauges(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.document_api.redacted_failure simd_json.document_api.error_redaction simd_json.native_execution.threaded_submission_failure
  test "malformed input and caught exception secrets remain redacted" do
    input_secret = "phase5-input-secret-3a4acfa4"
    exception_secret = "injected Zigler threaded submission rejection"

    assert {:error, %Error{} = malformed} =
             SimdJson.open(~s({"#{input_secret}": truX}))

    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, true)
    assert {:error, %Error{} = rejected} = SimdJson.open(~s("#{input_secret}"))

    log =
      capture_log(fn ->
        require Logger
        Logger.error("simd_json errors: #{inspect([malformed, rejected])}")
      end)

    for output <- [
          malformed.message,
          rejected.message,
          inspect(malformed),
          inspect(rejected),
          log
        ] do
      refute output =~ input_secret
      refute output =~ exception_secret
      refute output =~ "0x"
    end
  end

  # covers: simd_json.document_resource.input_lifetime simd_json.document_resource.padded_owned_copy simd_json.native_execution.threaded_parse simd_json.native_execution.retained_resources
  test "native document survives collection of its original BEAM binary", %{baseline: baseline} do
    document = open_ephemeral_document()
    %Document{__resource__: resource} = document

    wait_for_operations_to_release()
    force_garbage_collection()

    assert %{
             status: :ok,
             worker_context: :threaded,
             uses_owned_input: true,
             valid: true
           } = ThreadedOperation.probe_document_for_test(resource)

    assert :ok = SimdJson.close(document)
    document = resource = nil
    wait_for_quiescence()
    assert document == nil and resource == nil
    assert_idle_gauges(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.document_api.close_and_non_owner simd_json.document_resource.single_owner simd_json.document_resource.non_owner_rejection
  test "non-owner sees not_owner for both open and closed document terms" do
    assert {:ok, %Document{} = document} = SimdJson.open("null")
    %Document{__resource__: resource} = document
    generation = BuildSmoke.execution_generation()
    before_open_rejection = BuildSmoke.execution_snapshot()

    assert {:error, %Error{reason: :not_owner}} =
             Task.async(fn -> SimdJson.close(document) end) |> Task.await()

    assert BuildSmoke.document_lifecycle(resource) == :open
    assert BuildSmoke.execution_generation() == generation
    assert BuildSmoke.execution_snapshot().worker_entries == before_open_rejection.worker_entries

    assert :ok = SimdJson.close(document)
    before_closed_rejection = BuildSmoke.execution_snapshot()

    assert {:error, %Error{reason: :not_owner}} =
             Task.async(fn -> SimdJson.close(document) end) |> Task.await()

    assert BuildSmoke.document_lifecycle(resource) == :closed
    assert BuildSmoke.execution_generation() == generation

    assert BuildSmoke.execution_snapshot().worker_entries ==
             before_closed_rejection.worker_entries

    document = resource = nil
    wait_for_quiescence()
    assert document == nil and resource == nil
  end

  # covers: simd_json.document_resource.idempotent_close simd_json.document_resource.repeated_close simd_json.document_resource.native_memory_baseline simd_json.native_execution.threaded_cleanup
  test "queued owner closes and later resource destruction clean exactly once", %{
    baseline: baseline
  } do
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        {:ok, document} = SimdJson.open(~s({"close":"race"}))
        send(parent, {:owner_ready, self(), document})
        close_server(document, parent)
      end)

    assert_receive {:owner_ready, ^owner, %Document{} = document}, 5_000

    # A single owner PID is serial by definition. Queue every close before the
    # first reply so this is the maximum contention visible at the public API.
    requests =
      for _ <- 1..12 do
        request = make_ref()
        send(owner, {:close, request})
        request
      end

    for request <- requests do
      assert_receive {:close_result, ^request, :ok}, 5_000
    end

    after_closes = BuildSmoke.execution_snapshot()

    assert after_closes.completed_document_cleanup ==
             baseline.completed_document_cleanup + 1

    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 5_000

    assert inspect(document) == "#SimdJson.Document<opaque>"
    document = nil
    wait_for_quiescence()
    assert document == nil

    after_destruction = BuildSmoke.execution_snapshot()

    assert after_destruction.completed_document_cleanup ==
             baseline.completed_document_cleanup + 1

    assert_idle_gauges(after_destruction, baseline)
  end

  # covers: simd_json.document_resource.single_owner simd_json.document_resource.non_owner_rejection simd_json.document_resource.native_memory_baseline simd_json.native_execution.request_correlation
  test "concurrent owners keep documents, errors, probes, and cleanup independent", %{
    baseline: baseline
  } do
    parent = self()

    owners =
      for index <- 1..8 do
        spawn_monitor(fn ->
          input = ~s({"owner":#{index},"nested":[true,null,"#{index}"]})
          {:ok, document} = SimdJson.open(input)
          send(parent, {:independent_open, self(), index, document})
          document_server(document, parent)
        end)
      end

    documents =
      for {{owner, monitor}, index} <- Enum.zip(owners, 1..8) do
        assert_receive {:independent_open, ^owner, ^index, %Document{} = document}, 5_000
        {owner, monitor, document}
      end

    resources = Enum.map(documents, fn {_owner, _monitor, %Document{__resource__: r}} -> r end)
    assert MapSet.size(MapSet.new(resources)) == length(resources)

    error_tasks =
      for index <- 1..4 do
        Task.async(fn -> SimdJson.open("[#{index},") end)
      end

    for task <- error_tasks do
      assert {:error, %Error{reason: :unexpected_eof}} = Task.await(task)
    end

    for {owner, _monitor, document} <- documents do
      assert {:error, %Error{reason: :not_owner}} = SimdJson.close(document)
      request = make_ref()
      send(owner, {:probe, request})
      assert_receive {:probe_result, ^request, %{status: :ok, valid: true}}, 5_000
    end

    for {owner, _monitor, _document} <- documents do
      request = make_ref()
      send(owner, {:close, request})
      assert_receive {:document_close_result, ^request, :ok}, 5_000
      send(owner, :stop)
    end

    for {owner, monitor, _document} <- documents do
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 5_000
    end

    documents = resources = nil
    wait_for_quiescence()
    assert documents == nil and resources == nil
    assert_idle_gauges(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.document_resource.native_memory_baseline simd_json.document_resource.test_accounting simd_json.native_execution.threaded_cleanup
  test "explicit-close and garbage-collected batches return native gauges to baseline", %{
    baseline: baseline
  } do
    explicit_count = 16

    documents =
      for index <- 1..explicit_count do
        {:ok, document} = SimdJson.open(~s({"explicit":#{index}}))
        document
      end

    Enum.each(documents, fn document -> assert :ok = SimdJson.close(document) end)
    documents = nil
    force_garbage_collection()
    assert documents == nil

    parent = self()
    gc_count = 16

    {gc_owner, gc_monitor} =
      spawn_monitor(fn ->
        abandoned =
          for index <- 1..gc_count do
            {:ok, document} = SimdJson.open(~s({"garbage_collected":#{index}}))
            document
          end

        send(parent, {:gc_batch_ready, self(), length(abandoned)})
      end)

    assert_receive {:gc_batch_ready, ^gc_owner, ^gc_count}, 5_000
    assert_receive {:DOWN, ^gc_monitor, :process, ^gc_owner, :normal}, 5_000
    wait_for_quiescence()

    snapshot = BuildSmoke.execution_snapshot()
    assert_idle_gauges(snapshot, baseline)

    assert snapshot.completed_document_cleanup ==
             baseline.completed_document_cleanup + explicit_count + gc_count
  end

  defp open_ephemeral_document do
    unique = System.unique_integer([:positive, :monotonic])

    input =
      IO.iodata_to_binary([
        ~s({"ephemeral":"),
        Integer.to_string(unique),
        ~s(","payload":[1,2,3,{"valid":true}]})
      ])

    {:ok, document} = SimdJson.open(input)
    document
  end

  defp close_server(document, parent) do
    receive do
      {:close, request} ->
        send(parent, {:close_result, request, SimdJson.close(document)})
        close_server(document, parent)

      :stop ->
        :ok
    end
  end

  defp document_server(document, parent) do
    receive do
      {:probe, request} ->
        %Document{__resource__: resource} = document

        send(
          parent,
          {:probe_result, request, ThreadedOperation.probe_document_for_test(resource)}
        )

        document_server(document, parent)

      {:close, request} ->
        send(parent, {:document_close_result, request, SimdJson.close(document)})
        document_server(document, parent)

      :stop ->
        :ok
    end
  end

  defp assert_idle_gauges(snapshot, baseline) do
    for field <- @idle_gauges do
      assert Map.fetch!(snapshot, field) == Map.fetch!(baseline, field),
             "#{field} did not return to baseline: " <>
               "#{inspect(Map.fetch!(snapshot, field))} != #{inspect(Map.fetch!(baseline, field))}"
    end
  end

  defp force_garbage_collection do
    for _ <- 1..3 do
      :erlang.garbage_collect(self())
      :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    end
  end

  defp wait_for_operations_to_release(attempts \\ 400)

  defp wait_for_operations_to_release(0) do
    flunk("operation input was not released: #{inspect(BuildSmoke.execution_snapshot())}")
  end

  defp wait_for_operations_to_release(attempts) do
    force_garbage_collection()
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and snapshot.live_operations == 0 and
         snapshot.retained_inputs == 0 and snapshot.queued_operations == 0 and
         snapshot.running_operations == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_operations_to_release(attempts - 1)
    end
  end

  defp wait_for_quiescence(attempts \\ 800)

  defp wait_for_quiescence(0) do
    flunk(
      "native execution did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_quiescence(attempts) do
    force_garbage_collection()
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
