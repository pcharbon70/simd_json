defmodule Mix.Tasks.SimdJson.VerifyTraceability do
  @moduledoc """
  Verifies executable Milestone 1 requirement and scenario traceability.
  """

  use Mix.Task

  @shortdoc "Verifies Milestone 1 executable traceability"
  @subjects [
    "simd_json.native_build_and_abi",
    "simd_json.document_resource",
    "simd_json.native_execution",
    "simd_json.document_api"
  ]
  @assertion_pattern ~r/\b(?:assert|assert_raise|refute|flunk|doctest)\b/
  @test_target_pattern ~r{test/[A-Za-z0-9_./*-]+}
  @script_target_pattern ~r{scripts/[A-Za-z0-9_./-]+\.sh}
  @script_proof_pattern ~r/(?:mix (?:compile|hex\.build|test)|zig_executable|run_c_abi_conformance|run_zig_resource_tests|run_nif_sanitizer_tests|verify_release_symbols|verify_offline_native_build|nm -D)/

  @impl Mix.Task
  def run(_arguments) do
    state = read_state!()
    index = Map.fetch!(state, "index")

    inventory = Enum.map(@subjects, &inventory_subject!(index, &1))
    verify_executed_state!(state, inventory)
    write_inventory!(state, inventory)

    Enum.each(inventory, fn item ->
      Mix.shell().info(
        "#{item["subject_id"]}: active requirements=#{item["requirements"]} " <>
          "scenarios=#{item["scenarios"]} executable_commands=#{item["commands"]}"
      )
    end)

    Mix.shell().info("Milestone 1 executable traceability is complete")
  end

  defp inventory_subject!(index, subject_id) do
    subject =
      Enum.find(Map.fetch!(index, "subjects"), &(&1["id"] == subject_id)) ||
        fail!("subject is absent from generated state: #{subject_id}")

    unless get_in(subject, ["meta", "status"]) == "active" do
      fail!("subject is not active: #{subject_id}")
    end

    exceptions = Enum.filter(Map.fetch!(index, "exceptions"), &(&1["subject_id"] == subject_id))

    if exceptions != [] do
      fail!("subject retains exceptions: #{subject_id}")
    end

    requirement_ids = ids_for(index, "requirements", subject_id)
    scenario_ids = ids_for(index, "scenarios", subject_id)
    required_ids = MapSet.new(requirement_ids ++ scenario_ids)

    verifications =
      Enum.filter(Map.fetch!(index, "verifications"), &(&1["subject_id"] == subject_id))

    if verifications == [] do
      fail!("subject has no verification: #{subject_id}")
    end

    command_evidence =
      Enum.map(verifications, fn verification ->
        unless verification["kind"] == "command" and verification["execute"] == true do
          fail!("subject retains non-executable verification: #{subject_id}")
        end

        %{
          "target" => verification["target"],
          "proof" => verify_command_evidence!(verification["target"]),
          "covers" => List.wrap(verification["covers"])
        }
      end)

    covered_ids =
      verifications
      |> Enum.flat_map(&List.wrap(&1["covers"]))
      |> MapSet.new()

    missing = MapSet.difference(required_ids, covered_ids) |> MapSet.to_list() |> Enum.sort()

    if missing != [] do
      fail!(
        "subject has claims without executable proof: #{subject_id}: #{Enum.join(missing, ", ")}"
      )
    end

    claims =
      required_ids
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(fn id ->
        matching = Enum.filter(command_evidence, &(id in &1["covers"]))

        %{
          "id" => id,
          "kind" => if(id in requirement_ids, do: "requirement", else: "scenario"),
          "command_targets" => Enum.map(matching, & &1["target"]),
          "test_targets" =>
            matching |> Enum.flat_map(& &1["proof"]["tests"]) |> Enum.uniq() |> Enum.sort(),
          "script_targets" =>
            matching |> Enum.flat_map(& &1["proof"]["scripts"]) |> Enum.uniq() |> Enum.sort()
        }
      end)

    %{
      "subject_id" => subject_id,
      "status" => "active",
      "requirements" => length(requirement_ids),
      "scenarios" => length(scenario_ids),
      "commands" => length(verifications),
      "command_targets" => Enum.map(verifications, & &1["target"]),
      "claims" => claims
    }
  end

  defp ids_for(index, kind, subject_id) do
    index
    |> Map.fetch!(kind)
    |> Enum.filter(&(&1["subject_id"] == subject_id))
    |> Enum.map(&Map.fetch!(&1, "id"))
  end

  defp verify_executed_state!(state, inventory) do
    if Map.get(state, "findings", []) != [] do
      fail!("generated SpecLed state retains findings")
    end

    verification =
      Map.get(state, "verification") || fail!("SpecLed verification result is absent")

    unless verification["threshold_failures"] == 0 do
      fail!("SpecLed verification retains strength-threshold failures")
    end

    expected_ids =
      inventory
      |> Enum.flat_map(&Enum.map(&1["claims"], fn claim -> claim["id"] end))
      |> MapSet.new()

    claims =
      verification
      |> Map.fetch!("claims")
      |> Enum.filter(&(&1["subject_id"] in @subjects))

    actual_ids = claims |> Enum.map(& &1["cover_id"]) |> MapSet.new()

    unless MapSet.equal?(expected_ids, actual_ids) do
      missing = MapSet.difference(expected_ids, actual_ids) |> MapSet.to_list() |> Enum.sort()
      stale = MapSet.difference(actual_ids, expected_ids) |> MapSet.to_list() |> Enum.sort()

      fail!(
        "executed SpecLed claims do not match current truth; " <>
          "missing=#{inspect(missing)} stale=#{inspect(stale)}"
      )
    end

    weak =
      Enum.reject(claims, fn claim ->
        claim["strength"] == "executed" and claim["required_strength"] == "executed" and
          claim["meets_minimum"] == true
      end)

    if weak != [] do
      fail!("Milestone 1 retains non-executed SpecLed claims: #{inspect(weak)}")
    end
  end

  defp verify_command_evidence!(target) when is_binary(target) and target != "" do
    direct_tests = test_targets!(target)
    scripts = script_targets(target)

    {nested_tests, nested_scripts} =
      Enum.reduce(scripts, {MapSet.new(), MapSet.new()}, fn script, accumulated ->
        merge_evidence(accumulated, discover_script_evidence!(script, MapSet.new()))
      end)

    tests = MapSet.union(MapSet.new(direct_tests), nested_tests)

    if MapSet.size(tests) == 0 and MapSet.size(nested_scripts) == 0 do
      fail!("executed command has no reviewable test or qualification script: #{target}")
    end

    %{
      "tests" => tests |> MapSet.to_list() |> Enum.sort(),
      "scripts" => nested_scripts |> MapSet.to_list() |> Enum.sort()
    }
  end

  defp verify_command_evidence!(_target), do: fail!("verification command is empty")

  defp discover_script_evidence!(script, seen) do
    if MapSet.member?(seen, script) do
      {MapSet.new(), MapSet.new()}
    else
      unless File.regular?(script), do: fail!("qualification script does not exist: #{script}")

      contents = File.read!(script)
      tests = test_targets!(contents)
      children = script_targets(contents) |> Enum.reject(&(&1 == script))

      if tests == [] and children == [] and not Regex.match?(@script_proof_pattern, contents) do
        fail!("qualification script has no behavioral proof command: #{script}")
      end

      next_seen = MapSet.put(seen, script)

      {child_tests, child_scripts} =
        Enum.reduce(children, {MapSet.new(), MapSet.new()}, fn child, accumulated ->
          merge_evidence(accumulated, discover_script_evidence!(child, next_seen))
        end)

      {
        MapSet.union(MapSet.new(tests), child_tests),
        child_scripts |> MapSet.put(script) |> MapSet.union(MapSet.new(children))
      }
    end
  end

  defp merge_evidence({left_tests, left_scripts}, {right_tests, right_scripts}) do
    {MapSet.union(left_tests, right_tests), MapSet.union(left_scripts, right_scripts)}
  end

  defp test_targets!(text) do
    @test_target_pattern
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.filter(&(String.ends_with?(&1, ".exs") or File.dir?(&1) or String.contains?(&1, "*")))
    |> Enum.flat_map(&expand_test_target!/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> tap(&Enum.each(&1, fn path -> verify_test_assertions!(path) end))
  end

  defp expand_test_target!(target) do
    paths =
      cond do
        File.dir?(target) -> Path.wildcard(Path.join(target, "**/*_test.exs"))
        String.contains?(target, "*") -> Path.wildcard(target)
        File.regular?(target) -> [target]
        true -> []
      end

    if paths == [], do: fail!("executed test target does not resolve: #{target}")
    paths
  end

  defp verify_test_assertions!(path) do
    unless Regex.match?(@assertion_pattern, File.read!(path)) do
      fail!("executed test target contains no assertion: #{path}")
    end
  end

  defp script_targets(text) do
    @script_target_pattern
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp read_state! do
    ".spec/state.json"
    |> File.read!()
    |> :json.decode()
  end

  defp write_inventory!(state, inventory) do
    directory =
      System.get_env("SIMD_JSON_QUALIFICATION_DIR") ||
        "_build/qualification/traceability"

    File.mkdir_p!(directory)

    record = %{
      "schema_version" => 1,
      "qualification_input_sha256" => SimdJson.Native.BuildGuard.qualification_fingerprint(),
      "source_revision" => source_revision(),
      "source_tree" => source_tree(),
      "verification_strength" => get_in(state, ["verification", "strength_summary"]),
      "subjects" => inventory
    }

    File.write!(Path.join(directory, "inventory.json"), [:json.encode(record), "\n"])
  end

  defp source_revision do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {revision, 0} -> String.trim(revision)
      _other -> "unavailable"
    end
  end

  defp source_tree do
    case System.cmd("git", ["rev-parse", "HEAD^{tree}"], stderr_to_stdout: true) do
      {tree, 0} -> String.trim(tree)
      _other -> "unavailable"
    end
  end

  defp fail!(message), do: Mix.raise(message)
end
