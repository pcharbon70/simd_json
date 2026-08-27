# This is the authoritative, executable record of every ABI-relevant input for
# the Milestone 1 native build. Build guards read this file; update it only via
# the upgrade procedure in native/README.md.
# covers: simd_json.package.native_build_tooling simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.target_qualification
[
  schema_version: 1,
  qualified_on: ~D[2026-08-27],
  beam: [
    elixir_requirement: "~> 1.18.4",
    qualified_elixir: "1.18.4",
    qualified_otp: "27.3"
  ],
  zigler: [
    version: "0.16.0",
    requirement: "== 0.16.0",
    hex_url: "https://hex.pm/packages/zigler/0.16.0",
    hex_sha256: "867ce49289568a7fabff400cb9f1636a429defcd488f3302a82c4b51b2bc7741",
    threaded_docs: "https://hexdocs.pm/zigler/0.16.0/07-concurrency.html#threaded"
  ],
  zig: [
    version: "0.16.0",
    download_index: "https://ziglang.org/download/index.json",
    primary_archive_url: "https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz",
    primary_archive_sha256: "70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00"
  ],
  cxx: [
    family: "GCC",
    qualified_version: "13.3.0",
    accepted_major: 13,
    language_standard: "c++17",
    standard_library: "libstdc++.so.6",
    profiles: [
      development: ["-std=c++17", "-O0", "-g", "-fvisibility=hidden"],
      release: [
        "-std=c++17",
        "-O3",
        "-DNDEBUG",
        "-fvisibility=hidden",
        "-fvisibility-inlines-hidden"
      ],
      sanitizer: [
        "-std=c++17",
        "-O1",
        "-g",
        "-fno-omit-frame-pointer",
        "-fsanitize=address,undefined",
        "-fvisibility=hidden"
      ]
    ]
  ],
  simdjson: [
    version: "4.6.9",
    tag: "v4.6.9",
    commit: "0a2e33f345f49cb6e24401d5b16dbdbc9650921a",
    release_url: "https://github.com/simdjson/simdjson/releases/tag/v4.6.9",
    archive_url: "https://github.com/simdjson/simdjson/releases/download/v4.6.9/singleheader.zip",
    archive_sha256: "d406c794beece1ce6b9f9458914346560686c44a407f7e621299437bf38644ec",
    padding_bytes: 64,
    license: "Apache-2.0"
  ],
  primary_target: [
    triple: "x86_64-linux-gnu",
    operating_system: "Ubuntu 24.04 LTS",
    architecture: "x86_64",
    libc: "glibc 2.39",
    cxx_runtime: "libstdc++.so.6 from GCC 13.3.0",
    minimum_otp: "27.3",
    minimum_elixir: "1.18.4",
    expected_simdjson_implementations: ["icelake", "haswell", "westmere", "fallback"]
  ],
  unsupported_target_diagnostic:
    "unsupported native target %{target}; see native/README.md#target-and-cpu-dispatch-matrix"
]
