# Million-row wide projection benchmark

Source revision: `392ffd196312a5e40a0e74a0fa0ae1ef6e1bc361`  
Jason version: `1.4.5`  
Fixture: 1000000 rows × 16 fields, 208223036 uncompressed bytes

Each width selects fields from zero-based row 499999. Jason fully decodes the same document and performs equivalent lookups. Decompression is outside the timed region.

Unlike the earlier million-row supplement, which selected scalar paths distributed across a narrow three-field row shape (`id`, `value`, and unselected `ignored`), this benchmark holds the row and document constant while increasing the number of fields returned from one genuinely wide row.

| Selected fields | SimdJson.select p50 (ms) | Jason decode + lookup p50 (ms) | SimdJson speedup | SimdJson worker peak (MiB) | Jason worker peak (MiB) | SimdJson RSS increase (MiB) | Jason RSS increase (MiB) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 857.583 | 6505.887 | 7.59× | 0.0 | 1608.89 | 0.0 | 1130.67 |
| 2 | 816.765 | 6578.194 | 8.05× | 0.0 | 1608.83 | 297.34 | 586.84 |
| 4 | 828.998 | 6590.206 | 7.95× | 0.01 | 1608.06 | 214.36 | 865.56 |
| 8 | 813.908 | 6496.388 | 7.98× | 0.01 | 1608.88 | 274.84 | 1037.04 |
| 16 | 830.824 | 6674.651 | 8.03× | 0.02 | 1608.06 | 0.0 | 1024.09 |

Worker peak measures the isolated caller. RSS increase is whole-VM peak minus its per-sample baseline and remains allocator/host contextual.
