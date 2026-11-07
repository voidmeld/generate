# Generate maintainer guide

Generate is a content generation library for Luau. It owns production plans, candidate records and review bindings.
Consumers own art direction, tools, rights, credentials, destinations, acceptance and deployment.
The [README](README.md) maps the tasks.

First action: find the affected area in [the API](docs/api.md), then read its linked test and current consumers.
Read only the next required contract. Read [architecture](docs/architecture.md) for a boundary change.
For a first use, follow the [quickstart](docs/quickstart.md).

This file owns the contribution rules. Each fact has one owning document.

## Rules

- Write tools in Lute Luau. Start every maintained file with `--!strict`. Use no explicit `any`, type assertions or type-check suppressions.
- Core contains data and injected effects. Core has no providers, hosts, I/O, clocks, credentials, destinations or internals of another library. Sort canonical data. Use deterministic fixtures.
- Bind exactly one decision to exact candidate bytes, evidence and rubric. Independence defaults to required. An explicit optional contract lets a producer inspect intermediate inputs under consumer policy. A score cannot override a rejection. Unknown required rights or lineage block delivery.
- Declare mutation and recovery before execution. Use one granted attempt, authenticated readback and explicit uncertainty. A refusal grants no alternate route.
- Keep native originals before cleanup, as [native retention](docs/native-codegen.md) states. Preserve real rig, cage, animation and audio capabilities. A prompt or hash is not a model.
- Write every test, gate, benchmark and evidence record with the pinned Verify dependency: Verify cases, one declared gate and `Benchmark.case`. Do not write a second runner, matcher, verdict or report.
- Keep code that a current consumer, a rights obligation or a recovery obligation needs. Before you remove code, inspect its dynamic, CLI and native consumers.
- Remove superseded code, tests and references together. Never remove a known-defect test to obtain a pass.
- Keep consumer identity and comparisons with other products out of this repository. Keep exact dependency, API, tool and license identifiers.
- Add no explanatory source comments. Keep tool directives and required license notices.

## Validate

- Change the owning contract together with the implementation.
- Test public consumers and meaningful refusal and recovery paths. Report the [evidence limits](docs/evidence.md).
- For a changed brief, run `lute run tools/generate-check.luau <path.generate.luau>`.
- For execution hot-path changes, follow [benchmarks](docs/benchmarks.md).
- During edits, use `lute run tools/gate.luau --file tests/core.verify.luau` or `--tier fast`. The gate owns all selectors.
- After adding or removing a specification, run `lute run tools/check-test-manifest.luau --write`.
- Commit the candidate. Run `lute run tools/gate.luau` on the clean HEAD, including its fresh-clone check.
- Do not change verified bytes before integration.
- Reuse evidence while its inputs stay unchanged. Use existing tools and batch independent work.

## Repository

Changes to this library use a pull request to `main` and the required `Gate` check. Do not push directly to `main` or bypass a failing check.

Use author and committer `voidmeld <158495725+voidmeld@users.noreply.github.com>`. Add no attribution trailers.
Keep history append-only unless the repository owner authorizes a rewrite.
