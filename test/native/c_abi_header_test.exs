defmodule SimdJson.Native.CAbiHeaderTest do
  use ExUnit.Case, async: false

  @header "native/include/simd_json_abi.h"
  @translation_unit "native/test/c_abi_header_conformance.c"

  # covers: simd_json.native_build_and_abi.opaque_c_contract simd_json.native_build_and_abi.c_abi_conformance
  @tag :tmp_dir
  test "the private ABI header compiles as strict C11 and C++17", %{tmp_dir: tmp_dir} do
    zig = Zig.Command.executable_path()

    commands = [
      ["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-x", "c"],
      ["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic", "-x", "c++"]
    ]

    for {command, index} <- Enum.with_index(commands) do
      object = Path.join(tmp_dir, "header-conformance-#{index}.o")
      args = command ++ ["-I", "native/include", "-c", @translation_unit, "-o", object]
      {output, status} = System.cmd(zig, args, stderr_to_stdout: true)

      assert status == 0, output
    end
  end

  test "the header exposes only opaque handles and fixed-width contract values" do
    header = File.read!(@header)

    assert header =~ "typedef struct simd_json_parser simd_json_parser;"
    assert header =~ "typedef struct simd_json_document simd_json_document;"
    assert header =~ "typedef struct simd_json_projection_plan simd_json_projection_plan;"
    assert header =~ "typedef struct simd_json_stream_cursor simd_json_stream_cursor;"
    assert header =~ "const uint8_t *data"
    assert header =~ "uint64_t logical_length"
    assert header =~ "uint64_t capacity"
    assert header =~ "SIMD_JSON_BYTE_OFFSET_UNAVAILABLE UINT64_MAX"
    assert header =~ "SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE UINT32_MAX"
    assert header =~ "SIMD_JSON_ARRAY_INDEX_UNAVAILABLE UINT64_MAX"

    refute header =~ "std::"
    refute header =~ "simdjson::"
    refute header =~ "size_t logical_length"
  end
end
