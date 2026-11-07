# Generate

Asset production, review and Roblox delivery tools for Luau.

Generate helps Roblox developers turn an asset request into ordered tool steps, retained
outputs and a review tied to the exact files. It provides image transforms and checks,
audio measurement and conversion, review records, and Roblox upload and asset inspection
adapters. You supply the image, model, animation or audio tools, along with your quality
criteria, permissions and destination. Generate is a library for building that workflow;
it does not include a generation service or decide whether an asset meets your needs.

First, run one fixture with the [quickstart](docs/quickstart.md).

## What is inside

| Family | Tools | Entry |
| --- | --- | --- |
| Planning and execution | Asset requests, ordered stages, permission and budget checks, results and rollback records | [Brief, plan and execution](docs/api.md#brief-plan-and-execution) |
| Review and revisions | Review decisions tied to exact files, revision history, source and rights records, approved output lists | [Review and delivery](docs/api.md#review-and-delivery) |
| Delivery targets | Destination records checked by the selected adapter | [Delivery destinations](docs/api.md#delivery-destinations) |
| Roblox assets | File uploads, native Studio saves, permission requests, ownership and moderation checks, reference audits, binary instance reading and unit conversion | [Roblox adapter](docs/api.md#roblox-adapter) |
| Images | Tool bindings, pixel transforms, measurements, threshold checks and review views | [Image tools](docs/api.md#image-lane) |
| Audio | WAVE encoding and measurement, ffmpeg conversion, ffprobe metadata, loudness, waveforms and spectrograms | [Media](docs/api.md#media) |
| External tools | Run a supplied command and record its output digest and invocation | [Process tools](docs/api.md#process-tools) |
| Development | Asset-request diagnostics and simulated tool results for local tests | [Brief diagnostics](docs/api.md#brief-diagnostics), [fixture host](docs/api.md#fixture-host) |

Each package has a public entry under `src`. Core records work without Roblox or a
generation provider. Adapters connect those records to tools supplied by your project.

## Example

Describe an image and order its generation and review steps:

```luau
local Generate = require(path.to.generate.core)

local brief = Generate.brief {
    id = "sample.icon.v1",
    kind = "image",
    intent = { role = "A clear folder icon" },
    review = {
        rubric = "icon",
        rubricFingerprint = "icon-rubric-v1",
        views = { "normal", "32px" },
        blindness = "required",
        independence = "required",
    },
    delivery = { semanticId = "sample.icon", target = "local" },
}

local plan = Generate.plan(brief, {
    { id = "candidate", operation = "generate" },
    { id = "review", operation = "review", dependsOn = { "candidate" } },
})
assert(plan.briefId == brief.id)
```

This builds a plan without calling a tool or uploading anything. To run it, supply the
tool operations and permissions to `Generate.execute`, then inspect the returned status.
The [API reference](docs/api.md) covers results, failures and recovery.

## How it fits together

| Surface | Purpose |
| --- | --- |
| `src/core` | Asset requests, plans, execution, review, revisions, rights and delivery records. |
| `src/image` | Image tool bindings, transforms, measurements and review views. |
| `src/media` | WAVE encoding and measurement without external processes. |
| `src/roblox` | Roblox delivery, permissions, asset inspection and binary instance reading. |
| `src/lute` | Process execution and audio tool bindings for Lute. |
| `src/consumer` | Diagnostics for authored asset requests. |
| `src/host` | Simulated tool operations for fixtures. |

Import public package entries. Keep credentials, tool choices and final approval in your
project. [Architecture](docs/architecture.md) explains the boundaries between packages.

## Install

Generate is pinned by commit, not by version. Choose a commit of
`https://github.com/voidmeld/generate.git`, record its commit and tree in your dependency
lock, and vendor the packages you use. The [quickstart](docs/quickstart.md) covers the first
run; [adapters](docs/adapters.md) explains how to connect tools. After a pin change, run the
checks for the consumers you changed.

## Documentation

| Task | Document |
| --- | --- |
| Run the first fixture | [Quickstart](docs/quickstart.md) |
| Find public calls, returns and failures | [API reference](docs/api.md) |
| Connect tools and Roblox operations | [Adapters](docs/adapters.md) |
| Understand package boundaries | [Architecture](docs/architecture.md) |
| Look up record terminology | [Terms](docs/terms.md) |
| Understand what checks establish | [Check coverage and limits](docs/evidence.md) |
| Diagnose an asset request | [Lint](docs/lint.md) |
| Preserve editable source and native capabilities | [Native retention](docs/native-codegen.md) |
| Measure execution time | [Benchmarks](docs/benchmarks.md) |
| Change this repository or run its gate | [Maintainer guide](AGENTS.md) |
| Check source and dependency ownership | [Provenance](PROVENANCE.md) |

## Compatibility

The supported unit is an exact commit and tree; there is no semantic-version promise.
Public package exports, record schemas and documented failure behavior are contracts.
Update affected consumers with a contract change. Internal helpers and fixtures are not
public APIs. External tools and Roblox services have their own requirements.

## License

Generate is [MIT licensed](LICENSE). Its own development dependencies are pinned in
[dependencies.lock.luau](dependencies.lock.luau).
