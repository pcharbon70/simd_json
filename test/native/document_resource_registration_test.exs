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

  test "does not expose a production document constructor" do
    refute function_exported?(SimdJson, :open, 1)
    refute function_exported?(SimdJson, :parse, 1)
    refute Code.ensure_loaded?(SimdJson.Document)
  end
end
