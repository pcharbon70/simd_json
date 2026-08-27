defmodule SimdJson.Native.BuildError do
  @moduledoc false
  defexception [:message]
end

defmodule SimdJson.Native.BuildGuard do
  @moduledoc false

  alias SimdJson.Native.BuildError

  @project_root Path.expand("../../..", __DIR__)

  # covers: simd_json.native_build_and_abi.clean_checkout_build simd_json.native_build_and_abi.target_qualification
  defmacro assert_supported! do
    __MODULE__.validate!()
    quote(do: :ok)
  end

  @doc false
  def validate!(options \\ []) do
    root = Keyword.get(options, :root, @project_root)
    manifest = Keyword.get_lazy(options, :manifest, fn -> read_manifest!(root) end)
    target = Keyword.get_lazy(options, :target, &detected_target/0)

    validate_target!(manifest, target)
    validate_vendor!(root, manifest)
    validate_toolchain!(root, manifest, Keyword.get(options, :toolchain))

    :ok
  end

  @doc false
  def detected_target do
    :system_architecture
    |> :erlang.system_info()
    |> List.to_string()
    |> normalize_target()
  end

  @doc false
  def fingerprint(root \\ @project_root) do
    manifest = read_manifest!(root)

    manifest
    |> Keyword.fetch!(:cache_inputs)
    |> Enum.map(fn relative_path ->
      path = Path.join(root, relative_path)
      {relative_path, sha256!(path)}
    end)
    |> :erlang.term_to_binary()
    |> sha256()
  end

  defp read_manifest!(root) do
    path = Path.join(root, "native/manifest.exs")
    {manifest, _bindings} = Code.eval_file(path)

    if Keyword.keyword?(manifest) do
      manifest
    else
      fail!("native manifest must evaluate to a keyword list: #{path}")
    end
  end

  defp validate_target!(manifest, target) do
    supported_target = manifest |> Keyword.fetch!(:primary_target) |> Keyword.fetch!(:triple)

    unless target == supported_target do
      diagnostic =
        manifest
        |> Keyword.fetch!(:unsupported_target_diagnostic)
        |> String.replace("%{target}", target)

      fail!(diagnostic)
    end
  end

  defp validate_vendor!(root, manifest) do
    simdjson = Keyword.fetch!(manifest, :simdjson)
    vendor_directory = Keyword.fetch!(simdjson, :vendor_directory)

    simdjson
    |> Keyword.fetch!(:vendor_files)
    |> Enum.each(fn {relative_path, expected_sha256} ->
      path = Path.join([root, vendor_directory, relative_path])
      ensure_digest!(path, expected_sha256)
    end)

    series_path = Path.join(root, Keyword.fetch!(simdjson, :patch_series))
    declared_patches = declared_patches!(series_path)

    present_patches =
      series_path
      |> Path.dirname()
      |> Path.join("*.patch")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()

    unless Enum.sort(Map.keys(declared_patches)) == present_patches do
      fail!("undeclared or missing simdjson patch in #{Path.dirname(series_path)}")
    end

    Enum.each(declared_patches, fn {filename, expected_sha256} ->
      ensure_digest!(Path.join(Path.dirname(series_path), filename), expected_sha256)
    end)
  end

  defp declared_patches!(series_path) do
    series_path
    |> read_file!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Map.new(fn line ->
      case String.split(line, ~r/\s+/, parts: 2) do
        [sha256, filename]
        when byte_size(sha256) == 64 and filename != "" ->
          {filename, sha256}

        _other ->
          fail!("invalid simdjson patch entry in #{series_path}: #{line}")
      end
    end)
  end

  defp validate_toolchain!(root, manifest, nil) do
    actual = %{
      elixir: System.version(),
      otp: otp_version(),
      zigler: zigler_lock!(root),
      zig: zig_version!(),
      cxx: cxx_version!()
    }

    validate_toolchain!(root, manifest, actual)
  end

  defp validate_toolchain!(_root, manifest, actual) when is_map(actual) do
    beam = Keyword.fetch!(manifest, :beam)
    zigler = Keyword.fetch!(manifest, :zigler)
    zig = Keyword.fetch!(manifest, :zig)
    cxx = Keyword.fetch!(manifest, :cxx)

    unless Version.match?(actual.elixir, Keyword.fetch!(beam, :elixir_requirement)) do
      mismatch!("Elixir", Keyword.fetch!(beam, :elixir_requirement), actual.elixir)
    end

    validate_otp!(actual.otp, Keyword.fetch!(beam, :qualified_otp))

    unless actual.zigler == {
             Keyword.fetch!(zigler, :version),
             Keyword.fetch!(zigler, :hex_sha256)
           } do
      mismatch!(
        "Zigler lock",
        {Keyword.fetch!(zigler, :version), Keyword.fetch!(zigler, :hex_sha256)},
        actual.zigler
      )
    end

    ensure_equal!("Zig", Keyword.fetch!(zig, :version), actual.zig)
    ensure_equal!("Zig C++ compiler", Keyword.fetch!(cxx, :qualified_version), actual.cxx)
  end

  defp validate_otp!(actual, minimum) do
    with {:ok, [actual_major | _] = actual_parts} <- numeric_version(actual),
         {:ok, [minimum_major | _] = minimum_parts} <- numeric_version(minimum),
         true <- actual_major == minimum_major,
         true <- actual_parts >= minimum_parts do
      :ok
    else
      _other -> mismatch!("Erlang/OTP", "#{minimum} within major release", actual)
    end
  end

  defp numeric_version(version) do
    parts = version |> String.split(".") |> Enum.map(&Integer.parse/1)

    if Enum.all?(parts, &match?({_, ""}, &1)) do
      {:ok, Enum.map(parts, &elem(&1, 0))}
    else
      :error
    end
  end

  defp zigler_lock!(_root) do
    case Map.fetch(Mix.Dep.Lock.read(), :zigler) do
      {:ok, {:hex, :zigler, version, _inner_checksum, _managers, _dependencies, _repo, checksum}} ->
        {version, checksum}

      other ->
        fail!("Zigler must be an immutable Hex lock entry, got: #{inspect(other)}")
    end
  end

  defp zig_version! do
    zig = Zig.Command.executable_path()

    case System.cmd(zig, ["version"], stderr_to_stdout: true) do
      {version, 0} -> String.trim(version)
      {output, status} -> fail!("cannot query Zig version (#{status}): #{String.trim(output)}")
    end
  end

  defp cxx_version! do
    zig = Zig.Command.executable_path()

    case System.cmd(zig, ["c++", "--version"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/clang version ([0-9]+\.[0-9]+\.[0-9]+)/, output) do
          [_, version] -> version
          _other -> fail!("cannot identify the Zig-bundled C++ compiler: #{String.trim(output)}")
        end

      {output, status} ->
        fail!("cannot query the Zig-bundled C++ compiler (#{status}): #{String.trim(output)}")
    end
  end

  defp otp_version do
    otp_release = :erlang.system_info(:otp_release) |> List.to_string()
    path = Path.join([to_string(:code.root_dir()), "releases", otp_release, "OTP_VERSION"])

    case File.read(path) do
      {:ok, version} -> String.trim(version)
      {:error, _reason} -> otp_release
    end
  end

  defp normalize_target(raw) do
    cond do
      Regex.match?(~r/^x86_64-[^-]+-linux-gnu/, raw) -> "x86_64-linux-gnu"
      Regex.match?(~r/^aarch64-[^-]+-linux-gnu/, raw) -> "aarch64-linux-gnu"
      Regex.match?(~r/^x86_64-apple-darwin/, raw) -> "x86_64-macos"
      Regex.match?(~r/^aarch64-apple-darwin/, raw) -> "aarch64-macos"
      true -> raw
    end
  end

  defp ensure_digest!(path, expected_sha256) do
    actual_sha256 = sha256!(path)

    unless actual_sha256 == expected_sha256 do
      fail!(
        "native vendor checksum mismatch for #{path}: " <>
          "expected=#{expected_sha256} actual=#{actual_sha256}"
      )
    end
  end

  defp sha256!(path), do: path |> read_file!() |> sha256()

  defp sha256(bytes), do: bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  defp read_file!(path) do
    case File.read(path) do
      {:ok, bytes} -> bytes
      {:error, reason} -> fail!("required native build input is unavailable: #{path} (#{reason})")
    end
  end

  defp ensure_equal!(name, expected, actual) do
    unless expected == actual, do: mismatch!(name, expected, actual)
  end

  defp mismatch!(name, expected, actual) do
    fail!(
      "native build guard rejected #{name}: expected=#{inspect(expected)} actual=#{inspect(actual)}"
    )
  end

  defp fail!(message), do: raise(BuildError, message: message)
end
