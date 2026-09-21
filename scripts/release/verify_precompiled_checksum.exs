case System.argv() do
  [artifact, version, target, manifest] ->
    {checksums, _bindings} = Code.eval_file(manifest)
    expected = get_in(checksums, [version, target])

    actual =
      artifact
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    cond do
      !is_binary(expected) ->
        IO.puts(:stderr, "precompiled checksum is not recorded for #{version} #{target}")
        System.halt(1)

      expected != actual ->
        IO.puts(
          :stderr,
          "precompiled checksum mismatch: expected=#{expected} actual=#{actual}"
        )

        System.halt(1)

      true ->
        IO.puts("precompiled checksum verified: #{actual}")
    end

  _other ->
    IO.puts(
      :stderr,
      "usage: verify_precompiled_checksum.exs ARTIFACT VERSION TARGET MANIFEST"
    )

    System.halt(64)
end
