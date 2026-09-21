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

  test "a failed artifact download is actionable and installs no NIF" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])

    {:ok, {_address, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, _request} = :gen_tcp.recv(socket, 0)

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
          )

        :gen_tcp.close(socket)
      end)

    destination =
      Path.join(System.tmp_dir!(), "simd-json-download-#{System.unique_integer()}.so")

    on_exit(fn ->
      :gen_tcp.close(listener)
      File.rm(destination)
    end)

    source = {:web, "http://127.0.0.1:#{port}/missing.so", String.duplicate("0", 64)}

    assert_raise BuildError, ~r/download failed with HTTP 503/, fn ->
      Precompiled.install!(source, destination)
    end

    Task.await(server)
    refute File.exists?(destination)
  end
end
