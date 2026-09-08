defmodule SimdJson.ValidateExDocLinks do
  @source_prefix "https://github.com/pcharbon70/simd_json/blob/"
  @release_source_prefix "#{@source_prefix}v0.1.0/lib/"

  @required_pages %{
    "readme.html" => "Support and operational limits",
    "SimdJson.html" => "Decodes complete JSON values",
    "changelog.html" => "Known limitations",
    "security.html" => "Report a vulnerability privately",
    "contributing.html" => "Before opening a pull request",
    "license.html" => "MIT License",
    "third-party-notices.html" => "simdjson 4.6.9",
    "installation.html" => "Installation and Native Build",
    "support.html" => "Input and memory boundary"
  }

  def run([docs_root]) do
    root = Path.expand(docs_root)
    html_files = Path.wildcard(Path.join(root, "**/*.html"))

    failures = required_page_failures(root) ++ local_link_failures(root, html_files)
    source_links = release_source_links(html_files)

    failures =
      if source_links == [] do
        ["generated documentation contains no project source links" | failures]
      else
        failures
      end

    case failures do
      [] ->
        IO.puts(
          "validated #{length(html_files)} HTML pages and #{length(source_links)} release source links"
        )

      failures ->
        Enum.each(Enum.sort(failures), &IO.puts(:stderr, &1))
        System.halt(1)
    end
  end

  def run(_args) do
    IO.puts(:stderr, "usage: elixir scripts/ci/validate_exdoc_links.exs DOCS_ROOT")
    System.halt(2)
  end

  defp required_page_failures(root) do
    Enum.flat_map(@required_pages, fn {relative, marker} ->
      path = Path.join(root, relative)

      case File.read(path) do
        {:ok, html} ->
          if String.contains?(html, marker),
            do: [],
            else: ["#{relative} is missing rendered marker: #{marker}"]

        {:error, reason} ->
          ["#{relative} is missing: #{:file.format_error(reason)}"]
      end
    end)
  end

  defp local_link_failures(root, html_files) do
    Enum.flat_map(html_files, fn page ->
      page
      |> File.read!()
      |> then(&Regex.scan(~r/href="([^"]+)"/, &1, capture: :all_but_first))
      |> List.flatten()
      |> Enum.flat_map(&validate_href(root, page, &1))
    end)
  end

  defp validate_href(_root, _page, ""), do: []
  defp validate_href(_root, _page, "#" <> _fragment), do: []

  defp validate_href(root, page, href) do
    uri = URI.parse(href)

    cond do
      uri.scheme in ["http", "https", "mailto"] ->
        validate_project_source(href)

      uri.scheme != nil or String.starts_with?(href, "//") ->
        []

      true ->
        validate_local_target(root, page, uri.path)
    end
  end

  defp validate_project_source(href) do
    if String.starts_with?(href, @source_prefix) and
         String.contains?(href, "/lib/") and
         not String.starts_with?(href, @release_source_prefix) do
      ["project API source link does not use v0.1.0: #{href}"]
    else
      []
    end
  end

  defp validate_local_target(root, page, path) do
    decoded_path = path |> to_string() |> URI.decode()

    target =
      case decoded_path do
        "" -> page
        "/" <> relative -> Path.join(root, relative)
        relative -> Path.expand(relative, Path.dirname(page))
      end

    target = if File.dir?(target), do: Path.join(target, "index.html"), else: target

    cond do
      not String.starts_with?(Path.expand(target), root <> "/") ->
        ["#{relative(page, root)} links outside generated docs: #{decoded_path}"]

      File.regular?(target) ->
        []

      true ->
        ["#{relative(page, root)} has missing local link: #{decoded_path}"]
    end
  end

  defp release_source_links(html_files) do
    html_files
    |> Enum.flat_map(fn page ->
      Regex.scan(~r/href="(#{Regex.escape(@release_source_prefix)}[^"]+)"/, File.read!(page),
        capture: :all_but_first
      )
    end)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp relative(path, root), do: Path.relative_to(path, root)
end

SimdJson.ValidateExDocLinks.run(System.argv())
