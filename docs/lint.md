# Lint checks

This page names the source and brief lint checks, the command that runs each check and what each check reports.

## Source

Run `lute lint -c lint.config.luau` to check the repository source. Lute reports ordinary Luau defects.
The pinned Verify `checks` package supplies the CST rule banning ambient `_G` and `shared` authority.
Repository checks use `tools/checks-config.luau` and Generate policy in `tools/checks-policy.luau`.

The fast gate runs `tools/check-spec-style.luau` through Verify's `Checks.specStyle`.
Specs bind `describe`, `it` and `expect` once from `Bdd.create` and use those local functions.
The selection excludes `tests/adapters.lute.verify.luau`, which tests Verify's raw harness API.

The gate analyzes `src`, `tests`, `tools`, `bench`, `examples`, `lint.config.luau` and the dependency lock in `.luaurc` strict mode.
Standalone fixtures and tests also declare `--!strict`.
Run the full gate on final source changes, as [AGENTS](../AGENTS.md) requires.

## Briefs

Run `lute run tools/generate-check.luau <directory-or-brief.generate.luau>` to check a brief. The checker checks these items:

- identity
- review evidence
- unsafe execution and credential spelling
- publication rollback
- spatial bounds with an explicit unit (`constraints.maxSize = { x, y, z, unit = "m" }`)

The default ruleset is generic. It names no host.
To add the Roblox ruleset, pass `--ruleset=roblox`. The ruleset checks these items:

- raw Roblox IDs
- ambient or persisted Studio selection
- `GenerationService:` spelling
- a size in `maxSizeStuds`

Call `Consumer.scanSource(path, source, { "roblox" })` for the same selection in code.
The gate scans `examples` with the default ruleset.

The checker reads source text through `Consumer.scanSource`. It does not execute a brief, inspect candidate bytes or contact a provider.
A clean scan is not review, publication or runtime evidence.
Use the [evidence map](evidence.md) for the boundary that you must exercise.
