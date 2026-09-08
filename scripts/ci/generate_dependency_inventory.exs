#!/usr/bin/env elixir

# covers: simd_json.release.provenance simd_json.release.reproducible_candidate

defmodule SimdJson.ReleaseDependencyInventory do
  def run([package_metadata, output_path | rest]) do
    deps_root = List.first(rest) || "deps"
    package = read_metadata!(package_metadata)

    dependencies =
      package
      |> requirements()
      |> collect(deps_root, MapSet.new(), [])
      |> Enum.sort_by(& &1.name)

    rows = [
      row("simd_json", value!(package, "version"), licenses(package), "wrapper"),
      row("simdjson", "4.6.9", "Apache-2.0 OR MIT", "vendored")
      | Enum.map(dependencies, fn dependency ->
          row(
            dependency.name,
            dependency.version,
            dependency.licenses,
            "hexpm"
          )
        end)
    ]

    File.write!(
      output_path,
      ["name\tversion\tlicenses\tsource\n", Enum.map_join(rows, "\n", & &1), "\n"]
    )
  end

  def run(_args) do
    IO.puts(
      :stderr,
      "usage: generate_dependency_inventory.exs PACKAGE_METADATA OUTPUT [DEPS_ROOT]"
    )

    System.halt(64)
  end

  defp collect([], _deps_root, _seen, collected), do: collected

  defp collect([name | remaining], deps_root, seen, collected) do
    if MapSet.member?(seen, name) do
      collect(remaining, deps_root, seen, collected)
    else
      path = Path.join([deps_root, name, "hex_metadata.config"])

      unless File.regular?(path) do
        raise "missing Hex metadata for release dependency #{name}: #{path}"
      end

      metadata = read_metadata!(path)

      dependency = %{
        name: value!(metadata, "name"),
        version: value!(metadata, "version"),
        licenses: licenses(metadata)
      }

      collect(
        remaining ++ requirements(metadata),
        deps_root,
        MapSet.put(seen, name),
        [dependency | collected]
      )
    end
  end

  defp requirements(metadata) do
    metadata
    |> Map.get(<<"requirements">>, [])
    |> Enum.map(&Map.new/1)
    |> Enum.reject(&Map.get(&1, <<"optional">>, false))
    |> Enum.map(&value!(&1, "name"))
  end

  defp licenses(metadata) do
    case Map.get(metadata, <<"licenses">>, []) do
      [] -> "UNKNOWN"
      values -> Enum.map_join(values, " OR ", &to_string/1)
    end
  end

  defp read_metadata!(path) do
    case :file.consult(String.to_charlist(path)) do
      {:ok, terms} -> Map.new(terms)
      {:error, reason} -> raise "could not read #{path}: #{inspect(reason)}"
    end
  end

  defp value!(metadata, key), do: metadata |> Map.fetch!(key) |> to_string()

  defp row(name, version, license, source) do
    [name, version, license, source]
    |> Enum.map(&sanitize/1)
    |> Enum.join("\t")
  end

  defp sanitize(value) do
    value
    |> to_string()
    |> String.replace(~r/[\t\r\n]+/, " ")
  end
end

SimdJson.ReleaseDependencyInventory.run(System.argv())
