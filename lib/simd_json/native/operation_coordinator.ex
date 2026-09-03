defmodule SimdJson.Native.OperationCoordinator do
  @moduledoc false

  use GenServer

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.PoolOptions
  alias SimdJson.Native.ThreadedOperation

  @completion_tag {__MODULE__, :threaded_completion}
  @test_hooks Mix.env() == :test

  defstruct accepting?: true,
            pool_options: nil,
            requests: %{},
            caller_monitors: %{},
            worker_monitors: %{},
            closing_documents: MapSet.new(),
            rejected_submissions: MapSet.new(),
            open_failure_for_test: nil

  @type request :: %{
          kind: :document_open | :document_cleanup | :projection,
          operation: ThreadedOperation.operation(),
          from: GenServer.from() | nil,
          caller: pid() | nil,
          caller_monitor: reference() | nil,
          worker: pid(),
          worker_monitor: reference(),
          document_target: reference() | nil,
          diagnostics?: boolean(),
          orphaned?: boolean()
        }

  def start_link(%PoolOptions{} = pool_options) do
    GenServer.start_link(__MODULE__, pool_options, name: __MODULE__)
  end

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      type: :worker,
      restart: :permanent,
      shutdown: :infinity
    }
  end

  @spec open(ThreadedOperation.operation()) ::
          {:ok, reference()} | {:error, map()}
  def open(operation) do
    GenServer.call(__MODULE__, {:submit, :document_open, operation, nil}, :infinity)
  end

  @spec cleanup(ThreadedOperation.operation(), reference()) :: :ok | {:error, map()}
  def cleanup(operation, document) do
    GenServer.call(
      __MODULE__,
      {:submit, :document_cleanup, operation, document},
      :infinity
    )
  end

  @spec project(:binary | :document, binary() | reference(), term(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def project(source_kind, source, normalized, options)
      when source_kind in [:binary, :document] and is_list(options) do
    GenServer.call(
      __MODULE__,
      {:project, source_kind, source, normalized, options},
      :infinity
    )
  end

  def stream_setup(operation, source_kind, source, projection, target, rows, bytes) do
    GenServer.call(
      __MODULE__,
      {:stream_public, operation, {source_kind, source, projection, target, rows, bytes}},
      :infinity
    )
  end

  def stream_batch(operation, cursor, projection, sequence) do
    GenServer.call(
      __MODULE__,
      {:stream_public, operation, {:batch, cursor, projection, sequence}},
      :infinity
    )
  end

  if @test_hooks do
    @doc false
    def stream_probe(operation) do
      GenServer.call(__MODULE__, {:stream_probe, operation}, :infinity)
    end

    def stream_setup_fixture(operation, document, row_limit, byte_limit) do
      GenServer.call(
        __MODULE__,
        {:stream_fixture, operation, {:setup, document, row_limit, byte_limit}},
        :infinity
      )
    end

    def stream_binary_setup_fixture(operation, row_limit, byte_limit) do
      GenServer.call(
        __MODULE__,
        {:stream_fixture, operation, {:binary_setup, row_limit, byte_limit}},
        :infinity
      )
    end

    def stream_batch_fixture(operation, cursor, sequence) do
      GenServer.call(
        __MODULE__,
        {:stream_fixture, operation, {:batch, cursor, sequence}},
        :infinity
      )
    end
  end

  @spec snapshot() :: %{accepting?: boolean(), live_requests: non_neg_integer()}
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec pool_snapshot() :: map()
  def pool_snapshot do
    GenServer.call(__MODULE__, :pool_snapshot)
  end

  @spec begin_shutdown() :: :ok
  def begin_shutdown do
    GenServer.call(__MODULE__, :begin_shutdown, :infinity)
  end

  if @test_hooks do
    @spec release_pause(reference()) :: :ok | {:error, :unknown_request}
    def release_pause(request_ref) when is_reference(request_ref) do
      GenServer.call(__MODULE__, {:release_pause, request_ref})
    end

    @spec set_submission_rejection_for_test(
            :document_open | :document_cleanup | :projection | :stream_setup | :stream_batch,
            boolean()
          ) :: :ok
    def set_submission_rejection_for_test(kind, reject?)
        when kind in [
               :document_open,
               :document_cleanup,
               :projection,
               :stream_setup,
               :stream_batch
             ] and
               is_boolean(reject?) do
      GenServer.call(__MODULE__, {:set_submission_rejection_for_test, kind, reject?})
    end

    @spec set_open_failure_for_test(nil | map()) :: :ok | {:error, :invalid_failure}
    def set_open_failure_for_test(failure) when is_nil(failure) or is_map(failure) do
      GenServer.call(__MODULE__, {:set_open_failure_for_test, failure})
    end
  end

  @impl true
  def init(%PoolOptions{} = pool_options) do
    _generation = BuildSmoke.execution_resume()
    {:ok, %__MODULE__{pool_options: pool_options}}
  end

  @impl true
  def handle_call({:stream_public, operation, payload}, from, state) do
    {:noreply, start_request(state, operation.kind, operation, payload, from, elem(from, 0))}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, %{accepting?: state.accepting?, live_requests: map_size(state.requests)}, state}
  end

  def handle_call(:pool_snapshot, _from, state) do
    {:reply, PoolOptions.snapshot(state.pool_options), state}
  end

  def handle_call(:begin_shutdown, _from, state) do
    Enum.each(state.requests, fn {_request_ref, request} ->
      if request.kind in [:document_open, :projection] do
        _ = BuildSmoke.operation_cancel(request.operation.resource)
      end
    end)

    {:reply, :ok, %{state | accepting?: false}}
  end

  if @test_hooks do
    def handle_call({:set_submission_rejection_for_test, kind, reject?}, _from, state) do
      rejected_submissions =
        if reject? do
          MapSet.put(state.rejected_submissions, kind)
        else
          MapSet.delete(state.rejected_submissions, kind)
        end

      {:reply, :ok, %{state | rejected_submissions: rejected_submissions}}
    end

    def handle_call({:set_open_failure_for_test, failure}, _from, state) do
      allowed = [
        :cancelled,
        :execution_unavailable,
        :invalid_json,
        :invalid_utf8,
        :unexpected_eof,
        :out_of_memory,
        :invalid_argument,
        :internal_failure
      ]

      if is_nil(failure) or Map.get(failure, :status) in allowed do
        {:reply, :ok, %{state | open_failure_for_test: failure}}
      else
        {:reply, {:error, :invalid_failure}, state}
      end
    end
  end

  if @test_hooks do
    def handle_call({:release_pause, request_ref}, _from, state) do
      case Map.fetch(state.requests, request_ref) do
        {:ok, request} ->
          true = BuildSmoke.operation_release_pause(request.operation.resource)
          {:reply, :ok, state}

        :error ->
          {:reply, {:error, :unknown_request}, state}
      end
    end
  end

  def handle_call({:project, source_kind, source, normalized, options}, from, state) do
    caller = elem(from, 0)

    if state.accepting? do
      generation = BuildSmoke.execution_generation()

      case ThreadedOperation.admit_projection(
             source,
             normalized,
             source_kind,
             caller,
             generation
           ) do
        {:ok, operation} ->
          configure_pause(operation, options)
          configure_failure_injection(operation, options)
          reject_submission? = submission_rejected?(state, :projection)
          document_target = if source_kind == :document, do: source
          diagnostics? = Keyword.get(options, :diagnostics, false) == true

          {:noreply,
           start_request(
             state,
             :projection,
             operation,
             nil,
             from,
             caller,
             reject_submission?,
             nil,
             document_target,
             diagnostics?
           )}

        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, state}
      end
    else
      {:reply, native_error(:admission_rejected), state}
    end
  rescue
    _error -> {:reply, native_error(:admission_rejected), state}
  catch
    _kind, _reason -> {:reply, native_error(:admission_rejected), state}
  end

  if @test_hooks do
    def handle_call({:stream_probe, operation}, from, state) do
      caller = elem(from, 0)
      kind = operation.kind

      with true <- state.accepting?,
           true <- kind in [:stream_setup, :stream_batch],
           true <- BuildSmoke.operation_owner_is(operation.resource, caller),
           true <- operation.generation == BuildSmoke.execution_generation(),
           false <- Map.has_key?(state.requests, operation.request_ref) do
        {:noreply,
         start_request(
           state,
           kind,
           operation,
           nil,
           from,
           caller,
           submission_rejected?(state, kind)
         )}
      else
        _ ->
          _ = BuildSmoke.operation_finish(operation.resource, :discarded)
          {:reply, native_error(:admission_rejected), state}
      end
    end

    def handle_call({:stream_fixture, operation, payload}, from, state) do
      caller = elem(from, 0)
      kind = operation.kind

      with true <- state.accepting?,
           true <- kind in [:stream_setup, :stream_batch],
           true <- BuildSmoke.operation_owner_is(operation.resource, caller),
           true <- operation.generation == BuildSmoke.execution_generation(),
           false <- Map.has_key?(state.requests, operation.request_ref) do
        {:noreply,
         start_request(
           state,
           kind,
           operation,
           payload,
           from,
           caller,
           submission_rejected?(state, kind)
         )}
      else
        _ ->
          _ = BuildSmoke.operation_finish(operation.resource, :discarded)
          {:reply, native_error(:admission_rejected), state}
      end
    end
  end

  def handle_call({:submit, :document_cleanup, operation, document}, from, state) do
    caller = elem(from, 0)

    with true <- state.accepting?,
         :document_cleanup <- operation.kind,
         true <- BuildSmoke.operation_owner_is(operation.resource, caller),
         true <- operation.generation == BuildSmoke.execution_generation(),
         false <- Map.has_key?(state.requests, operation.request_ref) do
      reject_submission? = submission_rejected?(state, :document_cleanup)

      if reject_submission? do
        # The deterministic rejection seam proves no generated worker can own
        # cleanup, so preserve the original open lifecycle for a safe retry.
        {:noreply,
         start_request(
           state,
           :document_cleanup,
           operation,
           document,
           from,
           caller,
           true,
           nil,
           document
         )}
      else
        case BuildSmoke.document_prepare_cleanup(document) do
          owner_state when owner_state in [:closing, :closed] ->
            state =
              state
              |> cancel_document_projections(document)
              |> Map.update!(:closing_documents, &MapSet.put(&1, document))

            {:noreply,
             start_request(
               state,
               :document_cleanup,
               operation,
               document,
               from,
               caller,
               false,
               nil,
               document
             )}

          _other ->
            _ = BuildSmoke.operation_finish(operation.resource, :discarded)
            {:reply, native_error(:admission_rejected), state}
        end
      end
    else
      _ ->
        _ = BuildSmoke.operation_finish(operation.resource, :discarded)
        {:reply, native_error(:admission_rejected), state}
    end
  end

  def handle_call({:submit, kind, operation, payload}, from, state) do
    caller = elem(from, 0)

    with true <- state.accepting?,
         ^kind <- operation.kind,
         true <- BuildSmoke.operation_owner_is(operation.resource, caller),
         true <- operation.generation == BuildSmoke.execution_generation(),
         false <- Map.has_key?(state.requests, operation.request_ref) do
      reject_submission? = submission_rejected?(state, kind)
      open_failure_for_test = if kind == :document_open, do: state.open_failure_for_test

      {:noreply,
       start_request(
         state,
         kind,
         operation,
         payload,
         from,
         caller,
         reject_submission?,
         open_failure_for_test,
         nil
       )}
    else
      _ ->
        _ = BuildSmoke.operation_finish(operation.resource, :discarded)
        {:reply, native_error(:admission_rejected), state}
    end
  end

  @impl true
  def handle_info(
        {@completion_tag, kind, request_ref, generation, cursor_generation, batch_sequence,
         worker, result},
        state
      ) do
    case Map.fetch(state.requests, request_ref) do
      {:ok,
       %{
         kind: ^kind,
         operation: %{
           generation: ^generation,
           cursor_generation: ^cursor_generation,
           batch_sequence: ^batch_sequence
         },
         worker: ^worker
       } = request} ->
        state = remove_worker_monitor(state, request)
        complete_request(state, request_ref, request, result)

      _ ->
        # Unknown, duplicate, forged, or stale completions cannot select a
        # waiter. Any resource term in the discarded message is reclaimed by
        # its own GC teardown path.
        {:noreply, state}
    end
  end

  # Legacy-shaped, forged, or otherwise incomplete completions carry no
  # cursor generation and batch sequence, so they cannot select any request.
  def handle_info({@completion_tag, _kind, _request_ref, _generation, _worker, _result}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    cond do
      request_ref = state.caller_monitors[monitor] ->
        request = Map.fetch!(state.requests, request_ref)

        if request.kind in [:document_open, :projection, :stream_setup, :stream_batch] do
          _ = BuildSmoke.operation_cancel(request.operation.resource)
        end

        request = %{request | orphaned?: true, caller: nil, caller_monitor: nil, from: nil}

        {:noreply,
         %{
           state
           | requests: Map.put(state.requests, request_ref, request),
             caller_monitors: Map.delete(state.caller_monitors, monitor)
         }}

      request_ref = state.worker_monitors[monitor] ->
        # A normal worker sends completion before it exits, so reaching this
        # branch means no correlated completion was produced.
        request = Map.fetch!(state.requests, request_ref)
        release_projection_reservation(request.operation)
        _ = BuildSmoke.operation_finish(request.operation.resource, :discarded)
        maybe_reply(request, native_error(:worker_terminated))
        {:noreply, remove_request(state, request_ref, request)}

      true ->
        {:noreply, state}
    end
  end

  defp start_request(
         state,
         kind,
         operation,
         payload,
         from,
         caller,
         reject_submission? \\ false,
         open_failure_for_test \\ nil,
         document_target \\ nil,
         diagnostics? \\ false
       ) do
    coordinator = self()
    caller_monitor = Process.monitor(caller)

    {worker, worker_monitor} =
      spawn_monitor(fn ->
        result =
          ThreadedOperation.submit(operation, fn ->
            reject_submission_for_test!(reject_submission?)

            execute_operation(kind, operation, payload, open_failure_for_test)
          end)

        send(
          coordinator,
          {@completion_tag, kind, operation.request_ref, operation.generation,
           operation.cursor_generation, operation.batch_sequence, self(), result}
        )
      end)

    request = %{
      kind: kind,
      operation: operation,
      from: from,
      caller: caller,
      caller_monitor: caller_monitor,
      worker: worker,
      worker_monitor: worker_monitor,
      document_target: document_target,
      diagnostics?: diagnostics?,
      orphaned?: false
    }

    %{
      state
      | requests: Map.put(state.requests, operation.request_ref, request),
        caller_monitors: Map.put(state.caller_monitors, caller_monitor, operation.request_ref),
        worker_monitors: Map.put(state.worker_monitors, worker_monitor, operation.request_ref)
    }
  end

  if @test_hooks do
    defp submission_rejected?(state, kind) do
      MapSet.member?(state.rejected_submissions, kind)
    end

    defp reject_submission_for_test!(true) do
      raise "injected Zigler threaded submission rejection"
    end

    defp reject_submission_for_test!(false), do: :ok

    defp execute_operation(:document_open, operation, _payload, failure)
         when is_map(failure) do
      smoke = BuildSmoke.threaded_context_smoke(operation.resource)

      %{
        status: Map.fetch!(failure, :status),
        kind: operation.kind,
        generation: operation.generation,
        worker_context: smoke.context,
        native_code: Map.get(failure, :native_code),
        byte_offset: Map.get(failure, :byte_offset),
        document: nil
      }
    end
  else
    defp submission_rejected?(_state, _kind), do: false
    defp reject_submission_for_test!(_reject?), do: :ok
  end

  defp execute_operation(:document_open, operation, _payload, nil) do
    BuildSmoke.threaded_document_open(operation.resource)
  end

  defp execute_operation(:document_cleanup, operation, payload, nil) do
    BuildSmoke.threaded_document_cleanup(operation.resource, payload)
  end

  defp execute_operation(:projection, operation, _payload, nil) do
    BuildSmoke.threaded_projection_execute(operation.resource)
  end

  defp execute_operation(
         :stream_setup,
         operation,
         {:binary, _source, projection, target, rows, bytes},
         nil
       ),
       do:
         BuildSmoke.threaded_stream_binary_setup_fixture(
           operation.resource,
           projection,
           target,
           rows,
           bytes
         )

  defp execute_operation(
         :stream_setup,
         operation,
         {:document, document, projection, target, rows, bytes},
         nil
       ),
       do:
         BuildSmoke.threaded_stream_setup_fixture(
           operation.resource,
           document,
           projection,
           target,
           rows,
           bytes
         )

  defp execute_operation(:stream_batch, operation, {:batch, cursor, projection, sequence}, nil),
    do: BuildSmoke.threaded_stream_batch_fixture(operation.resource, cursor, projection, sequence)

  if @test_hooks do
    defp execute_operation(kind, operation, nil, nil)
         when kind in [:stream_setup, :stream_batch] do
      BuildSmoke.threaded_context_smoke(operation.resource)
    end

    defp execute_operation(:stream_setup, operation, {:setup, document, rows, bytes}, nil) do
      BuildSmoke.threaded_stream_setup_fixture(
        operation.resource,
        document,
        default_stream_projection(),
        [],
        rows,
        bytes
      )
    end

    defp execute_operation(:stream_setup, operation, {:binary_setup, rows, bytes}, nil) do
      BuildSmoke.threaded_stream_binary_setup_fixture(
        operation.resource,
        default_stream_projection(),
        [],
        rows,
        bytes
      )
    end

    defp execute_operation(:stream_batch, operation, {:batch, cursor, sequence}, nil) do
      BuildSmoke.threaded_stream_batch_fixture(
        operation.resource,
        cursor,
        default_stream_projection(),
        sequence
      )
    end
  end

  defp default_stream_projection,
    do: {:simd_json_projection_v1, [{0, :value, 0}], [{0, ["value"]}]}

  defp complete_request(state, request_ref, request, {:ok, native_result}) do
    correlated? =
      native_result.kind == request.kind and
        native_result.generation == request.operation.generation and
        Map.get(native_result, :context, Map.get(native_result, :worker_context)) == :threaded and
        ThreadedOperation.correlated?(request.operation, native_result)

    cond do
      not correlated? ->
        release_projection_reservation(request.operation)
        _ = BuildSmoke.operation_finish(request.operation.resource, :discarded)
        maybe_reply(request, native_error(:completion_mismatch))
        {:noreply, remove_request(state, request_ref, request)}

      request.orphaned? ->
        release_projection_reservation(request.operation)
        _ = BuildSmoke.operation_finish(request.operation.resource, :discarded)
        state = maybe_cleanup_orphan(state, native_result)
        {:noreply, remove_request(state, request_ref, request)}

      true ->
        response = normalize_result(native_result, request.diagnostics?)
        maybe_reply(request, response)
        release_projection_reservation(request.operation)
        _ = BuildSmoke.operation_finish(request.operation.resource, :delivered)
        {:noreply, remove_request(state, request_ref, request)}
    end
  end

  defp complete_request(state, request_ref, request, {:error, error}) do
    release_projection_reservation(request.operation)
    maybe_reply(request, {:error, error})
    {:noreply, remove_request(state, request_ref, request)}
  end

  defp normalize_result(%{kind: :document_open, status: :ok, document: document}, _diagnostics?) do
    {:ok, document}
  end

  defp normalize_result(%{kind: :document_open} = result, _diagnostics?) do
    {:error,
     %{
       reason: result.status,
       native_code: result.native_code,
       byte_offset: result.byte_offset
     }}
  end

  defp normalize_result(%{kind: :document_cleanup, status: :closed}, _diagnostics?), do: :ok

  defp normalize_result(%{kind: :document_cleanup, status: status}, _diagnostics?) do
    native_error(status)
  end

  defp normalize_result(%{kind: :projection, status: :ok, result: result} = native, true)
       when is_map(result) do
    {:ok, %{result: result, diagnostics: projection_diagnostics(native)}}
  end

  defp normalize_result(%{kind: :projection, status: :ok, result: result}, false)
       when is_map(result),
       do: {:ok, result}

  defp normalize_result(%{kind: :projection} = result, diagnostics?) do
    error = %{
      reason: result.status,
      native_code: result.native_code,
      byte_offset: result.byte_offset,
      output_slot: result.output_slot
    }

    error =
      if diagnostics? do
        Map.put(error, :diagnostics, projection_diagnostics(result))
      else
        error
      end

    {:error, error}
  end

  defp normalize_result(%{kind: kind, context: :threaded} = result, _diagnostics?)
       when kind in [:stream_setup, :stream_batch] do
    {:ok,
     Map.merge(result, %{
       cursor_generation: 0,
       batch_sequence: 0
     })}
  end

  defp normalize_result(%{kind: kind, status: :ok, worker_context: :threaded} = result, _)
       when kind in [:stream_setup, :stream_batch],
       do: {:ok, result}

  defp normalize_result(%{kind: kind, status: status} = result, _)
       when kind in [:stream_setup, :stream_batch],
       do:
         {:error,
          %{
            reason: status,
            sequence: Map.get(result, :sequence),
            native_code: Map.get(result, :native_code),
            byte_offset: Map.get(result, :byte_offset),
            output_slot: Map.get(result, :output_slot),
            array_index: Map.get(result, :array_index)
          }}

  defp maybe_cleanup_orphan(state, %{kind: :document_open, document: document})
       when is_reference(document) do
    operation =
      ThreadedOperation.admit(
        <<>>,
        :document_cleanup,
        BuildSmoke.execution_generation()
      )

    start_request(state, :document_cleanup, operation, document, nil, self())
  end

  defp maybe_cleanup_orphan(state, _result), do: state

  defp maybe_reply(%{from: nil}, _response), do: :ok
  defp maybe_reply(%{from: from}, response), do: GenServer.reply(from, response)

  defp native_error(stage), do: {:error, %{reason: :native_failure, stage: stage}}

  defp remove_worker_monitor(state, request) do
    Process.demonitor(request.worker_monitor, [:flush])
    %{state | worker_monitors: Map.delete(state.worker_monitors, request.worker_monitor)}
  end

  defp remove_request(state, request_ref, request) do
    if request.caller_monitor do
      Process.demonitor(request.caller_monitor, [:flush])
    end

    state = %{
      state
      | requests: Map.delete(state.requests, request_ref),
        caller_monitors: Map.delete(state.caller_monitors, request.caller_monitor),
        worker_monitors: Map.delete(state.worker_monitors, request.worker_monitor)
    }

    if request.kind == :document_cleanup and request.document_target do
      %{
        state
        | closing_documents: MapSet.delete(state.closing_documents, request.document_target)
      }
    else
      state
    end
  end

  if @test_hooks do
    defp configure_pause(operation, options) do
      case Keyword.get(options, :pause) do
        nil ->
          :ok

        {boundary, observer} when is_atom(boundary) and is_pid(observer) ->
          true = BuildSmoke.operation_configure_pause(operation.resource, boundary, observer)
      end
    end

    defp configure_failure_injection(operation, options) do
      case Keyword.get(options, :failure_after) do
        nil ->
          :ok

        successful_checkpoints
        when is_integer(successful_checkpoints) and successful_checkpoints >= 0 ->
          true =
            BuildSmoke.projection_operation_inject_failure(
              operation.resource,
              successful_checkpoints
            )
      end
    end
  else
    defp configure_pause(_operation, _options), do: :ok
    defp configure_failure_injection(_operation, _options), do: :ok
  end

  defp projection_diagnostics(result) do
    %{
      worker_context: result.worker_context,
      compilation_nanoseconds: result.compilation_nanoseconds,
      traversal_nanoseconds: result.traversal_nanoseconds,
      term_construction_nanoseconds: result.term_construction_nanoseconds,
      boundary_count: result.boundary_count
    }
  end

  defp cancel_document_projections(state, document) do
    Enum.each(state.requests, fn {_request_ref, request} ->
      if request.kind == :projection and request.document_target == document do
        _ = BuildSmoke.operation_cancel(request.operation.resource)
      end
    end)

    state
  end

  defp release_projection_reservation(%{kind: :projection, resource: resource}) do
    _ = BuildSmoke.projection_operation_release(resource)
    :ok
  end

  defp release_projection_reservation(_operation), do: :ok
end
