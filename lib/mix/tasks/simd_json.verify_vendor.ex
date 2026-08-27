defmodule Mix.Tasks.SimdJson.VerifyVendor do
  use Mix.Task

  @shortdoc "Verifies the vendored simdjson snapshot and optional source archive"

  @moduledoc """
  Verifies every recorded vendored simdjson digest and the declared patch
  series without accessing the network.

      mix simd_json.verify_vendor
      mix simd_json.verify_vendor --archive /path/to/singleheader.zip

  When an archive is supplied, the task checks its digest, extracts it into a
  temporary directory, applies the declared patch series in order, and compares
  the reconstructed source files byte-for-byte with the checked-in snapshot.
  """

  # covers: simd_json.native_build_and_abi.official_vendored_source simd_json.native_build_and_abi.dependency_upgrade_gate simd_json.package.native_source_distribution
  @switches [archive: :string]

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if positional != [] or invalid != [] do
      Mix.raise("usage: mix simd_json.verify_vendor [--archive PATH]")
    end

    root = project_root()
    manifest = read_manifest!(root)
    simdjson = Keyword.fetch!(manifest, :simdjson)

    verify_vendor_files!(root, simdjson)
    patches = verify_patch_series!(root, simdjson)
    verify_recorded_contract!(root, simdjson)

    if archive = options[:archive] do
      verify_archive!(root, simdjson, patches, archive)
    end

    Mix.shell().info("simdjson vendor verification passed")
  end

  defp project_root do
    Mix.Project.project_file()
    |> Path.dirname()
    |> Path.expand()
  end

  defp read_manifest!(root) do
    path = Path.join(root, "native/manifest.exs")
    {manifest, _bindings} = Code.eval_file(path)

    unless is_list(manifest) do
      Mix.raise("native manifest must evaluate to a keyword list: #{path}")
    end

    manifest
  end

  defp verify_vendor_files!(root, simdjson) do
    vendor_directory = Keyword.fetch!(simdjson, :vendor_directory)

    simdjson
    |> Keyword.fetch!(:vendor_files)
    |> Enum.each(fn {relative_path, expected_sha256} ->
      path = Path.join([root, vendor_directory, relative_path])
      verify_digest!(path, expected_sha256, "vendored file")
    end)
  end

  defp verify_patch_series!(root, simdjson) do
    series_path = Path.join(root, Keyword.fetch!(simdjson, :patch_series))
    patch_directory = Path.dirname(series_path)

    patches =
      series_path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reject(fn {line, _line_number} ->
        trimmed = String.trim(line)
        trimmed == "" or String.starts_with?(trimmed, "#")
      end)
      |> Enum.map(fn {line, line_number} ->
        parse_patch_entry!(line, line_number, series_path)
      end)

    declared_names = MapSet.new(patches, &elem(&1, 1))

    actual_names =
      patch_directory
      |> Path.join("*.patch")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> MapSet.new()

    if declared_names != actual_names do
      Mix.raise(
        "patch manifest drift in #{series_path}: declared=#{inspect(Enum.sort(declared_names))} " <>
          "present=#{inspect(Enum.sort(actual_names))}"
      )
    end

    Enum.each(patches, fn {expected_sha256, filename} ->
      verify_digest!(Path.join(patch_directory, filename), expected_sha256, "declared patch")
    end)

    patches
  end

  defp parse_patch_entry!(line, line_number, series_path) do
    case String.split(String.trim(line), ~r/\s+/, parts: 2) do
      [sha256, filename] ->
        unless Regex.match?(~r/^[0-9a-f]{64}$/, sha256) do
          Mix.raise("invalid SHA-256 at #{series_path}:#{line_number}")
        end

        unless Path.basename(filename) == filename and String.ends_with?(filename, ".patch") do
          Mix.raise("invalid patch filename at #{series_path}:#{line_number}")
        end

        {sha256, filename}

      _other ->
        Mix.raise("invalid patch entry at #{series_path}:#{line_number}")
    end
  end

  defp verify_recorded_contract!(root, simdjson) do
    header =
      Path.join([root, Keyword.fetch!(simdjson, :vendor_directory), "simdjson.h"])
      |> File.read!()

    version = Keyword.fetch!(simdjson, :version)
    padding = Keyword.fetch!(simdjson, :padding_bytes)

    unless String.contains?(header, ~s(#define SIMDJSON_VERSION "#{version}")) do
      Mix.raise("vendored simdjson version does not match native/manifest.exs")
    end

    unless String.contains?(header, "constexpr size_t SIMDJSON_PADDING = #{padding};") do
      Mix.raise("vendored SIMDJSON_PADDING does not match native/manifest.exs")
    end

    unless Keyword.fetch!(simdjson, :language_standard) == "c++17" do
      Mix.raise("the qualified simdjson language standard must be c++17")
    end
  end

  defp verify_archive!(root, simdjson, patches, archive) do
    archive = Path.expand(archive)
    verify_digest!(archive, Keyword.fetch!(simdjson, :archive_sha256), "source archive")

    extraction_directory =
      Path.join(
        System.tmp_dir!(),
        "simd_json-vendor-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(extraction_directory)

    try do
      extract_archive!(archive, extraction_directory, Keyword.fetch!(simdjson, :archive_members))
      apply_patches!(root, simdjson, extraction_directory, patches)
      compare_reconstructed_source!(root, simdjson, extraction_directory)
    after
      File.rm_rf!(extraction_directory)
    end
  end

  defp extract_archive!(archive, destination, expected_members) do
    case :zip.extract(String.to_charlist(archive), [:memory]) do
      {:ok, entries} ->
        members = Enum.map(entries, fn {name, _bytes} -> List.to_string(name) end)

        unless Enum.sort(members) == Enum.sort(expected_members) do
          Mix.raise(
            "source archive members differ: expected=#{inspect(Enum.sort(expected_members))} " <>
              "actual=#{inspect(Enum.sort(members))}"
          )
        end

        Enum.each(entries, fn {name, bytes} ->
          filename = List.to_string(name)

          unless Path.basename(filename) == filename do
            Mix.raise("source archive contains an unsafe path: #{filename}")
          end

          File.write!(Path.join(destination, filename), bytes)
        end)

      {:error, reason} ->
        Mix.raise("cannot extract source archive #{archive}: #{inspect(reason)}")
    end
  end

  defp apply_patches!(_root, _simdjson, _destination, []), do: :ok

  defp apply_patches!(root, simdjson, destination, patches) do
    patch_executable =
      System.find_executable("patch") ||
        Mix.raise("the `patch` executable is required to verify a non-empty patch series")

    patch_directory =
      simdjson
      |> Keyword.fetch!(:patch_series)
      |> Path.dirname()
      |> then(&Path.join(root, &1))

    Enum.each(patches, fn {_sha256, filename} ->
      patch_path = Path.join(patch_directory, filename)

      case System.cmd(
             patch_executable,
             ["-p1", "--batch", "--forward", "--input", patch_path],
             cd: destination,
             stderr_to_stdout: true
           ) do
        {_output, 0} -> :ok
        {output, status} -> Mix.raise("patch #{filename} failed (#{status}):\n#{output}")
      end
    end)
  end

  defp compare_reconstructed_source!(root, simdjson, extraction_directory) do
    vendor_directory = Keyword.fetch!(simdjson, :vendor_directory)

    simdjson
    |> Keyword.fetch!(:archive_members)
    |> Enum.each(fn filename ->
      reconstructed = File.read!(Path.join(extraction_directory, filename))
      vendored = File.read!(Path.join([root, vendor_directory, filename]))

      unless reconstructed == vendored do
        Mix.raise("vendored #{filename} differs from the verified archive plus declared patches")
      end
    end)
  end

  defp verify_digest!(path, expected_sha256, label) do
    actual_sha256 =
      path
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    unless actual_sha256 == expected_sha256 do
      Mix.raise(
        "#{label} checksum mismatch for #{path}: " <>
          "expected=#{expected_sha256} actual=#{actual_sha256}"
      )
    end
  end
end
