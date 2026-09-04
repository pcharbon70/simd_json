defmodule SimdJson.Native.ThreadedOperation do
  @moduledoc false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator

  @test_hooks Mix.env() == :test

  if @test_hooks do
    @admission_counter_key {__MODULE__, :admission_counter}
    @on_load :initialize_admission_counter_for_test

    @doc false
    def initialize_admission_counter_for_test do
      case :persistent_term.get(@admission_counter_key, nil) do
        nil ->
          :persistent_term.put(@admission_counter_key, :counters.new(7, [:atomics]))

        counter ->
          if :counters.info(counter).size < 7 do
            :persistent_term.put(@admission_counter_key, :counters.new(7, [:atomics]))
          end
      end

      :ok
    end

    @doc false
    @spec admission_snapshot_for_test() :: %{
            total: non_neg_integer(),
            document_open: non_neg_integer(),
            document_cleanup: non_neg_integer(),
            threaded_smoke: non_neg_integer(),
            projection: non_neg_integer(),
            stream_setup: non_neg_integer(),
            stream_batch: non_neg_integer()
          }
    def admission_snapshot_for_test do
      counter = :persistent_term.get(@admission_counter_key)

      %{
        total: :counters.get(counter, 1),
        document_open: :counters.get(counter, 2),
        document_cleanup: :counters.get(counter, 3),
        threaded_smoke: :counters.get(counter, 4),
        projection: :counters.get(counter, 5),
        stream_setup: :counters.get(counter, 6),
        stream_batch: :counters.get(counter, 7)
      }
    end
  end

  @type operation :: %{
          resource: reference(),
          request_ref: reference(),
          kind:
            :document_open
            | :document_cleanup
            | :threaded_smoke
            | :projection
            | :stream_setup
            | :stream_batch,
          generation: pos_integer(),
          cursor_generation: non_neg_integer(),
          batch_sequence: non_neg_integer(),
          input_bytes: non_neg_integer()
        }

  @spec admit(binary(), operation()[:kind], pos_integer() | nil) :: operation()
  def admit(input, kind, generation \\ nil)

  def admit(input, kind, nil) when is_binary(input) and is_atom(kind) do
    admit(input, kind, BuildSmoke.execution_generation())
  end

  if @test_hooks do
    def admit(input, kind, generation)
        when is_binary(input) and is_atom(kind) and is_integer(generation) and generation > 0 do
      record_admission_for_test(kind)
      admit_native(input, kind, generation)
    end
  else
    def admit(input, kind, generation)
        when is_binary(input) and is_atom(kind) and is_integer(generation) and generation > 0 do
      admit_native(input, kind, generation)
    end
  end

  defp admit_native(input, kind, generation) do
    resource = BuildSmoke.operation_admit(input, self(), kind, generation)
    {request_ref, ^kind, ^generation, :queued} = BuildSmoke.operation_metadata(resource)

    %{
      resource: resource,
      request_ref: request_ref,
      kind: kind,
      generation: generation,
      cursor_generation: 0,
      batch_sequence: 0,
      input_bytes: byte_size(input)
    }
  end

  @spec admit_projection(
          binary() | reference(),
          term(),
          :binary | :document,
          pid(),
          pos_integer()
        ) :: {:ok, operation()} | {:error, atom()}
  def admit_projection(source, normalized, source_kind, owner, generation)
      when source_kind in [:binary, :document] and is_pid(owner) and is_integer(generation) and
             generation > 0 do
    record_projection_admission()

    case BuildSmoke.projection_operation_admit(
           source,
           normalized,
           owner,
           source_kind,
           generation
         ) do
      %{status: :ok, operation: resource} when is_reference(resource) ->
        {request_ref, :projection, ^generation, :queued} =
          BuildSmoke.operation_metadata(resource)

        {:ok,
         %{
           resource: resource,
           request_ref: request_ref,
           kind: :projection,
           generation: generation,
           cursor_generation: 0,
           batch_sequence: 0,
           input_bytes: if(source_kind == :binary, do: byte_size(source), else: 0)
         }}

      %{status: status, operation: nil} when is_atom(status) ->
        {:error, status}
    end
  end

  @spec project(:binary | :document, binary() | reference(), term(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def project(source_kind, source, normalized, options \\ [])
      when source_kind in [:binary, :document] and is_list(options) do
    OperationCoordinator.project(source_kind, source, normalized, options)
  end

  if @test_hooks do
    @doc false
    def stream_probe(kind, input, cursor_generation, batch_sequence, options \\ [])
        when kind in [:stream_setup, :stream_batch] and is_binary(input) and
               is_integer(cursor_generation) and cursor_generation > 0 and
               is_integer(batch_sequence) and batch_sequence >= 0 and is_list(options) do
      generation = BuildSmoke.execution_generation()

      operation =
        input
        |> admit(kind, generation)
        |> Map.merge(%{
          cursor_generation: cursor_generation,
          batch_sequence: batch_sequence
        })

      configure_pause(operation, options)
      OperationCoordinator.stream_probe(operation)
    end

    @doc false
    def stream_setup_fixture(document, row_limit, byte_limit)
        when is_reference(document) and is_integer(row_limit) and row_limit > 0 and
               is_integer(byte_limit) and byte_limit > 0 do
      generation = BuildSmoke.execution_generation()
      operation = admit(<<>>, :stream_setup, generation)
      OperationCoordinator.stream_setup_fixture(operation, document, row_limit, byte_limit)
    end

    def stream_binary_setup_fixture(input, row_limit, byte_limit)
        when is_binary(input) and is_integer(row_limit) and row_limit > 0 and
               is_integer(byte_limit) and byte_limit > 0 do
      generation = BuildSmoke.execution_generation()
      operation = admit(input, :stream_setup, generation)
      OperationCoordinator.stream_binary_setup_fixture(operation, row_limit, byte_limit)
    end

    @doc false
    def stream_batch_fixture(cursor, cursor_generation, sequence)
        when is_reference(cursor) and is_integer(cursor_generation) and cursor_generation > 0 and
               is_integer(sequence) and sequence >= 0 do
      generation = BuildSmoke.execution_generation()

      operation =
        <<>>
        |> admit(:stream_batch, generation)
        |> Map.merge(%{cursor_generation: cursor_generation, batch_sequence: sequence})

      OperationCoordinator.stream_batch_fixture(operation, cursor, sequence)
    end
  end

  if @test_hooks do
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

    @spec probe_document_for_test(reference()) :: map()
    def probe_document_for_test(document) when is_reference(document) do
      operation = admit(<<>>, :threaded_smoke)

      {:ok, result} =
        submit(operation, fn ->
          BuildSmoke.threaded_document_probe(operation.resource, document)
        end)

      true =
        correlated?(operation, result) and
          result.worker_context == :threaded and
          result.ready_for_delivery

      true = BuildSmoke.operation_finish(operation.resource, :delivered)
      result
    end
  end

  @spec open(binary(), keyword()) :: {:ok, reference()} | {:error, map()}
  def open(input, options \\ []) when is_binary(input) and is_list(options) do
    generation = BuildSmoke.execution_generation()

    operation =
      input
      |> admit(:document_open, generation)
      |> Map.put(:test_legacy?, Keyword.has_key?(options, :pause))

    configure_pause(operation, options)
    OperationCoordinator.open(operation)
  end

  @spec cleanup(reference()) :: :ok | {:error, map()}
  def cleanup(document) when is_reference(document) do
    generation = BuildSmoke.execution_generation()

    <<>>
    |> admit(:document_cleanup, generation)
    |> OperationCoordinator.cleanup(document)
  end

  def stream_setup(source_kind, source, projection, target, rows, bytes) do
    generation = BuildSmoke.execution_generation()

    operation =
      admit(if(source_kind == :binary, do: source, else: <<>>), :stream_setup, generation)

    OperationCoordinator.stream_setup(
      operation,
      source_kind,
      source,
      projection,
      target,
      rows,
      bytes
    )
  end

  def stream_batch(cursor, projection, cursor_generation, sequence) do
    generation = BuildSmoke.execution_generation()

    operation =
      admit(<<>>, :stream_batch, generation)
      |> Map.merge(%{cursor_generation: cursor_generation, batch_sequence: sequence})

    OperationCoordinator.stream_batch(operation, cursor, projection, sequence)
  end

  @spec submit(operation(), (-> result)) ::
          {:ok, result} | {:error, %{reason: :native_failure, stage: :threaded_submission}}
        when result: term()
  def submit(operation, submitter) when is_function(submitter, 0) do
    {:ok, submitter.()}
  rescue
    _error ->
      rollback_projection(operation)
      _ = BuildSmoke.operation_finish(operation.resource, :discarded)
      {:error, %{reason: :native_failure, stage: :threaded_submission}}
  catch
    _kind, _reason ->
      rollback_projection(operation)
      _ = BuildSmoke.operation_finish(operation.resource, :discarded)
      {:error, %{reason: :native_failure, stage: :threaded_submission}}
  end

  @spec submit_to_pool(operation(), term()) ::
          {:ok, %{request_ref: reference(), request: reference(), request_id: pos_integer()}}
          | {:error, :busy | :stopped | :native_failure}
  def submit_to_pool(operation, payload) do
    submission =
      case {operation.kind, payload} do
        {:document_open, nil} ->
          BuildSmoke.native_pool_submit_open(operation.resource)

        {:document_cleanup, document} ->
          BuildSmoke.native_pool_submit_cleanup(operation.resource, document)

        {:projection, nil} ->
          BuildSmoke.native_pool_submit_projection(operation.resource)

        {:stream_setup, {:binary, _source, projection, target, rows, bytes}} ->
          BuildSmoke.native_pool_submit_stream_binary_setup(
            operation.resource,
            projection,
            target,
            rows,
            bytes
          )

        {:stream_setup, {:document, document, projection, target, rows, bytes}} ->
          BuildSmoke.native_pool_submit_stream_document_setup(
            operation.resource,
            document,
            projection,
            target,
            rows,
            bytes
          )

        {:stream_batch, {:batch, cursor, projection, sequence}} ->
          BuildSmoke.native_pool_submit_stream_batch(
            operation.resource,
            cursor,
            projection,
            sequence
          )
      end

    {:ok, submission}
  rescue
    error in ErlangError ->
      {:error, pool_error(error.original)}

    _error ->
      {:error, :native_failure}
  catch
    _kind, _reason -> {:error, :native_failure}
  end

  @spec cancel(operation()) :: :ok
  def cancel(operation) do
    true = BuildSmoke.operation_cancel(operation.resource)
    :ok
  end

  @spec correlated?(operation(), map()) :: boolean()
  def correlated?(operation, result) do
    operation.kind == result.kind and operation.generation == result.generation and
      Map.get(result, :request_ref, operation.request_ref) == operation.request_ref and
      Map.get(result, :cursor_generation, operation.cursor_generation) ==
        operation.cursor_generation and
      Map.get(result, :batch_sequence, operation.batch_sequence) == operation.batch_sequence
  end

  if @test_hooks do
    defp record_projection_admission, do: record_admission_for_test(:projection)

    defp configure_pause(operation, options) do
      case Keyword.get(options, :pause) do
        nil ->
          :ok

        {boundary, observer} when is_atom(boundary) and is_pid(observer) ->
          true = BuildSmoke.operation_configure_pause(operation.resource, boundary, observer)
      end
    end

    defp record_admission_for_test(kind) do
      counter = :persistent_term.get(@admission_counter_key)
      :counters.add(counter, 1, 1)

      case kind do
        :document_open -> :counters.add(counter, 2, 1)
        :document_cleanup -> :counters.add(counter, 3, 1)
        :threaded_smoke -> :counters.add(counter, 4, 1)
        :projection -> :counters.add(counter, 5, 1)
        :stream_setup -> :counters.add(counter, 6, 1)
        :stream_batch -> :counters.add(counter, 7, 1)
        _other -> :ok
      end
    end
  else
    defp record_projection_admission, do: :ok
    defp configure_pause(_operation, _options), do: :ok
  end

  defp rollback_projection(%{kind: :projection, resource: resource}) do
    _ = BuildSmoke.projection_operation_rollback(resource)
    :ok
  end

  defp rollback_projection(_operation), do: :ok

  defp pool_error(reason) when reason in [:pool_busy, :resource_busy], do: :busy
  defp pool_error(reason) when reason in [:pool_stopped, :resource_closed], do: :stopped
  defp pool_error(_reason), do: :native_failure
end
