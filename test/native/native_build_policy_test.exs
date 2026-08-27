defmodule SimdJson.Native.BuildPolicyTest do
  use ExUnit.Case, async: true

  @native_build_files [
    "mix.exs",
    "lib/mix/tasks/simd_json.verify_vendor.ex",
    "lib/simd_json/native/build_guard.ex",
    "lib/simd_json/native/build_smoke.ex",
    "native/manifest.exs",
    "native/src/build_smoke.cpp",
    "native/zig/build_smoke.zig"
  ]

  # covers: simd_json.native_build_and_abi.clean_checkout_build
  test "compiles the repository vendor snapshot without a system simdjson link" do
    build_configuration = File.read!("lib/simd_json/native/build_smoke.ex")

    assert build_configuration =~ "native/vendor/simdjson/simdjson.cpp"
    assert build_configuration =~ "link_libcpp: true"
    refute build_configuration =~ "link_lib:"

    nif =
      :simd_json
      |> :code.priv_dir()
      |> to_string()
      |> Path.join("lib/Elixir.SimdJson.Native.BuildSmoke.so")

    {dependencies, 0} = System.cmd("ldd", [nif], stderr_to_stdout: true)
    refute dependencies =~ "simdjson"
    refute dependencies =~ "libstdc++"
    refute dependencies =~ "libc++"
  end

  # covers: simd_json.native_build_and_abi.clean_checkout_build
  test "native compilation contains no network acquisition or package discovery" do
    source = Enum.map_join(@native_build_files, "\n", &File.read!/1)

    for forbidden <- [
          "curl ",
          "wget ",
          "git clone",
          "pkg-config",
          "find_library",
          "-lsimdjson"
        ] do
      refute source =~ forbidden
    end
  end

  # covers: simd_json.native_build_and_abi.pinned_toolchain
  test "native and development dependencies resolve through immutable lock entries" do
    lock = Mix.Dep.Lock.read()

    assert {:hex, :zigler, "0.16.0", _inner_checksum, _managers, _dependencies, "hexpm",
            "867ce49289568a7fabff400cb9f1636a429defcd488f3302a82c4b51b2bc7741"} =
             Map.fetch!(lock, :zigler)

    assert {:git, "https://github.com/specleddev/specled_ex.git", commit, options} =
             Map.fetch!(lock, :spec_led_ex)

    assert commit =~ ~r/^[0-9a-f]{40}$/
    assert options[:ref] == commit
  end

  # covers: simd_json.package.native_source_distribution
  test "package files include every clean consumer native input" do
    package_files = Mix.Project.config() |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)

    for entry <- ["lib", "native", ".tool-versions", "mix.exs", "mix.lock"] do
      assert entry in package_files
    end

    for path <- [
          "native/manifest.exs",
          "native/include/simd_json_build_smoke.h",
          "native/src/build_smoke.cpp",
          "native/zig/build_smoke.zig",
          "native/vendor/simdjson/simdjson.cpp",
          "native/vendor/simdjson/simdjson.h",
          "native/vendor/simdjson/LICENSE",
          "native/vendor/simdjson/LICENSE-MIT",
          "native/vendor/simdjson/patches/series"
        ] do
      assert File.regular?(path)
    end
  end

  # covers: simd_json.native_build_and_abi.pinned_toolchain
  test "CI cache identity includes all ABI-relevant source groups and profiles" do
    workflow = File.read!(".github/workflows/ci.yml")

    for cache_component <- [
          "runner.os",
          "x86_64",
          "env.MIX_ENV",
          "env.ZIGLER_RELEASE_MODE",
          ".tool-versions",
          "mix.lock",
          "lib/simd_json/native/**",
          "native/**"
        ] do
      assert workflow =~ cache_component
    end
  end
end
