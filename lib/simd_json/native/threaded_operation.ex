defmodule SimdJson.Native.ThreadedOperation do
  @moduledoc false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  @type operation :: %{
          resource: reference(),
          request_ref: reference(),
          kind: :document_open | :document_cleanup | :threaded_smoke,
          generation: pos_integer()
        }

  @spec admit(binary(), operation()[:kind], pos_integer()) :: operation()
  def admit(input, kind, generation \\ 1)
      when is_binary(input) and is_atom(kind) and is_integer(generation) and generation > 0 do
    resource = BuildSmoke.operation_admit(input, self(), kind, generation)
    {request_ref, ^kind, ^generation, :queued} = BuildSmoke.operation_metadata(resource)

    %{
      resource: resource,
      request_ref: request_ref,
      kind: kind,
      generation: generation
    }
  end

  @spec smoke(binary()) :: map()
  def smoke(input) when is_binary(input) do
    operation = admit(input, :threaded_smoke)
    true = BuildSmoke.operation_owner_matches(operation.resource)

    {:ok, result} =
      submit(operation, fn -> BuildSmoke.threaded_context_smoke(operation.resource) end)

    true =
      correlated?(operation, result) and
        result.context == :threaded and
        result.owner_matches and
        result.ready_for_delivery

    true = BuildSmoke.operation_owner_matches(operation.resource)
    true = BuildSmoke.operation_finish(operation.resource, :delivered)
    result
  end

  @spec open(binary(), keyword()) :: {:ok, reference()} | {:error, map()}
  def open(input, options \\ []) when is_binary(input) and is_list(options) do
    generation = BuildSmoke.execution_generation()
    operation = admit(input, :document_open, generation)

    case Keyword.get(options, :pause) do
      nil ->
        :ok

      {boundary, observer} when is_atom(boundary) and is_pid(observer) ->
        true = BuildSmoke.operation_configure_pause(operation.resource, boundary, observer)
    end

    OperationCoordinator.open(operation)
  end

  @spec cleanup(reference()) :: :ok | {:error, map()}
  def cleanup(document) when is_reference(document) do
    generation = BuildSmoke.execution_generation()

    <<>>
    |> admit(:document_cleanup, generation)
    |> OperationCoordinator.cleanup(document)
  end

  @spec submit(operation(), (-> result)) ::
          {:ok, result} | {:error, %{reason: :native_failure, stage: :threaded_submission}}
        when result: term()
  def submit(operation, submitter) when is_function(submitter, 0) do
    {:ok, submitter.()}
  rescue
    _error ->
      _ = BuildSmoke.operation_finish(operation.resource, :discarded)
      {:error, %{reason: :native_failure, stage: :threaded_submission}}
  catch
    _kind, _reason ->
      _ = BuildSmoke.operation_finish(operation.resource, :discarded)
      {:error, %{reason: :native_failure, stage: :threaded_submission}}
  end

  @spec cancel(operation()) :: :ok
  def cancel(operation) do
    true = BuildSmoke.operation_cancel(operation.resource)
    :ok
  end

  @spec correlated?(operation(), map()) :: boolean()
  def correlated?(operation, result) do
    operation.kind == result.kind and operation.generation == result.generation
  end
end
