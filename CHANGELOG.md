# Changelog

Generate follows [semantic versioning](https://semver.org). While the version is `0.x`, a minor
release may change a public contract.

## 0.1.1

- The package publishes the consumer skill (`.agents/skills/generate`).
- Verify, the development dependency, moves to 0.1.1.

## 0.1.0

- First versioned release. Generate is a `lute pkg` package: `pkg.luau` declares it, and
  consumers install it with `lute pkg install --vendor`.
- Verify is a development dependency pinned in `pkg.luau`; the custom dependency lock and sync
  script are gone.
- Requires Lute `1.0.1-nightly.20261120` or newer.
