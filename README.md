# Generate

Generate supplies deterministic asset records, image preparation and Roblox delivery for Luau. Consumers own execution, providers, authored-brief policy, rights, credentials and final acceptance.

| Family | Tools | Entry |
| --- | --- | --- |
| Records | Briefs, plans, reviews, provenance, receipts, manifests and revisions | [Core](docs/api.md#generate) |
| Images | Codecs, measurements, deterministic delivery, metrics and review staging | [Image](docs/api.md#image) |
| Roblox | Reviewed file/native delivery, destinations, readback, permissions, auditing and binary model reading | [Roblox](docs/api.md#roblox) |

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

The plan binds ordered stages to the brief. The consumer supplies execution and authority.
The [API reference](docs/api.md) covers record construction and delivery.

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
| Measure record processing time | [Benchmarks](docs/benchmarks.md) |
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
