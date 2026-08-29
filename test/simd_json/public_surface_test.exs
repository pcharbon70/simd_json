defmodule SimdJson.PublicSurfaceTest do
  use ExUnit.Case, async: true

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Projection

  @root_functions [close: 1, open: 1]
  @struct_functions [__struct__: 0, __struct__: 1]
  @forbidden_functions [
    :decode,
    :decode!,
    :select,
    :select!,
    :project,
    :project!,
    :compile_projection,
    :compile_projection!,
    :stream,
    :cursor,
    :transfer,
    :owner,
    :resource,
    :native_handle,
    :to_map,
    :to_list
  ]

  # covers: simd_json.document_api.milestone_scope simd_json.document_api.no_future_surface
  test "exports only the Milestone 1 runtime surface" do
    assert SimdJson.__info__(:functions) == @root_functions
    assert Document.__info__(:functions) == @struct_functions
    assert Error.__info__(:functions) == @struct_functions

    for module <- [SimdJson, Document, Error], {name, _arity} <- module.__info__(:functions) do
      refute name in @forbidden_functions
    end
  end

  # covers: simd_json.projection_api.milestone_scope
  test "keeps projection validation internal without a compiled-plan surface" do
    projection_functions = Projection.__info__(:functions)

    assert {:validate, 1} in projection_functions
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

  # covers: simd_json.document_api.milestone_scope simd_json.document_api.no_future_surface simd_json.native_execution.preproduction_boundary
  test "documents only the three runtime modules and hides native internals" do
    {:ok, modules} = :application.get_key(:simd_json, :modules)

    documented_runtime_modules =
      modules
      |> Enum.filter(&(Atom.to_string(&1) =~ ~r/^Elixir\.SimdJson(?:\.|$)/))
      |> Enum.filter(&documented?/1)
      |> Enum.sort()

    assert documented_runtime_modules == Enum.sort([SimdJson, Document, Error])

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

  # covers: simd_json.document_api.milestone_scope simd_json.document_api.no_future_surface
  test "publishes only the accepted specs, types, and inspection protocols" do
    assert spec_names(SimdJson) == @root_functions
    assert type_kinds(SimdJson) == []
    assert spec_names(Document) == []
    assert type_kinds(Document) == [{:t, :opaque}]
    assert spec_names(Error) == []
    assert type_kinds(Error) == [{:reason, :type}, {:t, :type}]

    {:ok, modules} = :application.get_key(:simd_json, :modules)

    protocol_modules =
      modules
      |> Enum.filter(&(Atom.to_string(&1) =~ ~r/^Elixir\.Inspect\.SimdJson\./))
      |> Enum.sort()

    assert protocol_modules ==
             Enum.sort([Inspect.SimdJson.Document, Inspect.SimdJson.Error])
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
