# Stream ETL benchmark: SimdJson vs Jason

Source revision: `392ffd196312a5e40a0e74a0fa0ae1ef6e1bc361`  
Jason version: `1.4.5`

Both workflows parse the same JSON and calculate the same reduction. The SimdJson workflow uses `SimdJson.stream/2`; the Jason workflow uses `Jason.decode!/1` followed by equivalent lookup and reduction work. The flat million-row fixture has three fields per row (`id`, `value`, and unselected `ignored`); both workflows project `id` and `value` from every row. This measures narrow-row streaming ETL, not how `select/2` scales as more fields are requested from one wide row.

## Acceptance

| Result | Million-row batch | SimdJson process peak | SimdJson/Jason process-peak ratio | Maximum allowed ratio | Maximum allowed SimdJson peak |
| --- | ---: | ---: | ---: | ---: | ---: |
| **PASS** | 1,000 | 123.93 MiB | 0.4× | 0.6× | 128.0 MiB |

## Side-by-side measurements

All values are medians (`p50`).

| Fixture | Rows | Batch | Workflow | Total latency (ms) | Time to first row (ms) | Rows/s | Worker process peak (MiB) | Whole-VM RSS peak (MiB) |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| small | 100 | 128 | SimdJson.stream/2 + reduce | 2.196 | 2.186 | 45537 | 0.01 MiB | 205.57 MiB |
| small | 100 | 128 | Jason.decode!/1 + lookup/reduce | 0.054 | 0.049 | 1851852 | 0.0 MiB | 205.88 MiB |
| small | 100 | 1000 | SimdJson.stream/2 + reduce | 2.235 | 2.226 | 44743 | 0.01 MiB | 205.88 MiB |
| small | 100 | 1000 | Jason.decode!/1 + lookup/reduce | 0.04 | 0.036 | 2500000 | 0.0 MiB | 206.04 MiB |
| medium | 10000 | 128 | SimdJson.stream/2 + reduce | 193.763 | 2.61 | 51609 | 2.17 MiB | 194.88 MiB |
| medium | 10000 | 128 | Jason.decode!/1 + lookup/reduce | 6.479 | 6.087 | 1543448 | 5.53 MiB | 150.24 MiB |
| medium | 10000 | 1000 | SimdJson.stream/2 + reduce | 25.793 | 2.881 | 387702 | 3.0 MiB | 156.72 MiB |
| medium | 10000 | 1000 | Jason.decode!/1 + lookup/reduce | 6.382 | 5.935 | 1566907 | 8.0 MiB | 152.68 MiB |
| million | 1000000 | 128 | SimdJson.stream/2 + reduce | 19122.388 | 38.222 | 52295 | 123.71 MiB | 526.98 MiB |
| million | 1000000 | 128 | Jason.decode!/1 + lookup/reduce | 1523.383 | 1473.292 | 656434 | 371.53 MiB | 1136.87 MiB |
| million | 1000000 | 1000 | SimdJson.stream/2 + reduce | 2890.097 | 37.549 | 346009 | 123.93 MiB | 675.71 MiB |
| million | 1000000 | 1000 | Jason.decode!/1 + lookup/reduce | 1545.166 | 1494.392 | 647180 | 309.81 MiB | 1403.47 MiB |

## SimdJson relative to Jason

Values below `1.0×` mean SimdJson used less time or memory than Jason; values above `1.0×` mean it used more.

| Fixture | Batch | Total latency | Time to first row | Worker process peak | Whole-VM RSS peak |
| --- | ---: | ---: | ---: | ---: | ---: |
| small | 128 | 40.667× | 44.612× | n/a | 0.998× |
| small | 1000 | 55.875× | 61.833× | n/a | 0.999× |
| medium | 128 | 29.906× | 0.429× | 0.392× | 1.297× |
| medium | 1000 | 4.042× | 0.485× | 0.375× | 1.026× |
| million | 128 | 12.553× | 0.026× | 0.333× | 0.464× |
| million | 1000 | 1.87× | 0.025× | 0.4× | 0.481× |

## Measurement definitions

- **Worker process peak** is the highest BEAM memory observed for the isolated benchmark worker. Compare it only with the other workflow's worker-process value.
- **Whole-VM RSS peak** is the highest resident-set size observed for the entire Erlang VM, including BEAM heaps, native allocations, resident mapped pages, loaded code, shared libraries, and allocator retention. Compare it only with the other workflow's RSS value.
- Absolute RSS is contextual rather than library-exclusive because both workflows run in the same long-lived VM. File-backed RSS qualifications therefore measure increase from a pre-operation baseline.
- This benchmark exercises the binary-based `stream/2` API. The separate `stream_file/2` qualification covers bounded file-backed parser memory.
- Total latency and throughput are informational. The release acceptance threshold is based on the million-row worker-process peak.
