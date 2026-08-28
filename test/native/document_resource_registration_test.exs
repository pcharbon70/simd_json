defmodule SimdJson.Native.DocumentResourceRegistrationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke

  # covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.parent_retention
  test "registers and releases a bounded opaque document resource fixture" do
    assert BuildSmoke.document_resource_registration_smoke()

    fixture = BuildSmoke.document_resource_fixture()
    assert is_reference(fixture)
    refute is_binary(fixture)
    refute is_integer(fixture)

    fixture = nil
    :erlang.garbage_collect(self())
    assert fixture == nil
  end

  test "repeated bounded fixtures can be abandoned to garbage collection" do
    fixtures = for _ <- 1..256, do: BuildSmoke.document_resource_fixture()
    assert Enum.all?(fixtures, &is_reference/1)

    fixtures = nil
    :erlang.garbage_collect(self())
    assert fixtures == nil

    for _ <- 1..256 do
      assert BuildSmoke.document_resource_registration_smoke()
    end
  end

  test "exposes only the Phase 5 document constructor at the root" do
    assert Code.ensure_loaded?(SimdJson)
    assert function_exported?(SimdJson, :open, 1)
    assert function_exported?(SimdJson, :close, 1)
    refute function_exported?(SimdJson, :parse, 1)
    assert Code.ensure_loaded?(SimdJson.Document)
    assert Code.ensure_loaded?(SimdJson.Error)
  end
end
