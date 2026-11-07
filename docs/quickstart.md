# Quickstart

Start with a fixture before you connect a provider.
Pin Generate to one exact commit of `https://github.com/voidmeld/generate.git`.
Record the commit and tree hash in your repository.
Require the packages under `src`.

## Run an example

After `rokit install`, run these commands from the repository root:

```console
lute run tools/generate-check.luau examples
lute run examples/quickstart.generate.luau
lute run examples/accepted-manifest.generate.luau
```

The checker reads briefs. It does not execute them.
The [quickstart](../examples/quickstart.generate.luau) prints a plan ID and fingerprint.
It runs no stage. The [modular wall](../examples/modular-wall.generate.luau) also shows planning.
The [accepted manifest](../examples/accepted-manifest.generate.luau) uses fixture effects.
It collects a review decision and selects delivery. It creates no real media.

## Inspect a result

The [API setup](api.md#shared-setup) supplies `Generate`, `Media` and `Consumer` in these fragments.
Use a typed brief before compiling a plan:

```luau
local plan = Generate.plan(brief, {
    { id = "candidate", operation = "generate" },
    { id = "review", operation = "review", dependsOn = { "candidate" } },
})
assert(plan.briefId == brief.id)
```

Check failures before consuming measurements or continuing a stage:

```luau
local outcome = Media.wav.measure("invalid bytes")
assert(not outcome.ok)
local findings = Consumer.scanSource("fixture.generate.luau", "return {}")
assert(#findings > 0)
```

Run the success and refusal cases with `lute run tools/gate.luau --file tests/core.verify.luau`.
Use [the API](api.md) for return fields and recovery rules.

## Connect a production job

1. Declare the asset with [Generate.brief](api.md#generatebrief).
2. Declare its stages with [Generate.plan](api.md#generateplan).
3. Supply a host through an [adapter](adapters.md).
4. Pass consumer authority to [Generate.execute](api.md#generateexecute).
5. Retain the candidate under the [native retention rules](native-codegen.md).
6. Measure spatial assets against `constraints.maxSize`.
7. Preserve required rigs, cages and animation clips.
8. Run the technical checks.
9. Review the exact candidate under the brief contract.
10. Use [continueReview](api.md#generatecontinuereview) if a decision is missing.
11. Select accepted artifacts with [manifest](api.md#generatemanifest).
12. Bind separate authority before publication.
13. Verify the delivered content in the consumer runtime.

The [production skill](../.agents/skills/generate/SKILL.md) gives the procedure for an assigned stage.
The [architecture](architecture.md) lists the public packages.

## Recover without repeating production

Keep the record of a held or ambiguous delivery.
Use the status or attach calls in [direct delivery](api.md#direct-delivery).
Do not generate or upload again because review or readback is missing.
Use the [README](../README.md#validate) for check commands.
Read the [evidence limits](evidence.md) before you make a production claim.
