# Deployment and Native Delivery

## Supported target

The qualified release target is Ubuntu 24.04 LTS x86-64 with glibc 2.39.
Other platforms are experimental or unsupported until equivalent package,
ABI, sanitizer, scheduler, lifecycle, benchmark, and shutdown qualification
exists.

## Precompiled installation

Ordinary consumers do not need Zig, Zigler, a C++ compiler, or a system simdjson package:

```elixir
def deps do
  [
    {:simd_json, "~> 0.1.0"}
  ]
end
```

```sh
mix deps.get
mix compile
```

Compilation downloads the versioned NIF from the matching GitHub release and
verifies its SHA-256 digest against `native/precompiled/checksums.exs`. A
missing, unsupported, corrupt, or replaced artifact fails before native code
is loaded.

For an offline build, place the approved asset in a local path and set
`SIMD_JSON_PRECOMPILED_PATH` to that file before `mix compile`.

## Optional source build

Maintainers and auditors can explicitly build from the packaged sources:

```sh
export SIMD_JSON_BUILD_FROM_SOURCE=1
mix zig.get --version 0.16.0
mix compile
```

The source build uses Zig 0.16.0, the bundled Clang/LLVM 21.1.0 and libc++,
C++17, and the vendored simdjson source. It does not use a system simdjson
package. Set `ZIG_GLOBAL_CACHE_DIR` when the build environment requires an
explicit writable cache location.

Source compilation is an opt-in maintainer path, not a fallback for a missing
or invalid release asset.

## Runtime smoke check

After deployment, verify both eager and native file-backed operation:

```elixir
{:ok, %{"ready" => true}} = SimdJson.decode(~s({"ready":true}))

{:ok, %{id: 7}} =
  SimdJson.select_file("account.json", id: ["account", "id"])
```

An `Unsupported native target` error means the running system has no qualified
precompiled asset. Do not bypass checksum or target validation; use the
explicit source-build path only when you intend to qualify that environment.
