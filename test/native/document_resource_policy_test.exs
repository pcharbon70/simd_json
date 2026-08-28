defmodule SimdJson.Native.DocumentResourcePolicyTest do
  use ExUnit.Case, async: true

  alias SimdJson.Native.BuildSmoke

  @resource_source File.read!("native/zig/document_resource.zig")
  @nif_source File.read!("native/zig/build_smoke.zig")

  # covers: simd_json.document_resource.zero_copy_disabled simd_json.document_resource.padded_owned_copy simd_json.document_resource.input_lifetime simd_json.native_execution.bounded_nif_entry simd_json.document_api.milestone_scope
  test "has one owned parser-input path and no production parse NIF" do
    assert length(Regex.scan(~r/c\.simd_json_document_open\(/, @resource_source)) == 1
    assert @resource_source =~ "owned.ptr"
    assert @resource_source =~ "@memcpy(owned[0..source.len], source)"
    assert @resource_source =~ "@memset(owned[source.len..capacity], 0)"

    exports = BuildSmoke.__info__(:functions)

    for forbidden <- [:open, :parse, :decode, :close, :cursor, :project] do
      refute Enum.any?(exports, fn {name, _arity} -> name == forbidden end)
    end
  end

  # covers: simd_json.document_resource.deferred_large_cleanup simd_json.document_resource.lifecycle simd_json.native_execution.bounded_nif_entry simd_json.native_execution.threaded_cleanup
  test "ordinary resource callbacks only detach bounded lifecycle state" do
    [destructor] =
      Regex.run(
        ~r/pub fn dtor\(payload: \*DocumentResourcePayload\) void \{(?<body>.*?)\n    \}/s,
        @nif_source,
        capture: :all_names
      )

    assert destructor =~ "detachForDeferredCleanup"

    for forbidden <- [
          "openOwned",
          "simd_json_document_open",
          "simd_json_document_destroy",
          "simd_json_parser_destroy",
          "allocator.free",
          "@memcpy",
          "while"
        ] do
      refute destructor =~ forbidden
    end
  end

  # covers: simd_json.document_resource.test_accounting simd_json.native_build_and_abi.symbol_visibility simd_json.package.native_build_tooling
  test "test accounting has no BEAM NIF entrypoint" do
    exports = BuildSmoke.__info__(:functions)

    for forbidden <- [
          :resource_accounting,
          :resource_snapshot,
          :wait_for_quiescence,
          :inject_resource_failure
        ] do
      refute Enum.any?(exports, fn {name, _arity} -> name == forbidden end)
    end
  end
end
