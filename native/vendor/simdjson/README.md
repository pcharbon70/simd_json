# Vendored simdjson source

This directory is an exact, reviewable import of the official simdjson
single-header release. It is compiled from the repository and must never be
replaced by a system library or a build-time download.

## Provenance

| Input | Recorded value |
| --- | --- |
| Release | `v4.6.9` |
| Commit | `0a2e33f345f49cb6e24401d5b16dbdbc9650921a` |
| Archive | `https://github.com/simdjson/simdjson/releases/download/v4.6.9/singleheader.zip` |
| Archive SHA-256 | `d406c794beece1ce6b9f9458914346560686c44a407f7e621299437bf38644ec` |
| `simdjson.cpp` SHA-256 | `452f682d543d3476808b25b8d8df8d884f7b7f4b2fb5df51e5123fd03f1c5e00` |
| `simdjson.h` SHA-256 | `0043db870ceb4c19756519ce9b8b8277ca1585d6222c39b9c022271b69884c4b` |
| `LICENSE` SHA-256 | `5fa8894e890bd77958f93b165433e0fb0dffa5bc982bfb147e4748e95bad24e5` |
| `LICENSE-MIT` SHA-256 | `9ed0a34979f22fc33fc13d942233f22d44906c236d876bd05fadf18cb5abf7da` |

The source archive contains only `simdjson.cpp` and `simdjson.h`. The two
license files were copied from the recorded immutable commit. The whole
`native` directory is listed in the Mix package files, so these licenses ship
with every Hex artifact.

Verify the checked-in files without network access:

```console
mix simd_json.verify_vendor
```

Also prove that the snapshot reconstructs from an already downloaded official
archive:

```console
mix simd_json.verify_vendor --archive /path/to/singleheader.zip
```

## Upstream contract used by this project

- `SIMDJSON_PADDING` is exactly 64 bytes.
- This project compiles the amalgamation as C++17. Upstream supports Clang 6+,
  GCC 7+, and Visual Studio 2017+; the narrower qualified project toolchain is
  recorded in `native/manifest.exs`.
- On the primary x86-64 target, simdjson selects an implementation at runtime
  from `icelake`, `haswell`, `westmere`, and `fallback` according to CPU
  capabilities. The build must not force a faster implementation than the host
  can execute.

## No-hidden-patch policy

The imported files are not edited in place. Every necessary local change must
be a separate unified-diff file under `patches/`, accompanied by rationale and
an upstream reference in its header. Add its SHA-256 and filename to
`patches/series` in application order. The verifier rejects missing,
undeclared, reordered, or modified patches and reconstructs the expected tree
before comparing it with the checked-in snapshot.

There are currently no local patches.

## Dependency-upgrade gate

Changing simdjson, Zig, Zigler, the C++ toolchain, build flags, or target data
requires a reviewed manifest update. Before acceptance, regenerate and review
the source provenance and licenses, clean offline build, C ABI conformance,
sanitizer, exported-symbol, CPU-dispatch, and BEAM scheduler evidence. Run the
complete SpecLed checks named by the implementation plan; changing only a
version string or checksum is not sufficient.

<!-- covers: simd_json.native_build_and_abi.official_vendored_source simd_json.native_build_and_abi.dependency_upgrade_gate simd_json.package.native_source_distribution -->
