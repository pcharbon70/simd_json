# This is the authoritative, executable record of every ABI-relevant input for
# the Milestone 1 native build. Build guards read this file; update it only via
# the upgrade procedure in native/README.md.
# covers: simd_json.package.native_build_tooling simd_json.native_build_and_abi.pinned_toolchain simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.clean_checkout_build
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
    driver: "zig c++",
    family: "Zig-bundled Clang/LLVM",
    qualified_version: "21.1.0",
    language_standard: "c++17",
    standard_library: "Zig-bundled libc++",
    linkage: "linked into the NIF by Zig",
    profiles: [
      development: [
        "Zig Debug",
        "-std=c++17",
        "-DSIMDJSON_AVX512_ALLOWED=0",
        "-fvisibility=hidden",
        "-fvisibility-inlines-hidden"
      ],
      release: [
        "Zig ReleaseSafe",
        "-std=c++17",
        "-DSIMDJSON_AVX512_ALLOWED=0",
        "-DNDEBUG",
        "-fvisibility=hidden",
        "-fvisibility-inlines-hidden"
      ],
      sanitizer: [
        "Zig Debug",
        "-std=c++17",
        "-DSIMDJSON_AVX512_ALLOWED=0",
        "-fno-omit-frame-pointer",
        "-fsanitize=address,undefined",
        "-fvisibility=hidden",
        "-fvisibility-inlines-hidden"
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
    vendor_directory: "native/vendor/simdjson",
    patch_series: "native/vendor/simdjson/patches/series",
    archive_members: ["simdjson.cpp", "simdjson.h"],
    vendor_files: [
      {"simdjson.cpp", "452f682d543d3476808b25b8d8df8d884f7b7f4b2fb5df51e5123fd03f1c5e00"},
      {"simdjson.h", "0043db870ceb4c19756519ce9b8b8277ca1585d6222c39b9c022271b69884c4b"},
      {"LICENSE", "5fa8894e890bd77958f93b165433e0fb0dffa5bc982bfb147e4748e95bad24e5"},
      {"LICENSE-MIT", "9ed0a34979f22fc33fc13d942233f22d44906c236d876bd05fadf18cb5abf7da"}
    ],
    padding_bytes: 64,
    input_alignment_bytes: 64,
    language_standard: "c++17",
    supported_compilers: ["Clang 6 or newer", "GCC 7 or newer", "MSVC 2017 or newer"],
    expected_x86_64_runtime_dispatch: ["haswell", "westmere", "fallback"],
    license: "Apache-2.0",
    license_files: ["LICENSE", "LICENSE-MIT"]
  ],
  primary_target: [
    triple: "x86_64-linux-gnu",
    operating_system: "Ubuntu 24.04 LTS",
    architecture: "x86_64",
    libc: "glibc 2.39",
    cxx_runtime: "Zig 0.16.0 bundled libc++ linked into the NIF",
    minimum_otp: "27.3",
    minimum_elixir: "1.18.4",
    expected_simdjson_implementations: ["haswell", "westmere", "fallback"]
  ],
  unsupported_target_diagnostic:
    "unsupported native target %{target}; see native/README.md#target-and-cpu-dispatch-matrix",
  cache_inputs: [
    ".tool-versions",
    "mix.exs",
    "mix.lock",
    "lib/simd_json/application.ex",
    "lib/simd_json/native/build_guard.ex",
    "lib/simd_json/native/build_smoke.ex",
    "lib/simd_json/native/operation_coordinator.ex",
    "lib/simd_json/native/threaded_operation.ex",
    "native/manifest.exs",
    "native/include/simd_json_abi.h",
    "native/include/simd_json_build_smoke.h",
    "native/src/build_smoke.cpp",
    "native/src/simd_json_abi.cpp",
    "native/test/document_resource_test.zig",
    "native/test/include/simd_json_test_hooks.h",
    "native/symbols/c_abi.allowlist",
    "native/symbols/c_abi.version",
    "native/symbols/nif.allowlist",
    "native/zig/build_smoke.zig",
    "native/zig/document_resource.zig",
    "native/vendor/simdjson/simdjson.cpp",
    "native/vendor/simdjson/simdjson.h",
    "native/vendor/simdjson/LICENSE",
    "native/vendor/simdjson/LICENSE-MIT",
    "native/vendor/simdjson/patches/series",
    "scripts/native/run_zig_resource_tests.sh"
  ]
]
