# Documentation index

This index maps each Generate document to the task that it serves.

| Document | Use it to |
| --- | --- |
| [Getting started](getting-started.md) | Write a production brief. |
| [API](api.md) | Call a public package root. |
| [Architecture](architecture.md) | Change ownership or dependencies. |
| [Adapters](adapters.md) | Bind a provider or platform. |
| [Evidence](evidence.md) | Check what a claim proves. |
| [Lint](lint.md) | Investigate a diagnostic. |
| [Native tools](native-codegen.md) | Add work that is not Luau. |
| [Benchmarks](benchmarks.md) | Measure, store and compare the execution hot path. |
| [Validate](../README.md#validate) | Run the gate, one test file or one case. |
| [Provenance](../PROVENANCE.md) | Assess the origin or license of the source. |

## Terms

Each document uses these terms with one meaning.

| Term | Meaning |
| --- | --- |
| brief | The declaration of one asset: intent, constraints, review, provenance and delivery. |
| plan | The ordered stages that a brief needs. A plan runs nothing. |
| stage | One step of a plan. It has an operation, its dependencies and an optional mutation with a rollback. |
| candidate | An artifact that a stage produced. It is not accepted until review binds a decision to its exact bytes. |
| receipt | The record of one execution: stages, artifacts, review, recovery and status. |
| host | The code that performs the effects of a stage. The consumer supplies it. |
| adapter | The package or module that binds Generate to one tool, platform or service. |
| consumer | The code and the owner that use Generate. The consumer owns art direction, tools, rights, credentials, destinations and acceptance. |
| destination | The place that receives delivered content. An adapter describes it and validates its descriptor. |
| publication record | The delivery receipt of one destination. It names the content identity and a state: `pending`, `confirmed`, `reconciled` or `stopped`. |
| host verification | An observation that delivered content was exercised in a named host build. |
| packet | The exact candidate, evidence and rubric that one reviewer sees. A packet binds their digests. |
| decision | The verdict of one reviewer about one packet: `approved`, `rejected` or `abstained`, with reasons. |
| revision | One numbered version of a candidate. A ledger keeps the revisions in order. |
| rights fact | One of `source`, `license`, `owner` and `consent`. A brief can require facts before delivery. |
| quota | A measured value and its ceiling, or a kind and its allowed kinds. |
| capture bracket | The declared order and poses of the captures that serve as review evidence. |
| grant | The authority that allows one bounded Roblox action: one publication attempt, or the use of assets by a universe. |
| readback | A read of the destination after a change. It checks the creator, the type, the version and the moderation state. |
| census | A readback of a root asset and the dependencies that the caller names. It reports owners, moderation and unresolved IDs. |
| disposition | The name of an outcome of a publication or transaction, for example `published` or `refused`. |
| rollback token | The opaque handle that undoes one mutation. |
| transcript | The retained record of Studio calls and results. It binds their bytes by SHA-256. |
| threshold | A pass line or a measurement parameter that the consumer declares. Generate supplies no default. |
| review | The resolution of one packet by its one eligible decision. It is `approved`, `rejected`, `unresolved`, `incomplete` or `stale`. |

The production skill reports a stage end with `REFUSE` or `HOLD`.
`REFUSE` means the stage must not continue, because authority, scope or a prerequisite is missing or forbidden.
`HOLD` means the stage waits for a missing input or a pending outcome, and the consumer can resume it.

