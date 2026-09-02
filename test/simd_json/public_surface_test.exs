defmodule SimdJson.PublicSurfaceTest do
  use ExUnit.Case, async: true

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Projection
  alias SimdJson.StreamOptions
  alias SimdJson.Stream

  @root_functions [close: 1, open: 1, select: 2, stream: 2]
  @struct_functions [__struct__: 0, __struct__: 1]
  @forbidden_functions [
    :decode,
    :decode!,
    :select!,
    :project,
    :project!,
    :compile_projection,
    :compile_projection!,
    :stream_batches,
    :cursor,
    :transfer,
    :owner,
    :resource,
    :native_handle,
    :to_map,
    :to_list
  ]
  @root_types [
    {:array_index, :type},
    {:object_segment, :type},
    {:output_key, :type},
    {:path, :type},
    {:path_segment, :type},
    {:projection, :type},
    {:projection_entry, :type},
    {:projection_result, :type},
    {:scalar_result, :type},
    {:stream_fields, :type},
    {:stream_option, :type},
    {:stream_row, :type},
    {:stream_target_path, :type},
    {:stream_target_segment, :type}
  ]

  # covers: simd_json.document_api.milestone_scope simd_json.document_api.no_future_surface simd_json.projection_api.select_contract simd_json.projection_api.milestone_scope simd_json.projection_api.atom_and_surface_safety
  test "exports the accepted document, projection, and streaming operations" do
    assert SimdJson.__info__(:functions) == @root_functions
    assert Document.__info__(:functions) == @struct_functions
    assert Error.__info__(:functions) == @struct_functions ++ [exception: 1, message: 1]

    for module <- [SimdJson, Document, Error, Stream],
        {name, _arity} <- module.__info__(:functions) do
      refute name in @forbidden_functions
    end
  end

  # covers: simd_json.projection_api.milestone_scope
  test "keeps projection validation internal without a compiled-plan surface" do
    projection_functions = Projection.__info__(:functions)

    assert {:validate, 1} in projection_functions
    assert {:validate_target_path, 1} in projection_functions
    assert {:path_for_output_slot, 2} in projection_functions
    assert {:preflight_for_test, 2} in projection_functions
    assert {:snapshot_for_test, 1} in projection_functions

    for function <- [
          :__struct__,
          :compile,
          :compile_projection,
          :deserialize,
          :new,
          :resource,
          :serialize
        ] do
      refute Enum.any?(projection_functions, fn {name, _arity} -> name == function end)
    end

    refute documented?(Projection)
    refute Code.ensure_loaded?(SimdJson.CompiledProjection)
  end

  # covers: simd_json.streaming_api.milestone_scope simd_json.streaming_api.lazy_construction simd_json.streaming_api.opaque_stream
  test "publishes only the opaque stream shell over internal preflight" do
    stream_option_functions = StreamOptions.__info__(:functions)

    assert stream_option_functions == [
             inspect_metadata: 1,
             new: 2,
             runtime: 1,
             snapshot_for_test: 1
           ]

    refute documented?(StreamOptions)
    assert {:stream, 2} in SimdJson.__info__(:functions)
    assert Code.ensure_loaded?(Stream)
    assert Stream.__info__(:functions) == [__struct__: 0, __struct__: 1, new: 1, options: 1]
    refute Code.ensure_loaded?(SimdJson.Cursor)

    for function <- [
          :__struct__,
          :cursor,
          :deserialize,
          :next,
          :resource,
          :serialize,
          :stream,
          :stream_batches
        ] do
      refute Enum.any?(stream_option_functions, fn {name, _arity} -> name == function end)
    end
  end

  # covers: simd_json.document_api.milestone_scope simd_json.document_api.no_future_surface simd_json.native_execution.preproduction_boundary simd_json.projection_api.milestone_scope
  test "documents only the three runtime modules and hides native internals" do
    {:ok, modules} = :application.get_key(:simd_json, :modules)

    documented_runtime_modules =
      modules
      |> Enum.filter(&(Atom.to_string(&1) =~ ~r/^Elixir\.SimdJson(?:\.|$)/))
      |> Enum.filter(&documented?/1)
      |> Enum.sort()

    assert documented_runtime_modules == Enum.sort([SimdJson, Document, Error, Stream])

    for module <- modules, Atom.to_string(module) =~ ~r/^Elixir\.SimdJson\.Native\./ do
      refute documented?(module)
    end

    for text <- [
          module_doc(SimdJson),
          File.read!("README.md"),
          File.read!("docs/milestones/01-native-foundation.md")
        ] do
      assert text =~ "Milestone 4"
      assert text =~ "bounded worker pool"
    end
  end

  # covers: simd_json.document_api.milestone_scope simd_json.document_api.no_future_surface simd_json.projection_api.select_contract simd_json.projection_api.milestone_scope simd_json.projection_api.atom_and_surface_safety
  test "publishes only the accepted specs, types, and inspection protocols" do
    assert spec_names(SimdJson) == @root_functions
    assert type_kinds(SimdJson) == @root_types
    assert spec_names(Document) == []
    assert type_kinds(Document) == [{:t, :opaque}]
    assert spec_names(Error) == []
    assert type_kinds(Error) == [{:reason, :type}, {:t, :type}]
    assert type_kinds(Stream) == [{:t, :opaque}]

    {:ok, modules} = :application.get_key(:simd_json, :modules)

    protocol_modules =
      modules
      |> Enum.filter(&(Atom.to_string(&1) =~ ~r/^Elixir\.Inspect\.SimdJson\./))
      |> Enum.sort()

    assert protocol_modules ==
             Enum.sort([
               Inspect.SimdJson.Document,
               Inspect.SimdJson.Error,
               Inspect.SimdJson.Stream
             ])
  end

  # covers: simd_json.projection_api.milestone_scope simd_json.projection_api.error_path simd_json.projection_api.atom_and_surface_safety
  test "public terms reveal no normalized plan, cursor, diagnostic, or unselected source data" do
    secret = "unselected-public-surface-secret-9041"

    assert {:ok, %{value: 1} = result} =
             SimdJson.select(~s({"value":1,"private":"#{secret}"}), value: ["value"])

    assert {:error, %Error{} = error} =
             SimdJson.select(~s({"value":1,"private":"#{secret}"}), missing: ["missing"])

    for rendered <- [inspect(result), inspect(error)] do
      refute rendered =~ secret
      refute rendered =~ "simd_json_projection_v1"
      refute rendered =~ "path_slot"
      refute rendered =~ "generation"
      refute rendered =~ "nanoseconds"
      refute rendered =~ "native plan"
    end

    for module <- [SimdJson, Document, Error, Stream] do
      functions = module.__info__(:functions)

      for forbidden <- @forbidden_functions do
        refute Enum.any?(functions, fn {name, _arity} -> name == forbidden end)
      end
    end

    refute Code.ensure_loaded?(SimdJson.CompiledProjection)
    refute Code.ensure_loaded?(SimdJson.Cursor)
    assert Code.ensure_loaded?(Stream)
  end

  # covers: simd_json.package.documentation_layout simd_json.projection_api.select_contract simd_json.projection_api.fresh_string_results simd_json.projection_api.milestone_scope simd_json.projection_execution.preproduction_boundary
  test "publishes the projection contract and limits in README, module, milestone, and ExDoc" do
    docs = Mix.Project.config() |> Keyword.fetch!(:docs)
    extras = Keyword.fetch!(docs, :extras)
    assert "docs/milestones/02-projection-api.md" in extras

    readme = File.read!("README.md")
    milestone = File.read!("docs/milestones/02-projection-api.md")
    root_doc = module_doc(SimdJson)

    for text <- [readme, milestone, root_doc] do
      assert text =~ "SimdJson.select"
      assert text =~ "scalar"
      assert text =~ "Milestone 4"
    end

    assert readme =~ "first occurrence"
    assert readme =~ "fresh result binary"
    assert readme =~ "no transparent rewind"
    assert milestone =~ "No compiled projection is public"
    assert milestone =~ "does not rewind"
    assert root_doc =~ "no bang variant"
    assert root_doc =~ "public compiled plan"
  end

  defp documented?(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{} = module_doc, _, _} -> map_size(module_doc) > 0
      _ -> false
    end
  end

  defp module_doc(module) do
    {:docs_v1, _, _, _, %{"en" => module_doc}, _, _} = Code.fetch_docs(module)
    module_doc
  end

  defp spec_names(module) do
    {:ok, specs} = Code.Typespec.fetch_specs(module)

    specs
    |> Enum.map(fn {{name, arity}, _definitions} -> {name, arity} end)
    |> Enum.sort()
  end

  defp type_kinds(module) do
    {:ok, types} = Code.Typespec.fetch_types(module)

    types
    |> Enum.map(fn {kind, {name, _definition, _arguments}} -> {name, kind} end)
    |> Enum.sort()
  end
end
