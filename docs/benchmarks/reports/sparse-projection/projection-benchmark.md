# Sparse projection benchmark

Source revision: `392ffd196312a5e40a0e74a0fa0ae1ef6e1bc361`

| Fixture | Workflow | p50 ns | ops/s at p50 | median estimated BEAM bytes |
| --- | --- | ---: | ---: | ---: |
| small | jason_decode_and_lookup | 440773 | 2268.742 | 217800 |
| small | simd_json_select | 294098 | 3400.227 | 4256 |
| medium | jason_decode_and_lookup | 8576233 | 116.601 | 6908440 |
| medium | simd_json_select | 2980601 | 335.503 | 4256 |
| large | jason_decode_and_lookup | 110991832 | 9.01 | 54990640 |
| large | simd_json_select | 18949463 | 52.772 | 4256 |

Allocation threshold: **PASS**. Latency and throughput are context only.
