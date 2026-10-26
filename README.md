# Generate

Generate is a content generation library for Luau. It turns a brief into a plan,
candidate files, review decisions and delivery records. It supports images, 3D models,
animation, audio, voice and structured content.

First, install the pinned tools from the repository root:

```console
rokit install
```

Then run the [first example](docs/getting-started.md#run-an-example).
The consumer supplies the tools, host and authority. The consumer owns art direction,
rights, credentials, destinations and final acceptance.

## Documents

Use this page to select a document. Each document owns one subject.

| Document | Subject |
| --- | --- |
| [Getting started](docs/getting-started.md) | First example and production steps. |
| [API](docs/api.md) | Public calls, fields and contracts. |
| [Terms](docs/index.md#terms) | Technical words used in these documents. |
| [Architecture](docs/architecture.md) | Packages and their responsibilities. |
| [Adapters](docs/adapters.md) | Connections to tools and hosts. |
| [Evidence](docs/evidence.md) | Checks and the limits of their results. |
| [Lint](docs/lint.md) | Source and brief diagnostics. |
| [Native retention](docs/native-codegen.md) | Preserve native content before cleanup. |
| [Benchmarks](docs/benchmarks.md) | Measure execution time. |
| [Production skill](.agents/skills/generate/SKILL.md) | Execute an assigned production stage. |
| [Skill adapters](.agents/skills/generate/references/adapters.md) | Tool and Studio procedures. |
| [Skill review](.agents/skills/generate/references/review.md) | Review and rights procedures. |
| [Skill delivery](.agents/skills/generate/references/delivery.md) | Delivery procedures. |
| [Contributor guide](AGENTS.md) | Source change rules and validation. |
| [Provenance](PROVENANCE.md) | Source and dependency ownership. |
| [License](LICENSE) | MIT License. |
| [Change report](ready.md) | Changes, checks and limits for this candidate. |

## Validate

Run the gate from the repository root:

```console
lute run tools/gate.luau --tier fast
```

For a full gate, follow the [contributor guide](AGENTS.md#validate).
For one test file, add `--file tests/core.verify.luau` to the gate command.
For a case name, use `--name "<text>"`.
For a case ID, use `--only tests --case "<case id>"`.
Use `--list` to list producers. Use `--rerun` to repeat failed checks.
Use `--explain <id>` to explain a selection or failure.
A narrowed run proves only the selected checks.
