# Installation and Native Delivery

SimdJson 0.1.0 ships its Elixir code and native sources through Hex and one
qualified production NIF as an immutable GitHub release asset. On the supported
target, Mix downloads that asset and verifies its committed SHA-256 digest
before installing or loading it. Ordinary consumers do not need Zig, Zigler, a
C++ compiler, or a system simdjson installation.

## Add the dependency

Add the first-release series to the consumer project's `mix.exs`:

```elixir
defp deps do
  [
    {:simd_json, "~> 0.1.0"}
  ]
end
```

Fetch and compile:

```console
mix deps.get
mix compile
```

Dependency fetching requires access to Hex. The first native compile also
requires HTTPS access to the matching GitHub release unless the verified asset
is supplied through the documented local override. The NIF is named
`simd_json-v0.1.0-x86_64-linux-gnu.so`; its expected digest is shipped in
`native/precompiled/checksums.exs`. A missing release, failed download,
unsupported target, or checksum mismatch stops compilation before native code
is installed or loaded.

## Smoke test the three workflows

Start `iex -S mix` in the consumer project and run:

```elixir
{:ok, %{"ready" => true}} = SimdJson.decode(~s({"ready":true}))

{:ok, %{id: 7}} =
  SimdJson.select(~s({"account":{"id":7}}), id: ["account", "id"])

[%{id: 1}, %{id: 2}] =
  SimdJson.stream(~s({"rows":[{"id":1},{"id":2}]}),
    path: ["rows"],
    fields: [id: ["id"]],
    batch_size: 1
  )
  |> Enum.to_list()
```

These checks cover eager decode, sparse projection, and demand-driven batched
streaming through the production bounded worker pool.

## Qualified prerequisites

The supported target is deliberately narrow:

| Input | Required or qualified value |
| --- | --- |
| Operating system | Ubuntu 24.04 LTS, x86-64 |
| libc and target ABI | glibc 2.39, `x86_64-linux-gnu` |
| Erlang/OTP | 27.3 |
| Elixir | 1.18.4; package requirement `~> 1.18.4` |
| Hex and Rebar | Current installations provided through Mix |
| Precompiled NIF | Versioned, target-specific GitHub release asset with a package-pinned SHA-256 digest |
| Zigler | Not required for supported consumers; optional exact release 0.16.0 for qualified source builds |
| Zig and C++ toolchain | Not required for supported consumers; source builds use Zig 0.16.0 with bundled Clang/LLVM 21.1.0 and libc++ |
| simdjson | Package-vendored release 4.6.9 used to reproduce the asset |

The release NIF was built from the packaged C++17 and Zig sources with the
qualified toolchain. A separate system `g++`, system simdjson package, or
dynamically linked C++ standard library is not selected. The NIF uses the
target's glibc and BEAM NIF loader. The host needs ordinary CA certificates and
network access while fetching Hex packages and the release asset; it does not
retrieve simdjson separately.

simdjson runtime dispatch may select its qualified `haswell`, `westmere`, or
`fallback` implementation for the host CPU. AVX-512/Ice Lake is disabled by
the pinned profile. Do not copy an unverified NIF between applications or
substitute another target's binary for the checksummed release asset.

Other Linux distributions, libc implementations, architectures, operating
systems, OTP/Elixir lines, and CPU dispatch paths are experimental or
unsupported. Compilation success alone does not promote a target to supported
status. See the complete [support policy](support.md).

## Compile time, downloads, and caches

The initial `mix compile` downloads and verifies the release NIF, then compiles
the Elixir modules. Later unchanged builds reuse normal Mix output. Cleaning
the dependency build removes the installed NIF, so the next compile downloads
and verifies it again.

- Mix stores application build output under `_build/<mix-env>` and fetched
  dependencies under `deps` in the consumer project.
- `SIMD_JSON_PRECOMPILED_PATH` may point to an already downloaded candidate
  for offline or mirrored builds, but `SIMD_JSON_PRECOMPILED_SHA256` must also
  contain its independently obtained 64-character lowercase digest. The
  package rejects either value on its own and never trusts the file name.
- Maintainer source builds use normal Zig caches. Qualification may set
  `ZIG_GLOBAL_CACHE_DIR`, `ZIG_LOCAL_CACHE_DIR`, and `MIX_BUILD_PATH` to isolate
  them.

## Explicit source build for maintainers

Auditing or reproducing the native asset requires the pinned compiler stack.
Add `{:zigler, "== 0.16.0", runtime: false}` to the consuming project's
dependencies, run `mix zig.get --version 0.16.0`, and compile with
`SIMD_JSON_BUILD_FROM_SOURCE=1`. Source builds remain limited to the same
qualified target and validate the pinned Elixir, OTP, Zigler, Zig, compiler,
flags, vendored simdjson, and qualification fingerprint. They are not an
automatic fallback for a missing or invalid release asset.

## Troubleshooting

Record runtime, dependency, and artifact identity before clearing any cache:

```console
elixir --version
mix --version
mix deps.tree
sha256sum _build/*/lib/simd_json/priv/lib/Elixir.SimdJson.Native.BuildSmoke.so
```

Common diagnostics have direct remedies:

- **Release asset unavailable:** verify HTTPS access to the exact `v0.1.0`
  GitHub release and retry `mix deps.compile simd_json --force`; for an
  approved mirror, supply both local override variables above.
- **Checksum mismatch:** stop and compare the downloaded asset with
  `native/precompiled/checksums.exs`. Never disable verification or replace a
  published asset in place.
- **Wrong Elixir or OTP:** use Elixir 1.18.4 on OTP 27.3; the loader rejects
  unqualified combinations rather than silently installing a NIF.
- **Unsupported native target:** compare the detected triple in the error with
  the [supported target](support.md#qualified-target). There is no generic,
  source-build, or system-library fallback.
- **Stale or corrupted dependency output:** after recording diagnostics, run
  `mix deps.clean simd_json --build`, `mix deps.get`, and `mix compile`.
- **Deployment cannot load the NIF:** use the qualified OTP/Elixir and glibc
  target, preserve the original loader error, and do not reuse another
  application's `_build` directory.

If the problem remains, open an issue through the repository's configured
[issue tracker](https://github.com/pcharbon70/simd_json/issues) with the command
output, target triple, and complete build error. Never attach private JSON
payloads, credentials, or production data.
