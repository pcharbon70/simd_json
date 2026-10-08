defmodule SimdJson.PackageDocumentationContractTest do
  use ExUnit.Case, async: true

  # covers: simd_json.release.public_identity simd_json.release.project_license simd_json.release.consumer_documentation
  test "publishes complete Hex and ExDoc identity metadata" do
    project = Mix.Project.config()
    package = Keyword.fetch!(project, :package)
    docs = Keyword.fetch!(project, :docs)

    assert project[:app] == :simd_json
    assert project[:name] == "SimdJson"
    assert project[:version] == "1.0.0"
    assert project[:source_url] == "https://github.com/pcharbon70/simd_json"
    assert project[:homepage_url] == "https://github.com/pcharbon70/simd_json"

    assert package[:name] == "simd_json"
    assert package[:maintainers] == ["Pascal Charbonneau"]
    assert package[:licenses] == ["MIT"]

    assert package[:links] == %{
             "Documentation" => "https://hexdocs.pm/simd_json",
             "GitHub" => "https://github.com/pcharbon70/simd_json",
             "Homepage" => "https://github.com/pcharbon70/simd_json",
             "Issues" => "https://github.com/pcharbon70/simd_json/issues"
           }

    assert docs[:source_url] == "https://github.com/pcharbon70/simd_json"
    assert docs[:source_ref] == "v1.0.0"

    groups = Keyword.fetch!(docs, :groups_for_extras)

    assert groups[:"User guides"] == [
             "docs/guides/01-getting-started.md",
             "docs/guides/02-decoding-json.md",
             "docs/guides/03-selecting-fields.md",
             "docs/guides/04-streaming-large-files.md",
             "docs/guides/05-errors-limits-performance.md",
             "docs/guides/06-deployment.md",
             "docs/guides/07-explore-with-livebook.livemd"
           ]

    refute Keyword.has_key?(groups, :"Milestone guides")
    refute Keyword.has_key?(groups, :"Operations guides")
    refute Keyword.has_key?(groups, :"Acceptance records")
    refute Keyword.has_key?(groups, :"Release policies")
    assert groups[:"Release notes"] == ["CHANGELOG.md"]
    assert groups[:Security] == ["SECURITY.md"]
    assert groups[:Contributing] == ["CONTRIBUTING.md"]

    assert groups[:Benchmarks] == [
             "docs/benchmarks/README.md",
             "docs/benchmarks/reports/sparse-projection/projection-benchmark.md",
             "docs/benchmarks/reports/stream-etl/stream-etl.md",
             "docs/benchmarks/reports/eager-decode/decode-benchmark.md",
             "docs/benchmarks/reports/wide-projection/wide-projection.md"
           ]

    extras = Keyword.fetch!(docs, :extras)

    for page <- groups[:Benchmarks] do
      assert Enum.any?(extras, fn
               {^page, _options} -> true
               _extra -> false
             end)
    end
  end

  # covers: simd_json.package.specled_tooling simd_json.release.archive_integrity
  test "publishes only consumer dependencies with qualified runtime requirements" do
    project = Mix.Project.config()

    assert project[:elixir] == "~> 1.18.4"

    assert {:zigler, "== 0.16.0", zigler_options} =
             Enum.find(project[:deps], &match?({:zigler, _, _}, &1))

    assert zigler_options[:runtime] == false
    assert zigler_options[:optional] == true
    assert {:telemetry, "~> 1.3"} in project[:deps]

    assert {:jason, "== 1.4.5", jason_options} =
             Enum.find(project[:deps], &match?({:jason, _, _}, &1))

    assert jason_options[:only] == [:dev, :test]
    assert jason_options[:runtime] == false

    assert {:spec_led_ex, specled_options} =
             Enum.find(project[:deps], &match?({:spec_led_ex, _}, &1))

    assert specled_options[:only] == [:dev, :test]
    assert specled_options[:runtime] == false
    assert is_binary(specled_options[:github])
    assert is_binary(specled_options[:ref])
  end

  # covers: simd_json.release.consumer_documentation simd_json.release.qualified_support
  test "documents a copyable precompiled installation and explicit source-build contract" do
    readme = File.read!("README.md")
    installation = File.read!("docs/guides/06-deployment.md")

    for document <- [readme, installation] do
      assert document =~ ~s({:simd_json, "~> 1.0.0"})
      assert document =~ "mix deps.get"
      assert document =~ "mix compile"
    end

    [installation_section | _rest] = String.split(readme, "## Quick examples", parts: 2)
    refute installation_section =~ "mix zig.get --version 0.16.0"
    assert installation =~ "Ordinary consumers do not need Zig"
    assert installation =~ "SIMD_JSON_BUILD_FROM_SOURCE=1"
    assert installation =~ "mix zig.get --version 0.16.0"
    assert installation =~ "SIMD_JSON_PRECOMPILED_PATH"
    assert installation =~ "native/precompiled/checksums.exs"
    assert installation =~ "Ubuntu 24.04 LTS"
    assert installation =~ "glibc 2.39"
    assert installation =~ "bundled Clang/LLVM 21.1.0 and libc++"
    assert installation =~ "system simdjson package"
    assert installation =~ "ZIG_GLOBAL_CACHE_DIR"
    assert installation =~ "Unsupported native target"
    assert installation =~ "experimental or unsupported"
  end

  # covers: simd_json.release.consumer_documentation simd_json.package.documentation_layout
  test "leads with measured workload-selection guidance" do
    readme = File.read!("README.md")

    assert readme =~ "## Choose SimdJson for selective work"
    assert readme =~ "7.59× to 8.05× faster"
    assert readme =~ "Jason is generally the better choice"
    assert readme =~ "took 1.87× as long overall as Jason"
    assert readme =~ "used 40% of Jason's"
    assert readme =~ "worker-process memory peak"
    assert readme =~ "| 16 | 830.824 ms | 6,674.651 ms | 8.03× | 0.02 MiB | 1,608.06 MiB |"
    assert readme =~ "[See the complete benchmark reports](docs/benchmarks/README.md)"

    assert position(readme, "## Choose SimdJson for selective work") <
             position(readme, "## Installation")
  end

  # covers: simd_json.release.consumer_documentation
  test "documented decode, select, and stream smoke workflows execute" do
    assert {:ok, %{"ready" => true}} = SimdJson.decode(~s({"ready":true}))

    assert {:ok, %{id: 7}} =
             SimdJson.select(~s({"account":{"id":7}}), id: ["account", "id"])

    assert [%{id: 1}, %{id: 2}] =
             SimdJson.stream(~s({"rows":[{"id":1},{"id":2}]}),
               path: ["rows"],
               fields: [id: ["id"]],
               batch_size: 1
             )
             |> Enum.to_list()
  end

  # covers: simd_json.release.consumer_documentation simd_json.package.documentation_layout
  test "Livebook tutorial executes from top to bottom" do
    livebook = File.read!("docs/guides/07-explore-with-livebook.livemd")

    blocks =
      ~r/```elixir\n(.*?)```/s
      |> Regex.scan(livebook, capture: :all_but_first)
      |> List.flatten()

    assert length(blocks) == 8

    Enum.reduce(blocks, [], fn block, binding ->
      {_result, next_binding} =
        Code.eval_string(block, binding, file: "07-explore-with-livebook.livemd")

      next_binding
    end)
  end

  # covers: simd_json.release.consumer_documentation simd_json.release.qualified_support
  test "publishes the accepted contract, release notes, and private security policy" do
    readme = File.read!("README.md")
    changelog = File.read!("CHANGELOG.md")
    security = File.read!("SECURITY.md")
    contributing = File.read!("CONTRIBUTING.md")

    assert readme =~ "The qualified target is Ubuntu 24.04 x86-64"
    assert readme =~ "File-backed APIs pass only"
    assert readme =~ "bounded-parser-memory path"
    assert readme =~ "stream_file/2"
    assert readme =~ "Getting Started"
    refute readme =~ ~r/milestone/i

    assert changelog =~ "## 1.0.0"
    assert changelog =~ "### Known limitations"
    assert changelog =~ "consumers install without Zig or Zigler"
    assert changelog =~ "one-million-row fixture"
    assert changelog =~ "A full queue returns `:busy`"

    assert security =~ "Only the newest published patch in the `1.0.x` series"
    assert security =~ "pcharbon70@gmail.com"
    assert security =~ "Do not open a public issue"

    assert contributing =~ "mix format --check-formatted"
    assert contributing =~ "mix test"
    assert contributing =~ "mix spec.next"
    assert contributing =~ "mix spec.check --base origin/main"
  end

  # covers: simd_json.release.consumer_documentation simd_json.package.documentation_layout
  test "publishes only feature-oriented user documentation" do
    docs = Mix.Project.config() |> Keyword.fetch!(:docs)
    extras = Keyword.fetch!(docs, :extras)

    published_markdown =
      ["README.md"] ++
        for extra <- extras,
            path = if(is_tuple(extra), do: elem(extra, 0), else: extra),
            Path.extname(path) in [".md", ".livemd"],
            do: path

    for path <- published_markdown do
      refute File.read!(path) =~ ~r/milestone/i, "#{path} contains internal roadmap language"
    end

    refute module_doc(SimdJson) =~ ~r/milestone/i
  end

  # covers: simd_json.release.archive_integrity simd_json.release.consumer_documentation
  test "defines executable archive, secret, size, checksum, and rendered-doc gates" do
    verifier = File.read!("scripts/ci/verify_package_documentation.sh")
    link_validator = File.read!("scripts/ci/validate_exdoc_links.exs")

    assert verifier =~ "mix hex.publish package --dry-run --yes"
    assert verifier =~ "unused-dry-run-placeholder"
    assert verifier =~ "required_package_files"
    assert verifier =~ "forbidden_directory"
    assert verifier =~ "secret_patterns"
    assert verifier =~ "package_compressed_limit"
    assert verifier =~ "docs_uncompressed_limit"
    assert verifier =~ "package-files.sha256"
    assert verifier =~ "mix docs --warnings-as-errors"
    assert verifier =~ "validate_exdoc_links.exs"

    assert link_validator =~ "@release_source_prefix"
    assert link_validator =~ "required_page_failures"
    assert link_validator =~ "local_link_failures"

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/ci/verify_package_documentation.sh"],
               stderr_to_stdout: true
             )
  end

  defp module_doc(module) do
    {:docs_v1, _, _, _, %{"en" => module_doc}, _, _} = Code.fetch_docs(module)
    module_doc
  end

  defp position(document, text) do
    {position, _length} = :binary.match(document, text)
    position
  end
end
