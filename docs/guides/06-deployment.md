# 06 — Deployment and Native Delivery

Most users install SimdJson like any other Hex dependency. This guide starts
with that normal path, then covers offline environments and the opt-in source
build used by maintainers and auditors.

## Start with the precompiled package

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:simd_json, "~> 1.0.0"}
  ]
end
```

Then compile:

```sh
mix deps.get
mix compile
```

On the supported target, compilation downloads the versioned NIF from the
matching GitHub release and verifies its SHA-256 checksum before loading it.
The approved digests are recorded in `native/precompiled/checksums.exs`.
Ordinary consumers do not need Zig, Zigler, or a C++ compiler. They also do
not need a system simdjson package.

## Confirm the deployed library works

Run a small binary operation after deployment:

```elixir
{:ok, %{"ready" => true}} = SimdJson.decode(~s({"ready":true}))
```

If your application uses file input, check that path too:

```elixir
File.write!("account.json", ~s({"account":{"id":7}}))

{:ok, %{id: 7}} =
  SimdJson.select_file("account.json", id: ["account", "id"])
```

These checks exercise both eager result conversion and native file-backed
operation.

## Supported target

The qualified release target is Ubuntu 24.04 LTS, x86-64, with glibc 2.39.
Other systems are experimental or unsupported until they pass equivalent ABI,
sanitizer, scheduler, lifecycle, benchmark, and shutdown checks.

An `Unsupported native target` error means no qualified precompiled artifact
matches the running system. Do not bypass target or checksum validation.

## Install without network access

In a connected environment, obtain the approved release asset using your
normal artifact-mirroring process. Transfer it to the offline build machine,
then point compilation at the local file:

```sh
export SIMD_JSON_PRECOMPILED_PATH=/approved/artifacts/simd_json_nif.so
mix compile
```

The file must still match the package checksum. The environment variable
changes where the asset is read from; it does not disable verification.

## Build from source when you intend to

Source compilation is for maintainers, auditors, and environments being
explicitly qualified. It is not an automatic fallback when a release asset is
missing or invalid.

To opt in:

```sh
export SIMD_JSON_BUILD_FROM_SOURCE=1
mix zig.get --version 0.16.0
mix compile
```

The build uses Zig 0.16.0, bundled Clang/LLVM 21.1.0 and libc++, C++17, and the
vendored simdjson source. It never links to a system simdjson installation.

If the build environment requires an explicit writable cache, set
`ZIG_GLOBAL_CACHE_DIR` before compiling.

## Troubleshoot safely

- If the target is unsupported, use a supported deployment or deliberately
  qualify a source build.
- If checksum verification fails, replace the asset from the trusted release;
  do not disable the check.
- If an offline build cannot find the asset, verify that
  `SIMD_JSON_PRECOMPILED_PATH` names the file itself, not its directory.
- If a source build cannot find Zig, rerun the pinned `mix zig.get` command and
  confirm the cache is writable.

Previous: [05 — Errors, Limits, and Performance](05-errors-limits-performance.md)  
Return to: [01 — Getting Started](01-getting-started.md)
