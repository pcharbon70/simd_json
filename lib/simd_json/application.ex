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
end
