# Generate

Generate is a content generation library for Luau. It turns a production brief into a plan,
candidate artifacts, review decisions and delivery records. Use it for images, 3D models,
animation, audio, voice and structured content.

```text
brief + host + authority -> plan -> candidate -> review -> delivery
```

## Use cases

- Declare a production brief: intent, constraints, review contract, provenance and delivery.
- Plan stages with capability and authority checks before any tool runs.
- Run image, 3D, audio and structured-content stages through consumer-supplied tools and hosts.
- Bind each review decision to exact candidate bytes, evidence and rubric. Require independent, blind reviewers.
- Block delivery when rights or lineage are unknown. Record each mutation with a recovery path.
- Deliver a reviewed file or, through the Roblox adapter, a native Roblox object directly, with readback and recovery.
- Select accepted artifacts into a manifest that the consumer loads through its own scene system.
- Check authored briefs with `tools/generate-check.luau`.

The consumer supplies generation tools, host operations and authority.
The consumer owns creative direction, providers, credentials, destinations and final acceptance.
Generate contains no media model and no scene runtime.

Terms: a brief declares an asset. A plan orders its stages. A candidate is a produced artifact. A receipt records an execution. A host performs the effects. The consumer is the code that uses Generate.

## Getting started

1. Install the pinned tools: `rokit install`.
2. Pin Generate. Use one exact commit of `https://github.com/voidmeld/generate.git`. Record its commit and tree hash in your repository. Require the packages under its `src` directory.
3. Declare a brief and a plan. This is the complete file [examples/quickstart.generate.luau](examples/quickstart.generate.luau):

```luau
--!strict

local Generate = require "../src/core"

local brief = Generate.brief {
	id = "example.crate.v1",
	kind = "modular-mesh",
	intent = { role = "A wooden storage crate", style = "weathered planks" },
	constraints = { triangleBudget = 2000, maxSize = { x = 4, y = 4, z = 4, unit = "m" } },
	review = {
		rubric = "prop",
		rubricFingerprint = "rubric-prop-v1-a71b30",
		rubricVersion = "1",
		views = { "front" },
		blindness = "required",
		independence = "required",
	},
	provenance = { requireParentLineage = true, requiredRightsFacts = { "source" } :: { Generate.RightsFactName } },
	delivery = { semanticId = "example.crate", target = "example-host" },
}

local plan = Generate.plan(brief, {
	{ id = "candidate", operation = "generate", requires = { "image-to-mesh" } },
	{ id = "review", operation = "review", dependsOn = { "candidate" }, requires = {} },
})

print(plan.id)
print(plan.fingerprint)
```

Run it with `lute run examples/quickstart.generate.luau`. The command prints the plan identity and its fingerprint.
It runs no stage and does not contact a provider. The [getting started guide](docs/getting-started.md) continues with a production job.

## Documentation

| Document | Owns |
| --- | --- |
| [Getting started](docs/getting-started.md) | Examples, the production job steps and recovery. |
| [Documentation index](docs/index.md) | The task each document serves. |
| [API](docs/api.md) | Planning, execution, review and delivery contracts. |
| [Adapters](docs/adapters.md) | Binding generation, image, audio, content and publication tools. |
| [Architecture](docs/architecture.md) | Public packages and responsibility boundaries. |
| [Evidence](docs/evidence.md) | What a claim proves. |
| [Production skill](.agents/skills/generate/SKILL.md) | How to execute an assigned production stage. |
| [Contributor guide](AGENTS.md) | How to change and validate this repository. |

## Packages

The [architecture](docs/architecture.md) lists each public package root (`src/core`, `src/agent`, `src/roblox`, `src/media`,
`src/image`, `src/content`, `src/lute`, `src/host` and `src/consumer`) and its responsibility.

## Validate

Run `lute run tools/gate.luau`. It is the one command that checks this repository.
Every test file and every example is a producer of this gate. Use these commands to run a part:

| Goal | Command |
| --- | --- |
| Run the whole gate | `lute run tools/gate.luau` |
| Run one test file | `lute run tools/gate.luau --file tests/core.verify.luau` |
| Run the cases whose name contains a text | `lute run tools/gate.luau --name "<text>"` |
| Run one case | `lute run tools/gate.luau --only tests --case "<case id>"` |
| Run one tier (`static`, `behavior` or `benchmark`) | `lute run tools/gate.luau --tier behavior` |
| Repeat what the last run did not pass | `lute run tools/gate.luau --rerun` |
| Explain why a producer or case ran or failed | `lute run tools/gate.luau --explain tests` |
| List the producers | `lute run tools/gate.luau --list` |
| Measure the execution hot path | `lute run tools/gate.luau --benchmark --only benchmark` |

A narrowed run prints `NARROWED`. It is not the gate. [AGENTS](AGENTS.md#validate) states when to run which.
[Benchmarks](docs/benchmarks.md) describes how to store and compare measurements.

## License

Copyright © 2026 voidmeld. [MIT License](LICENSE). [Provenance](PROVENANCE.md) states the source and dependency ownership.
