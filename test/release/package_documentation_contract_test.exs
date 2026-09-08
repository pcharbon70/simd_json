defmodule SimdJson.PackageDocumentationContractTest do
  use ExUnit.Case, async: true

  # covers: simd_json.release.public_identity simd_json.release.project_license simd_json.release.consumer_documentation
  test "publishes complete Hex and ExDoc identity metadata" do
    project = Mix.Project.config()
    package = Keyword.fetch!(project, :package)
    docs = Keyword.fetch!(project, :docs)

    assert project[:app] == :simd_json
    assert project[:name] == "SimdJson"
    assert project[:version] == "0.1.0"
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
    assert docs[:source_ref] == "v0.1.0"

    groups = Keyword.fetch!(docs, :groups_for_extras)
    assert groups[:"Milestone guides"]
    assert groups[:"Operations guides"]
    assert groups[:"Acceptance records"]
    assert groups[:"Release notes"] == ["CHANGELOG.md"]
    assert groups[:Security] == ["SECURITY.md"]
    assert groups[:Contributing] == ["CONTRIBUTING.md"]
  end

  # covers: simd_json.package.specled_tooling simd_json.release.archive_integrity
  test "publishes only consumer dependencies with qualified runtime requirements" do
    project = Mix.Project.config()

    assert project[:elixir] == "~> 1.18.4"

    assert {:zigler, "== 0.16.0", zigler_options} =
             Enum.find(project[:deps], &match?({:zigler, _, _}, &1))

    assert zigler_options[:runtime] == false
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
  test "documents a copyable source-build installation contract" do
    readme = File.read!("README.md")
    installation = File.read!("docs/releases/installation.md")

    for document <- [readme, installation] do
      assert document =~ ~s({:simd_json, "~> 0.1.0"})
      assert document =~ "mix deps.get"
      assert document =~ "mix zig.get --version 0.16.0"
      assert document =~ "mix compile"
    end

    assert installation =~ "first release does not ship precompiled NIF artifacts"
    assert installation =~ "Ubuntu 24.04 LTS"
    assert installation =~ "glibc 2.39"
    assert installation =~ "bundled Clang/LLVM 21.1.0 and libc++"
    assert installation =~ ~r/never discovers a\s+system simdjson installation/
    assert installation =~ "budget several minutes"
    assert installation =~ "ZIG_GLOBAL_CACHE_DIR"
    assert installation =~ "Unsupported native target"
    assert installation =~ "experimental or unsupported"
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

  # covers: simd_json.release.consumer_documentation simd_json.release.qualified_support
  test "publishes the accepted contract, release notes, and private security policy" do
    readme = File.read!("README.md")
    changelog = File.read!("CHANGELOG.md")
    security = File.read!("SECURITY.md")
    contributing = File.read!("CONTRIBUTING.md")

    assert readme =~ "Milestones 1–5 are active"
    assert readme =~ ~r/complete JSON binary.*encoded document is already\s+resident in memory/s
    assert readme =~ "does not incrementally read JSON from a file"
    assert readme =~ "45,666,793-byte million-row fixture"
    assert readme =~ "pool operations guide"
    assert readme =~ "telemetry runbook"
    assert readme =~ "decode acceptance record"

    assert changelog =~ "## 0.1.0"
    assert changelog =~ "### Known limitations"
    assert changelog =~ "no precompiled native artifacts"
    assert changelog =~ "one-million-row fixture"
    assert changelog =~ "A full queue returns `:busy`"

    assert security =~ "Only the newest published patch in the `0.1.x` series"
    assert security =~ "pcharbon70@gmail.com"
    assert security =~ "Do not open a public issue"

    assert contributing =~ "mix format --check-formatted"
    assert contributing =~ "mix test"
    assert contributing =~ "mix spec.next"
    assert contributing =~ "mix spec.check --base origin/main"
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
end
