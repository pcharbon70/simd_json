# Eager decode benchmark: SimdJson vs Jason

Source revision: `392ffd196312a5e40a0e74a0fa0ae1ef6e1bc361`  
Jason version: `1.4.5`  
Correctness acceptance: **PASS**

Both workflows fully materialize the same JSON input into equivalent Elixir terms. This benchmark measures eager `decode/1`; it does not measure bounded streaming or sparse projection. Each value is the median (`p50`) of 5 measured samples after 2 warmup samples.

| Fixture | Input bytes | Workflow | Latency p50 (µs) | Throughput (MiB/s) | Reductions p50 | Caller memory delta p50 (bytes) | Minor GCs p50 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| small | 24 | SimdJson.decode/1 | 41 | 0.56 | 75 | 0 | 0 |
| small | 24 | Jason.decode/1 | 1 | 22.89 | 81 | 72 | 0 |
| medium | 16427 | SimdJson.decode/1 | 566 | 27.68 | 75 | 0 | 0 |
| medium | 16427 | Jason.decode/1 | 108 | 145.06 | 20532 | 39208 | 0 |
| large_array | 523344 | SimdJson.decode/1 | 220912 | 2.26 | 78 | 72 | 0 |
| large_array | 523344 | Jason.decode/1 | 7285 | 68.51 | 851742 | 8833112 | 1 |
| nested | 2584 | SimdJson.decode/1 | 100 | 24.64 | 75 | 0 | 0 |
| nested | 2584 | Jason.decode/1 | 18 | 136.91 | 4165 | 9216 | 0 |
| strings | 134001 | SimdJson.decode/1 | 12932 | 9.88 | 75 | 0 | 0 |
| strings | 134001 | Jason.decode/1 | 296 | 431.73 | 138083 | 160000 | 0 |
| numbers | 160860 | SimdJson.decode/1 | 3533 | 43.42 | 75 | 0 | 0 |
| numbers | 160860 | Jason.decode/1 | 3020 | 50.8 | 242131 | 4343392 | 1 |
| malformed | 5 | SimdJson.decode/1 | 23 | 0.21 | 94 | 0 | 0 |
| malformed | 5 | Jason.decode/1 | 0 | 4.77 | 61 | 48 | 0 |

Caller memory delta is the non-negative difference between process memory immediately before and after the call. It is not a sampled peak and may be zero after garbage collection. Throughput and memory values are host- and allocator-contextual.
