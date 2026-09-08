# Contributing

Contributions are welcome when they preserve the documented ownership,
bounded-execution, redaction, and source-build contracts.

## Development environment

The supported development and release target is Ubuntu 24.04 x86-64 with OTP
27.3, Elixir 1.18.4, and Zig 0.16.0. Other environments may be useful for
experiments, but their success does not establish package support.

Bootstrap the repository with:

```console
mix deps.get
mix zig.get --version 0.16.0
MIX_ENV=test bash scripts/ci/bootstrap_release_tools.sh
```

## Before opening a pull request

Run the focused tests for the behavior you changed, then the ordinary project
gates:

```console
mix format --check-formatted
mix test
mix spec.next
mix spec.check --base origin/main
```

The repository's [SpecLed guide](https://github.com/pcharbon70/simd_json/blob/main/.spec/AGENTS.md)
explains when current-truth specifications and decisions must change. Keep
commits focused, add executable regression evidence for behavior changes, and
do not commit generated NIFs, Zigler intermediates, caches, qualification
outputs, credentials, or private data.

Changes to native code, toolchain pins, ABI, worker lifecycle, supported
targets, package inventory, or release inputs also require the applicable
native and release qualification commands documented in
[native/README.md](native/README.md) and the
[CI policy](docs/releases/ci-policy.md). A stale qualification fingerprint is a
required failure until the complete matrix has passed and its evidence is
refreshed.

Security reports must follow [SECURITY.md](SECURITY.md), not the public issue or
pull-request workflow.
