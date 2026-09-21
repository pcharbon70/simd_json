defmodule SimdJson.Native.Precompiled do
  @moduledoc false

  # covers: simd_json.release.precompiled_delivery

  alias SimdJson.Native.BuildError
  alias SimdJson.Native.BuildGuard

  @project_root Path.expand("../../..", __DIR__)
  @checksums_path "native/precompiled/checksums.exs"
  @source_url "https://github.com/pcharbon70/simd_json"
  @source_override "SIMD_JSON_BUILD_FROM_SOURCE"
  @local_artifact "SIMD_JSON_PRECOMPILED_PATH"
  @local_checksum "SIMD_JSON_PRECOMPILED_SHA256"

  @doc false
  def resolve!(options \\ []) do
    root = Keyword.get(options, :root, @project_root)
    version = Keyword.get_lazy(options, :version, &project_version/0)
    target = Keyword.get_lazy(options, :target, &BuildGuard.detected_target/0)
    mix_env = Keyword.get_lazy(options, :mix_env, &Mix.env/0)

    source_checkout =
      Keyword.get_lazy(options, :source_checkout, fn -> source_checkout?(root) end)

    env = Keyword.get(options, :env, System.get_env())

    validate_runtime!(root, target)

    cond do
      truthy?(Map.get(env, @source_override)) ->
        nil

      mix_env == :test ->
        nil

      path = present(Map.get(env, @local_artifact)) ->
        checksum = required_env!(env, @local_checksum)
        verify_local!(path, checksum)

      source_checkout ->
        nil

      true ->
        web_artifact!(root, version, target)
    end
  end

  @doc false
  def asset_name(version, target) do
    "simd_json-v#{version}-#{target}.so"
  end

  @doc false
  def install!(source, destination) do
    contents = artifact_contents!(source)
    expected_checksum = source_checksum!(source)
    actual_checksum = sha256(contents)

    unless actual_checksum == expected_checksum do
      fail!(
        "precompiled NIF checksum mismatch: expected=#{expected_checksum} " <>
          "actual=#{actual_checksum}"
      )
    end

    File.mkdir_p!(Path.dirname(destination))
    temporary = destination <> ".tmp-#{System.unique_integer([:positive])}"

    try do
      File.write!(temporary, contents, [:binary])
      File.rename!(temporary, destination)
    after
      File.rm(temporary)
    end

    destination
  end

  @doc false
  def checksums(root \\ @project_root) do
    path = Path.join(root, @checksums_path)
    {checksums, _bindings} = Code.eval_file(path)

    if is_map(checksums), do: checksums, else: fail!("invalid precompiled checksum manifest")
  rescue
    error in File.Error ->
      fail!("cannot read precompiled checksum manifest: #{Exception.message(error)}")
  end

  defp web_artifact!(root, version, target) do
    checksum =
      root
      |> checksums()
      |> get_in([version, target])
      |> validate_checksum!(version, target)

    asset = asset_name(version, target)
    url = "#{@source_url}/releases/download/v#{version}/#{asset}"
    {:web, url, checksum}
  end

  defp artifact_contents!(path) when is_binary(path), do: File.read!(path)

  defp artifact_contents!({:web, url, _checksum}) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), []}

    http_options = [
      autoredirect: true,
      ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
    ]

    case :httpc.request(:get, request, http_options, body_format: :binary) do
      {:ok, {{_http_version, status, _reason}, _headers, body}}
      when status in 200..299 ->
        body

      {:ok, {{_http_version, status, reason}, _headers, _body}} ->
        fail!("precompiled NIF download failed with HTTP #{status}: #{reason}")

      {:error, reason} ->
        fail!("precompiled NIF download failed: #{inspect(reason)}")
    end
  end

  defp source_checksum!(path) when is_binary(path), do: path |> File.read!() |> sha256()
  defp source_checksum!({:web, _url, checksum}), do: checksum

  defp verify_local!(path, expected_checksum) do
    checksum = validate_checksum!(expected_checksum, "local", BuildGuard.detected_target())
    expanded = Path.expand(path)

    unless File.regular?(expanded) do
      fail!("precompiled NIF does not exist: #{expanded}")
    end

    actual_checksum = expanded |> File.read!() |> sha256()

    unless actual_checksum == checksum do
      fail!("precompiled NIF checksum mismatch: expected=#{checksum} actual=#{actual_checksum}")
    end

    expanded
  end

  defp validate_runtime!(root, target) do
    {manifest, _bindings} = Code.eval_file(Path.join(root, "native/manifest.exs"))
    supported = manifest |> Keyword.fetch!(:primary_target) |> Keyword.fetch!(:triple)

    unless target == supported do
      fail!("no qualified precompiled NIF for target #{target}; supported target is #{supported}")
    end

    :ok
  end

  defp validate_checksum!(checksum, _version, _target)
       when is_binary(checksum) and byte_size(checksum) == 64 do
    case Base.decode16(checksum, case: :lower) do
      {:ok, _digest} -> checksum
      :error -> fail!("precompiled NIF checksum must be 64 lowercase hexadecimal characters")
    end
  end

  defp validate_checksum!(_checksum, version, target) do
    fail!(
      "no qualified precompiled NIF checksum for version #{version} and target #{target}; " <>
        "set #{@source_override}=1 to perform the documented source build"
    )
  end

  defp project_version do
    Mix.Project.config() |> Keyword.fetch!(:version)
  end

  defp source_checkout?(root), do: File.exists?(Path.join(root, ".git"))

  defp truthy?(value), do: value in ["1", "true"]
  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value), do: value

  defp required_env!(env, name) do
    case present(Map.get(env, name)) do
      nil -> fail!("#{name} is required with #{@local_artifact}")
      value -> value
    end
  end

  defp sha256(contents) do
    :sha256
    |> :crypto.hash(contents)
    |> Base.encode16(case: :lower)
  end

  defp fail!(message), do: raise(BuildError, message: message)
end
