# Getting started

Use Generate when a content job needs a declared brief, tool execution, retained output and review.
Before you connect a real provider, start with a fixture.

## Run an example

From the repository root, run:

```console
lute run tools/generate-check.luau examples
lute run examples/quickstart.generate.luau
lute run examples/accepted-manifest.generate.luau
```

The checker scans the authored briefs. It does not run them and does not contact a provider.
The [quickstart brief](../examples/quickstart.generate.luau) and the
[modular-wall brief](../examples/modular-wall.generate.luau) are planning examples.
They print a plan identity and run no stage.
The [accepted-manifest example](../examples/accepted-manifest.generate.luau) runs injected fixture effects,
collects a review decision and selects delivery. It produces no real media and publishes nothing.

## Connect a production job

1. Declare the intent, semantic identity, constraints, review and provenance of the asset with [Generate.brief](api.md#generatebrief).
2. Declare stages with [Generate.plan](api.md#generateplan).
3. Supply a host through the required [adapter](adapters.md). Pass the consumer authority to [Generate.execute](api.md#generateexecute).
4. Retain the candidate under [native retention](native-codegen.md). Measure prepared spatial assets against `constraints.maxSize`. Preserve required rigs, cages and clips. Run the technical checks.
5. Review the exact candidate under the contract of the brief. If a decision is missing, use [continueReview](api.md#generatecontinuereview). Do not repeat production.
6. Select the accepted artifacts with [manifest](api.md#generatemanifest).
7. Publication needs its own bound authority. After delivery, the consumer verifies the delivered content in its runtime.

The [production skill](../.agents/skills/generate/SKILL.md) owns the procedure for an assigned stage.
The [architecture](architecture.md) page identifies the public entry points.

## Run the checks

Every test file and every example is a producer of one gate. Run it with `lute run tools/gate.luau`.
To run one test file, use `lute run tools/gate.luau --file tests/core.verify.luau`.
To run the cases whose name contains a text, use `lute run tools/gate.luau --name "<text>"`.
To run one case, use `lute run tools/gate.luau --only tests --case "<case id>"`.
The [README](../README.md#validate) lists the other options.

## Recover without repeating production

A held or ambiguous delivery keeps its record.
Resolve it with the status or attach calls of [direct delivery](api.md#direct-delivery).
A missing review or readback does not justify another generation or upload.

A fixture pass proves no live credentials, moderation, asset load or artistic quality.
Before you use a report to close a production claim, see the [evidence limits](evidence.md).
