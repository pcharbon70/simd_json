defmodule SimdJson.Native.PrecompiledTest do
  use ExUnit.Case, async: true

  alias SimdJson.Native.BuildError
  alias SimdJson.Native.Precompiled

  @target "x86_64-linux-gnu"

  test "source builds remain explicit for repository and test contexts" do
    assert Precompiled.resolve!(
             target: @target,
             mix_env: :prod,
             source_checkout: true,
             env: %{}
           ) == nil

    assert Precompiled.resolve!(
             target: @target,
             mix_env: :test,
             source_checkout: false,
             env: %{}
           ) == nil

    assert Precompiled.resolve!(
             target: @target,
             mix_env: :prod,
             source_checkout: false,
             env: %{"SIMD_JSON_BUILD_FROM_SOURCE" => "1"}
           ) == nil
  end

  test "a local candidate must match its independently supplied checksum" do
    path = Path.join(System.tmp_dir!(), "simd-json-precompiled-#{System.unique_integer()}.so")
    on_exit(fn -> File.rm(path) end)
    File.write!(path, "candidate")
    checksum = :crypto.hash(:sha256, "candidate") |> Base.encode16(case: :lower)

    assert Precompiled.resolve!(
             target: @target,
             mix_env: :prod,
             source_checkout: false,
             env: %{
               "SIMD_JSON_PRECOMPILED_PATH" => path,
               "SIMD_JSON_PRECOMPILED_SHA256" => checksum
             }
           ) == Path.expand(path)

    assert_raise BuildError, ~r/checksum mismatch/, fn ->
      Precompiled.resolve!(
        target: @target,
        mix_env: :prod,
        source_checkout: false,
        env: %{
          "SIMD_JSON_PRECOMPILED_PATH" => path,
          "SIMD_JSON_PRECOMPILED_SHA256" => String.duplicate("0", 64)
        }
      )
    end
  end

  test "packaged builds fail closed without a qualified checksum" do
    assert_raise BuildError, ~r/no qualified precompiled NIF checksum/, fn ->
      Precompiled.resolve!(
        version: "99.99.99",
        target: @target,
        mix_env: :prod,
        source_checkout: false,
        env: %{}
      )
    end
  end

  test "unsupported targets fail before artifact selection" do
    assert_raise BuildError, ~r/no qualified precompiled NIF for target/, fn ->
      Precompiled.resolve!(
        target: "aarch64-linux-gnu",
        mix_env: :prod,
        source_checkout: false,
        env: %{}
      )
    end
  end
end
