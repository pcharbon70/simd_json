%{
  schema_version: 1,
  generator: "scripts/benchmarks/generate_wide_projection_fixture.exs",
  fixture: %{
    name: :million_wide_16,
    path: "bench/wide_projection_fixture/million-wide-16.json.gz",
    bytes: 208223036,
    rows: 1000000,
    compressed_bytes: 39538906,
    fields_per_row: 16,
    sha256: "08cf49f388569c27938f5aa265a6440fd607dcf4b0c5d8c6b03ea34af997378a"
  },
  field_names: ["f00", "f01", "f02", "f03", "f04", "f05", "f06", "f07", "f08",
   "f09", "f10", "f11", "f12", "f13", "f14", "f15"],
  value_rule: "field fNN at one-based row R equals R + NN"
}
