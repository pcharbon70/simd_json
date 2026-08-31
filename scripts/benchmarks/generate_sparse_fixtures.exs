defmodule SimdJson.Benchmarks.GenerateSparseFixtures do
  @moduledoc false

  @seed 260_831_006
  @targets [small: 16 * 1_024, medium: 512 * 1_024, large: 4 * 1_024 * 1_024]
  @fixture_directory Path.expand("../../bench/fixtures", __DIR__)

  def run do
    File.mkdir_p!(@fixture_directory)

    fixtures =
      Enum.map(@targets, fn {name, target_bytes} ->
        source = fixture(name, target_bytes)
        path = Path.join(@fixture_directory, "#{name}.json")
        File.write!(path, source)

        %{
          "name" => Atom.to_string(name),
          "path" => Path.relative_to_cwd(path),
          "bytes" => byte_size(source),
          "sha256" => sha256(source),
          "expected" => expected(name)
        }
      end)

    manifest = %{
      "schema_version" => 1,
      "generator" => "scripts/benchmarks/generate_sparse_fixtures.exs",
      "seed" => @seed,
      "projection" => [
        %{"output" => "id", "path" => ["customer", "id"]},
        %{"output" => "name", "path" => ["customer", "name"]},
        %{"output" => "sku", "path" => ["orders", 0, "sku"]},
        %{"output" => "active", "path" => ["meta", "active"]},
        %{"output" => "nothing", "path" => ["meta", "nothing"]}
      ],
      "fixtures" => fixtures
    }

    File.write!(
      Path.join(@fixture_directory, "manifest.json"),
      [format_json(manifest), "\n"]
    )

    Enum.each(fixtures, fn fixture ->
      IO.puts("#{fixture["name"]}: bytes=#{fixture["bytes"]} sha256=#{fixture["sha256"]}")
    end)
  end

  defp fixture(name, target_bytes) do
    name_string = Atom.to_string(name)
    expected = expected(name)

    prefix =
      IO.iodata_to_binary([
        ~s({"meta":{"fixture":"#{name_string}","seed":#{@seed},"active":true,"nothing":null},),
        ~s("customer":{"id":#{expected["id"]},"name":"#{expected["name"]}",),
        ~s("unselected_profile":{"history":[1,2,3,4],"internal":"ignore"}},),
        ~s("orders":[{"sku":"#{expected["sku"]}","quantity":7,"unselected":{"discounts":[1,2,3]}}],),
        ~s("unselected":{"records":[)
      ])

    suffix_prefix = ~s(],"padding":")
    suffix = ~s("},"tail":{"valid":true}})
    available = target_bytes - byte_size(prefix) - byte_size(suffix_prefix) - byte_size(suffix)

    {records, records_bytes, _state} = records_for(available, @seed, [], 0, 0)
    padding_bytes = available - records_bytes

    source =
      IO.iodata_to_binary([
        prefix,
        Enum.reverse(records),
        suffix_prefix,
        String.duplicate("p", padding_bytes),
        suffix
      ])

    if byte_size(source) != target_bytes do
      raise "fixture #{name} has #{byte_size(source)} bytes, expected #{target_bytes}"
    end

    source
  end

  defp records_for(available, state, records, bytes, index) do
    next_state = rem(state * 1_103_515_245 + 12_345, 2_147_483_648)
    separator = if index == 0, do: "", else: ","

    record =
      IO.iodata_to_binary([
        separator,
        ~s({"index":#{index},"token":"noise-#{Integer.to_string(next_state, 16)}",),
        ~s("values":[#{rem(next_state, 997)},#{rem(next_state, 991)},#{rem(next_state, 983)}],),
        ~s("flags":{"a":true,"b":false},"nested":{"discard":"value-#{index}"}})
      ])

    record_bytes = byte_size(record)

    if bytes + record_bytes <= available - 256 do
      records_for(
        available,
        next_state,
        [record | records],
        bytes + record_bytes,
        index + 1
      )
    else
      {records, bytes, next_state}
    end
  end

  defp expected(name) do
    offset = Enum.find_index(Keyword.keys(@targets), &(&1 == name))

    %{
      "id" => @seed + offset,
      "name" => "Fixture #{String.capitalize(to_string(name))}",
      "sku" => "SKU-#{100 + offset}",
      "active" => true,
      "nothing" => :null
    }
  end

  defp format_json(value) do
    value
    |> :json.encode()
    |> IO.iodata_to_binary()
  end

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
end

SimdJson.Benchmarks.GenerateSparseFixtures.run()
