defmodule SimdJson.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [SimdJson.Native.OperationCoordinator]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: SimdJson.Supervisor
    )
  end

  @impl true
  def prep_stop(state) do
    if Process.whereis(SimdJson.Native.OperationCoordinator) do
      :ok = SimdJson.Native.OperationCoordinator.begin_shutdown()
      await_operation_drain()
    end

    _generation = SimdJson.Native.BuildSmoke.execution_begin_shutdown()
    state
  end

  defp await_operation_drain do
    case SimdJson.Native.OperationCoordinator.snapshot() do
      %{live_requests: 0} ->
        :ok

      _snapshot ->
        Process.sleep(5)
        await_operation_drain()
    end
  end
end
