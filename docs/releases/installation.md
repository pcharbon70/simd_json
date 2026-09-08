# Installation and Native Build

SimdJson 0.1.0 is a source-distributed Elixir package. Installing it compiles
the bundled simdjson C++ source into a NIF for the current BEAM and target; the
first release does not ship precompiled NIF artifacts.

## Add the dependency

Add the exact first-release series to the consumer project's `mix.exs`:

```elixir
defp deps do
  [
    {:simd_json, "~> 0.1.0"}
  ]
end
```

Fetch dependencies before acquiring Zig so the `mix zig.get` task is
available, then compile:

```console
mix deps.get
mix zig.get --version 0.16.0
mix compile
```

Dependency fetching requires access to Hex. Native compilation itself uses
the simdjson 4.6.9 snapshot included in the package and never discovers a
system simdjson installation or downloads simdjson source.

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
| Zigler | Package-pinned Hex release 0.16.0 |
| Zig and C++ toolchain | Zig 0.16.0 with bundled Clang/LLVM 21.1.0 and libc++ |
| simdjson | Package-vendored release 4.6.9 |

Zig compiles and links the C++17 translation units. A separate system `g++`,
system simdjson package, or dynamically linked C++ standard library is not
selected by the qualified build. The resulting NIF uses the target's glibc and
BEAM NIF loader. The host needs ordinary CA certificates and network access
while fetching Hex packages and Zig; those are not needed to retrieve
simdjson during compilation.

simdjson runtime dispatch may select its qualified `haswell`, `westmere`, or
`fallback` implementation for the host CPU. AVX-512/Ice Lake is disabled by
the pinned profile. Do not copy a compiled NIF between machines or BEAM
toolchains as a substitute for compiling the package locally.

Other Linux distributions, libc implementations, architectures, operating
systems, OTP/Elixir lines, Zig releases, and CPU dispatch paths are
experimental or unsupported. Compilation success alone does not promote a
target to supported status. See the complete [support policy](support.md).

## Compile time and caches

The initial `mix compile` performs C++ and Zig compilation and is materially
slower than compiling a pure-Elixir dependency; budget several minutes on a
small development or CI host. Later unchanged builds reuse normal Mix and Zig
caches and should be substantially faster.

- Mix stores application build output under `_build/<mix-env>` and fetched
  dependencies under `deps` in the consumer project.
- `mix zig.get` stores the qualified executable below
  `${XDG_CACHE_HOME:-$HOME/.cache}/zigler/`; on the supported target the
  executable ends in `zig-x86_64-linux-0.16.0/zig`.
- Zig uses its normal global and local caches. CI and qualification may set
  `ZIG_GLOBAL_CACHE_DIR`, `ZIG_LOCAL_CACHE_DIR`, and `MIX_BUILD_PATH` to
  isolate them; consumers normally do not need to set these variables.

Changing the NIF source, toolchain, target, Mix environment, or build mode can
correctly trigger a full rebuild.

## Troubleshooting

Record tool and dependency identity before clearing any cache:

```console
elixir --version
mix --version
mix deps.tree
mix zig.get --version 0.16.0
${XDG_CACHE_HOME:-$HOME/.cache}/zigler/zig-x86_64-linux-0.16.0/zig version
```

Common diagnostics have direct remedies:

- **Missing or wrong Zig:** rerun `mix zig.get --version 0.16.0`, then
  `mix deps.compile simd_json --force`.
- **Wrong Elixir or OTP:** use Elixir 1.18.4 on OTP 27.3; the build guard
  rejects unqualified combinations rather than silently producing a NIF.
- **Unsupported native target:** compare the detected triple in the error with
  the [supported target](support.md#qualified-target). There is no generic or
  system-library fallback.
- **Stale or corrupted dependency output:** after recording diagnostics, run
  `mix deps.clean simd_json --build`, `mix deps.get`, and `mix compile`.
- **Deployment cannot load the NIF:** compile on the deployment target with
  its intended OTP/Elixir installation and inspect the original loader error;
  do not reuse another host's `_build` directory.

If the problem remains, open an issue through the repository's configured
[issue tracker](https://github.com/pcharbon70/simd_json/issues) with the command
output, target triple, and complete build error. Never attach private JSON
payloads, credentials, or production data.
