# Architecture

Generate converts a brief and consumer authority into deterministic plans, retained artifacts, revision-bound review and receipts.
Core owns records. Hosts own effects. Consumers own taste, budgets, credentials, destinations, rights policy and final runtime acceptance.

| Boundary | Responsibility |
| --- | --- |
| `src/core` | Briefs, plans, intersection of capability and authority, provenance, review, manifests, delivery destinations, publication records, host verification and recovery records. |
| `src/agent` | Reviewer executables that the consumer configures, and independent reviewer streams. |
| `src/roblox` | Roblox adapter, one module per job: direct file and native-object delivery, asset publication, publication records, size units, native transcripts, asset readback, permission grants, reference provenance, asset audit, binary instance reading. |
| `src/media` | Audio measurement without a process. |
| `src/image` | Recipe binding, one provider attempt, deterministic transforms, measurements and checks against consumer thresholds, and blind review packets. |
| `src/content` | Compilation of structured content that the consumer supplies. |
| `src/lute` | Process and media tool bindings. |
| `src/host`, `src/consumer` | Fixture hosts and authored-brief diagnostics. |

Core imports no provider, filesystem, engine or scene framework. Core names no host. A host is an adapter. `tools/check-boundary.luau` enforces this rule.
A manifest is data. The consumer can load it through its own scene system.
Generate records stochastic outputs. Planning does not make a provider deterministic.
`gen-fp2` is a bookkeeping fingerprint. It is not a signature and grants no authority.
Artifact SHA-256 digests bind bytes. They do not bind truthfulness or rights.

## Contracts

- [Execution](api.md#generateexecute) owns authority checks, stage results and compensation.
- [Review](api.md#generatebrief) owns the single decision, independence, blindness and byte bindings.
- [Direct delivery](api.md#direct-delivery) owns file and native-object saves with moderation readback and recovery.
- [Publication records](api.md#delivery-destination-and-publication-records) own the declared destination, the delivery receipt, its states and host verification.
- [Native retention](native-codegen.md) owns preservation before cleanup.

An accepted receipt establishes only the acceptance that the brief declares.
The consumer still verifies its actual runtime and decides whether to promote the artifact.

Test production receipts with ordinary Verify cases.
Close over the receipt and assert through the case context.
Use the same host binding, deadline, evidence and report APIs as other tests.
Generate adds no test authoring format and does not wrap Verify run options.
