%{
  seed: 260902003,
  fixtures: [
    %{
      name: :small,
      path: "bench/stream_fixtures/small.json.gz",
      bytes: 3785,
      rows: 100,
      nested: false,
      compressed_bytes: 666,
      sha256: "0fad77eec6cadbe817c6204f3bd93545bf22c46430055de1241f6c93e17966ec",
      expected_sum: 10100
    },
    %{
      name: :medium,
      path: "bench/stream_fixtures/medium.json.gz",
      bytes: 416700,
      rows: 10000,
      nested: true,
      compressed_bytes: 72038,
      sha256: "99b0d5b90b584d7fdfe66b45f9db8542040cf8af384dcfa5bdf3c1bd8d24e43a",
      expected_sum: 100010000
    },
    %{
      name: :million,
      path: "bench/stream_fixtures/million.json.gz",
      bytes: 45666793,
      rows: 1000000,
      nested: false,
      compressed_bytes: 7113832,
      sha256: "2171d30d6e247aede4318ba732e60e41af513be04b3d148cd26b92f218042ea7",
      expected_sum: 1000001000000
    }
  ],
  huge_row: %{
    path: "bench/stream_fixtures/huge-row.json.gz",
    bytes: 1048609,
    sha256: "4ca55e9e6448b1c0ee724051c3dbcab566b90a12e011caf9eb401691effd269a"
  },
  schema_version: 1,
  generator: "scripts/benchmarks/generate_stream_fixtures.exs",
  projection: [id: ["id"], value: ["value"]]
}
