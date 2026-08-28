defmodule SimdJson.Native.OperationCoordinator do
  @moduledoc false

  use GenServer

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.ThreadedOperation

  @completion_tag {__MODULE__, :threaded_completion}

  defstruct accepting?: true,
            requests: %{},
            caller_monitors: %{},
            worker_monitors: %{}

  @type request :: %{
          kind: :document_open | :document_cleanup,
          operation: ThreadedOperation.operation(),
          from: GenServer.from() | nil,
          caller: pid() | nil,
          caller_monitor: reference() | nil,
          worker: pid(),
          worker_monitor: reference(),
          orphaned?: boolean()
        }

  def start_link(_options) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
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

  @spec snapshot() :: %{accepting?: boolean(), live_requests: non_neg_integer()}
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec release_pause(reference()) :: :ok | {:error, :unknown_request}
  def release_pause(request_ref) when is_reference(request_ref) do
    GenServer.call(__MODULE__, {:release_pause, request_ref})
  end

  @spec begin_shutdown() :: :ok
  def begin_shutdown do
    GenServer.call(__MODULE__, :begin_shutdown, :infinity)
  end

  @impl true
  def init(:ok) do
    _generation = BuildSmoke.execution_resume()
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, %{accepting?: state.accepting?, live_requests: map_size(state.requests)}, state}
  end

  def handle_call(:begin_shutdown, _from, state) do
    Enum.each(state.requests, fn {_request_ref, request} ->
      if request.kind == :document_open do
        _ = BuildSmoke.operation_cancel(request.operation.resource)
      end
    end)

    {:reply, :ok, %{state | accepting?: false}}
  end

  def handle_call({:release_pause, request_ref}, _from, state) do
    case Map.fetch(state.requests, request_ref) do
      {:ok, request} ->
        true = BuildSmoke.operation_release_pause(request.operation.resource)
        {:reply, :ok, state}

      :error ->
        {:reply, {:error, :unknown_request}, state}
    end
  end

  def handle_call({:submit, kind, operation, payload}, from, state) do
    caller = elem(from, 0)

    with true <- state.accepting?,
         ^kind <- operation.kind,
         true <- BuildSmoke.operation_owner_is(operation.resource, caller),
         true <- operation.generation == BuildSmoke.execution_generation(),
         false <- Map.has_key?(state.requests, operation.request_ref) do
      {:noreply, start_request(state, kind, operation, payload, from, caller)}
    else
      _ ->
        _ = BuildSmoke.operation_finish(operation.resource, :discarded)
        {:reply, native_error(:admission_rejected), state}
    end
  end

  @impl true
  def handle_info(
        {@completion_tag, kind, request_ref, generation, worker, result},
        state
      ) do
    case Map.fetch(state.requests, request_ref) do
      {:ok,
       %{
         kind: ^kind,
         operation: %{generation: ^generation},
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

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    cond do
      request_ref = state.caller_monitors[monitor] ->
        request = Map.fetch!(state.requests, request_ref)

        if request.kind == :document_open do
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
        _ = BuildSmoke.operation_finish(request.operation.resource, :discarded)
        maybe_reply(request, native_error(:worker_terminated))
        {:noreply, remove_request(state, request_ref, request)}

      true ->
        {:noreply, state}
    end
  end

  defp start_request(state, kind, operation, payload, from, caller) do
    coordinator = self()
    caller_monitor = Process.monitor(caller)

    {worker, worker_monitor} =
      spawn_monitor(fn ->
        result =
          ThreadedOperation.submit(operation, fn ->
            case kind do
              :document_open ->
                BuildSmoke.threaded_document_open(operation.resource)

              :document_cleanup ->
                BuildSmoke.threaded_document_cleanup(operation.resource, payload)
            end
          end)

        send(
          coordinator,
          {@completion_tag, kind, operation.request_ref, operation.generation, self(), result}
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
      orphaned?: false
    }

    %{
      state
      | requests: Map.put(state.requests, operation.request_ref, request),
        caller_monitors: Map.put(state.caller_monitors, caller_monitor, operation.request_ref),
        worker_monitors: Map.put(state.worker_monitors, worker_monitor, operation.request_ref)
    }
  end

  defp complete_request(state, request_ref, request, {:ok, native_result}) do
    correlated? =
      native_result.kind == request.kind and
        native_result.generation == request.operation.generation and
        native_result.worker_context == :threaded

    cond do
      not correlated? ->
        _ = BuildSmoke.operation_finish(request.operation.resource, :discarded)
        maybe_reply(request, native_error(:completion_mismatch))
        {:noreply, remove_request(state, request_ref, request)}

      request.orphaned? ->
        _ = BuildSmoke.operation_finish(request.operation.resource, :discarded)
        state = maybe_cleanup_orphan(state, native_result)
        {:noreply, remove_request(state, request_ref, request)}

      true ->
        response = normalize_result(native_result)
        maybe_reply(request, response)
        _ = BuildSmoke.operation_finish(request.operation.resource, :delivered)
        {:noreply, remove_request(state, request_ref, request)}
    end
  end

  defp complete_request(state, request_ref, request, {:error, error}) do
    maybe_reply(request, {:error, error})
    {:noreply, remove_request(state, request_ref, request)}
  end

  defp normalize_result(%{kind: :document_open, status: :ok, document: document}) do
    {:ok, document}
  end

  defp normalize_result(%{kind: :document_open} = result) do
    {:error,
     %{
       reason: result.status,
       native_code: result.native_code,
       byte_offset: result.byte_offset
     }}
  end

  defp normalize_result(%{kind: :document_cleanup, status: :closed}), do: :ok

  defp normalize_result(%{kind: :document_cleanup, status: status}) do
    native_error(status)
  end

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

    %{
      state
      | requests: Map.delete(state.requests, request_ref),
        caller_monitors: Map.delete(state.caller_monitors, request.caller_monitor),
        worker_monitors: Map.delete(state.worker_monitors, request.worker_monitor)
    }
  end
end
