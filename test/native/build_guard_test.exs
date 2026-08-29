defmodule SimdJson.Native.BuildGuardTest do
  use ExUnit.Case, async: true

  alias SimdJson.Native.BuildError
  alias SimdJson.Native.BuildGuard

  @manifest Code.eval_file("native/manifest.exs") |> elem(0)
  @primary_target @manifest |> Keyword.fetch!(:primary_target) |> Keyword.fetch!(:triple)
  @zigler Keyword.fetch!(@manifest, :zigler)
  @beam Keyword.fetch!(@manifest, :beam)
  @zig Keyword.fetch!(@manifest, :zig)
  @cxx Keyword.fetch!(@manifest, :cxx)

  # covers: simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.unsupported_target_rejection
  test "rejects an unsupported target with the documented diagnostic" do
    assert_raise BuildError,
                 "unsupported native target riscv64-linux-gnu; see " <>
                   "native/README.md#target-and-cpu-dispatch-matrix",
                 fn ->
                   BuildGuard.validate!(target: "riscv64-linux-gnu")
                 end
  end

  # covers: simd_json.native_build_and_abi.pinned_toolchain
  test "rejects drift in an ABI-relevant tool pin" do
    toolchain = valid_toolchain() |> Map.put(:zig, "0.15.0")

    assert_raise BuildError,
                 ~r/native build guard rejected Zig: expected="0\.16\.0" actual="0\.15\.0"/,
                 fn ->
                   BuildGuard.validate!(
                     manifest: @manifest,
                     target: @primary_target,
                     toolchain: toolchain
                   )
                 end
  end

  # covers: simd_json.native_build_and_abi.official_vendored_source
  @tag :tmp_dir
  test "rejects a corrupted vendor file in an isolated fixture", %{tmp_dir: tmp_dir} do
    fixture_manifest = vendor_fixture!(tmp_dir, "trusted vendor bytes")
    File.write!(Path.join(tmp_dir, "vendor/simdjson.cpp"), "corrupted vendor bytes")

    assert_raise BuildError, ~r/native vendor checksum mismatch/, fn ->
      BuildGuard.validate!(
        root: tmp_dir,
        manifest: fixture_manifest,
        target: @primary_target,
        toolchain: valid_toolchain()
      )
    end
  end

  # covers: simd_json.native_build_and_abi.official_vendored_source
  @tag :tmp_dir
  test "rejects an undeclared vendor patch in an isolated fixture", %{tmp_dir: tmp_dir} do
    fixture_manifest = vendor_fixture!(tmp_dir, "trusted vendor bytes")
    File.write!(Path.join(tmp_dir, "patches/undeclared.patch"), "not declared")

    assert_raise BuildError, ~r/undeclared or missing simdjson patch/, fn ->
      BuildGuard.validate!(
        root: tmp_dir,
        manifest: fixture_manifest,
        target: @primary_target,
        toolchain: valid_toolchain()
      )
    end
  end

  # covers: simd_json.native_build_and_abi.dependency_upgrade_gate
  @tag :tmp_dir
  test "rejects stale qualification after an isolated ABI pin change", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "tool.pin"), "zig=0.16.0\n")

    manifest =
      @manifest
      |> Keyword.put(:qualification_inputs, ["tool.pin"])

    qualification = [
      input_sha256: qualification_fingerprint(tmp_dir, ["tool.pin"]),
      supported_targets: [
        [
          triple: @primary_target,
          expected_simdjson_implementations:
            @manifest
            |> Keyword.fetch!(:primary_target)
            |> Keyword.fetch!(:expected_simdjson_implementations)
        ]
      ]
    ]

    assert :ok =
             BuildGuard.validate_qualification!(
               root: tmp_dir,
               manifest: manifest,
               qualification: qualification,
               target: @primary_target
             )

    File.write!(Path.join(tmp_dir, "tool.pin"), "zig=0.16.1\n")

    assert_raise BuildError, ~r/native qualification evidence is stale/, fn ->
      BuildGuard.validate_qualification!(
        root: tmp_dir,
        manifest: manifest,
        qualification: qualification,
        target: @primary_target
      )
    end
  end

  defp valid_toolchain do
    %{
      elixir: Keyword.fetch!(@beam, :qualified_elixir),
      otp: Keyword.fetch!(@beam, :qualified_otp),
      zigler: {Keyword.fetch!(@zigler, :version), Keyword.fetch!(@zigler, :hex_sha256)},
      zig: Keyword.fetch!(@zig, :version),
      cxx: Keyword.fetch!(@cxx, :qualified_version)
    }
  end

  defp vendor_fixture!(tmp_dir, contents) do
    File.mkdir_p!(Path.join(tmp_dir, "vendor"))
    File.mkdir_p!(Path.join(tmp_dir, "patches"))
    File.write!(Path.join(tmp_dir, "vendor/simdjson.cpp"), contents)
    File.write!(Path.join(tmp_dir, "patches/series"), "# no patches\n")

    simdjson =
      @manifest
      |> Keyword.fetch!(:simdjson)
      |> Keyword.put(:vendor_directory, "vendor")
      |> Keyword.put(:patch_series, "patches/series")
      |> Keyword.put(:vendor_files, [{"simdjson.cpp", sha256(contents)}])

    Keyword.put(@manifest, :simdjson, simdjson)
  end

  defp sha256(contents) do
    contents
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp qualification_fingerprint(root, paths) do
    paths
    |> Enum.map(fn path -> {path, File.read!(Path.join(root, path)) |> sha256()} end)
    |> :erlang.term_to_binary()
    |> sha256()
  end
end
