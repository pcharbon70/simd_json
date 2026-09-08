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
end
