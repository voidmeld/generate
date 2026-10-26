# Lint checks

## Source

Run `lute lint -c lint.config.luau` to check source.
Lute reports Luau defects. Verify checks forbid ambient `_G` and `shared` authority.
`tools/checks-config.luau` selects checks. `tools/checks-policy.luau` defines Generate policy.

The fast gate runs Verify `Checks.specStyle` through `tools/check-spec-style.luau`.
Specifications bind `describe`, `it` and `expect` once from `Bdd.create`.
The check excludes `tests/adapters.lute.verify.luau`, which tests the raw Verify API.

The gate analyzes `src`, `tests`, `tools`, `bench`, `examples`, `lint.config.luau` and the dependency lock.
It uses strict mode from `.luaurc`. Fixtures and tests also declare `--!strict`.
Follow the [contributor guide](../AGENTS.md) for final checks.

## Briefs

Run `lute run tools/generate-check.luau <directory-or-brief.generate.luau>`.
The checker reads identity, review evidence, unsafe execution, credential names and publication rollback.
It checks spatial bounds with an explicit unit: `constraints.maxSize = { x, y, z, unit = "m" }`.

The default rules name no host. Add `--ruleset=roblox` to check Roblox rules.
These rules check raw Roblox IDs, stored Studio selection, `GenerationService:` and `maxSizeStuds`.
Call `Consumer.scanSource(path, source, { "roblox" })` for the same checks in code.
The gate scans `examples` with the default rules.

The checker reads source through `Consumer.scanSource`. It does not execute briefs or inspect candidate bytes.
A clean scan does not prove review, publication or runtime results.
Use the [evidence map](evidence.md) to select the required check.
