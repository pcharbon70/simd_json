defmodule SimdJson.Benchmark.SparseFixtureTest do
  use ExUnit.Case, async: true

  @manifest_path "bench/fixtures/manifest.json"
  @policy_path "bench/sparse_projection_policy.exs"

  # covers: simd_json.projection_execution.end_to_end_benchmark simd_json.projection_execution.sparse_allocation_advantage simd_json.projection_execution.jason_sparse_benchmark
  test "frozen sparse fixtures have exact sizes, digests, expected values, and equivalent workflows" do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()
    {policy, _binding} = Code.eval_file(@policy_path)

    assert manifest["seed"] == policy.fixture_generator_seed
    assert Enum.map(manifest["fixtures"], & &1["name"]) == ["small", "medium", "large"]

    for fixture <- manifest["fixtures"] do
      source = File.read!(fixture["path"])
      decoded = Jason.decode!(source)
      expected = fixture["expected"]

      assert byte_size(source) == fixture["bytes"]
      assert sha256(source) == fixture["sha256"]

      projection = [
        id: ["customer", "id"],
        name: ["customer", "name"],
        sku: ["orders", 0, "sku"],
        active: ["meta", "active"],
        nothing: ["meta", "nothing"]
      ]

      assert {:ok, selected} = SimdJson.select(source, projection)

      assert selected == %{
               id: get_in(decoded, ["customer", "id"]),
               name: get_in(decoded, ["customer", "name"]),
               sku: get_in(decoded, ["orders", Access.at(0), "sku"]),
               active: get_in(decoded, ["meta", "active"]),
               nothing: get_in(decoded, ["meta", "nothing"])
             }

      assert selected == %{
               id: expected["id"],
               name: expected["name"],
               sku: expected["sku"],
               active: expected["active"],
               nothing: expected["nothing"]
             }
    end
  end

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
end
