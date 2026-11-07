# API reference

This page owns public signatures, return values and failure behavior.
The public-surface check requires an entry here for each public export.
Generate turns a brief into a plan, a retained candidate, a review decision and a receipt.
Core owns those records. The consumer supplies art direction, host operations and authority.

| Task | Start here |
| --- | --- |
| Describe an asset and run its stages | [Brief, plan and execution](#brief-plan-and-execution) |
| Review exact bytes and select delivery | [Review and delivery](#review-and-delivery) |
| Declare the intended destination of a brief | [Delivery destinations](#delivery-destinations) |
| Use Roblox: save, publish, grant, read back or audit assets | [Roblox adapter](#roblox-adapter) |
| Measure, convert or render audio for review | [Media](#media) |
| Bind a content compiler, a process tool or a reviewer | [Content, process and reviewer adapters](#process-tools) |
| Produce and review an image | [Image lane](#image-lane) |
| Check an authored brief | [Brief diagnostics](#brief-diagnostics) |

## Shared setup

The examples are fragments. Complete examples and tests are linked in each area.
Calls use dots. The examples use public package roots. Replace the path with your package location:

```luau
local Generate = require(path.to.generate.core)
local Roblox = require(path.to.generate.roblox)
local Image = require(path.to.generate.image)
local Media = require(path.to.generate.media)
local Lute = require(path.to.generate.lute)
local Consumer = require(path.to.generate.consumer)
local Host = require(path.to.generate.host)
```

Type names in a signature use the linked module's aliases. Public root aliases are listed with each area.
The signature tables and prose below form one contract. Source links locate type declarations for implementation work.
A missing return annotation means the result is inferred; the area's prose describes its shape.
This page lists every public function. Use the [architecture](architecture.md) for package responsibilities.
Use [the quickstart](quickstart.md) for the procedure.
Modules below package roots are internal. Their helper exports are not public contracts.
The [terms](terms.md) define the words that this page uses.

---

## Brief, plan and execution

### Signatures

| Call and return | Type declarations |
| --- | --- |
| `Generate.brief(draft: BriefDraft): Brief` | [Types](../src/core/brief.luau) |
| `Generate.briefFingerprint(brief: Brief): string` | [Types](../src/core/brief.luau) |
| `Generate.canonical(value: unknown): string` | [Types](../src/core/canonical.luau) |
| `Generate.continueReview(brief: Brief, plan: Plan, receipt: Receipt, drafts: { ReviewDecisionDraft }): Receipt` | [Types](../src/core/execution.luau) |
| `Generate.derivation(draft: DerivationDraft): Derivation` | [Types](../src/core/provenance.luau) |
| `Generate.execute(brief: Brief, plan: Plan, host: Host, authority: Authority): Receipt` | [Types](../src/core/execution.luau) |
| `Generate.fingerprint(value: unknown): string` | [Types](../src/core/canonical.luau) |
| `Generate.manifest(receipt: Receipt, artifactIds: { string }): DeliveryManifest` | [Types](../src/core/manifest.luau) |
| `Generate.plan(brief: AssetBrief, drafts: { StageDraft }): Plan` | [Types](../src/core/plan.luau) |
| `Generate.provenanceFaults( value: Derivation?, contract: ProvenanceContract, byArtifactId: { [string]: Derivation }, artifactId: string ): { string }` | [Types](../src/core/provenance.luau) |
| `Generate.receiptFingerprint(receipt: Receipt): string` | [Types](../src/core/receipt.luau) |
| `Generate.resolveReview( target: ReviewPacket, contract: ReviewContract, decisions: { ReviewDecision }, staleness: ReviewStaleness? ): ResolvedReview` | [Types](../src/core/review.luau) |
| `Generate.reviewBinds(review: ResolvedReview, artifactId: string, digest: string): boolean` | [Types](../src/core/review.luau) |
| `Generate.reviewDecision(draft: ReviewDecisionDraft): ReviewDecision` | [Types](../src/core/review.luau) |
| `Generate.reviewPacket(draft: ReviewPacketDraft, binding: Types.PacketBinding): ReviewPacket` | [Types](../src/core/review.luau) |
| `Generate.revisionLedger(candidateId: string, drafts: { RevisionEntryDraft }): RevisionLedger` | [Types](../src/core/revision.luau) |
| `Generate.rights(draft: RightsFactsDraft?): RightsFacts` | [Types](../src/core/provenance.luau) |
| `Generate.rollCandidate(current: RevisionLedger, draft: RollDraft): CandidateRevisionDraft` | [Types](../src/core/revision.luau) |

Public types: `Generate.ArtifactRef`, `Generate.CandidateDisposition`, `Generate.CandidateRevision`, `Generate.Certainty`, `Generate.Verdict`, `Generate.RightsFactName`, `Generate.ReviewRequirement`, `Generate.PacketBinding`, `Generate.Derivation`, `Generate.DerivationDraft`, `Generate.EvidenceRef`, `Generate.ExcludedDecision`, `Generate.ReviewDisposition`, `Generate.ParentRef`, `Generate.ProvenanceContract`, `Generate.ResolvedReview`, `Generate.ReceiptStatus`, `Generate.ReviewContract`, `Generate.Metadata`, `Generate.DerivationOrigin`, `Generate.ReviewDecision`, `Generate.ReviewDecisionDraft`, `Generate.ReviewPacket`, `Generate.ReviewPacketDraft`, `Generate.RightsFact`, `Generate.RightsFacts`, `Generate.RubricIdentity`, `Generate.RevisionEntry`, `Generate.RevisionEntryDraft`, `Generate.RevisionLedger`, `Generate.RevisionOutcome`, `Generate.RevisionRollDraft`, `Generate.CandidateRevisionDraft`, `Generate.Artifact`, `Generate.AssetKind`, `Generate.Authority`, `Generate.Brief`, `Generate.BriefDraft`, `Generate.Host`, `Generate.Invocation`, `Generate.Destination`, `Generate.DeliveryContract`, `Generate.PublicationAttemptEconomics`, `Generate.DeliveryEntry`, `Generate.DeliveryManifest`, `Generate.Plan`, `Generate.Receipt`, `Generate.ProviderCallEconomics`, `Generate.ReviewerEconomics`, `Generate.StageEconomics`, `Generate.RunContext`, `Generate.RollbackOutcome`, `Generate.Stage`, `Generate.StageDraft`, `Generate.StageOutcome`, `Generate.StageRecord`.
### Returns and failures

Core constructors return normalized contract records. The plan copies parameter maps shallowly.
Invalid trusted drafts raise with a field-specific message.
They reject duplicate identities, malformed bindings, non-finite values, cycles and secret-shaped metadata.
`briefFingerprint`, `receiptFingerprint` and `fingerprint` return deterministic strings; `canonical` returns canonical text.
`execute` returns a receipt whose `status` must be inspected. A produced receipt is not an acceptance or publication grant.
Execution records rejected and faulted stages and the compensation outcomes of completed mutations.
`continueReview` returns a new receipt. Binding drift and ineligible input receipts raise before continuation.

Run the [core contract](../tests/core.verify.luau) and [consumer checks](../tests/consumer.verify.luau).


A brief declares an asset. A plan orders its stages. Execution runs the stages under authority.

### `Generate.brief`

`brief(draft) -> Brief`

`Generate.brief` declares one asset. It makes a schema-v1 record with identity, kind, intent, delivery, review and provenance.
Brief metadata uses the open `Metadata` data map and contributes to its fingerprint. Validation rejects executable values, cycles, non-finite numbers and secret-shaped keys at every depth.

- Every contract requires exactly one decision. One decision covers the entire rubric.
- The contract has no decision count and no rule. The default for `independence` is `required`.
- Review declares the rubric identity and fingerprint, the canonical views and the blindness.
- `independence = "optional"` permits a producer inspection in a shared context. Record the real actor. Set `blind = false`. Consumer policy decides which intermediate inputs allow this mode. Finished assets usually require independence.
- A change to the contract changes the brief fingerprint. It invalidates earlier receipt bindings. Earlier receipts fail verification when the review fields change.
- The rights facts are `source`, `license`, `owner` and `consent`. `Generate.RIGHTS_FACT_NAMES` lists them. An unknown fact that the brief requires blocks publication and manifest promotion.
- Scores and structural refusals remain review data. They cannot override a rejected or unresolved review.
- `Generate.briefFingerprint(brief)` recomputes the fingerprint of a brief.

A brief declares the asset and the evidence that review needs. The `schemaVersion` of a brief is `1`:

```luau
local brief = Generate.brief {
    id = "inventory.icon.v1",
    kind = "image",
    intent = { role = "A legible inventory icon" },
    review = {
        rubric = "icon",
        rubricFingerprint = "icon-rubric-v1",
        views = { "normal", "32px" },
        blindness = "required",
        independence = "required",
    },
    delivery = { semanticId = "inventory.icon", target = "local" },
}
```

[Accepted delivery](../examples/accepted-manifest.generate.luau) is a complete fixture with rights, artifact digests, review evidence and a manifest.

### `Generate.plan`

`plan(brief, stages) -> Plan`

`Generate.plan` turns a brief into ordered stages. It orders the declared `generate`, `import`, `transform`, `verify`, `review`, `publish` and `custom` operations.
A dependency must refer backward. Every mutation declares rollback.
Plans copy dependency and requirement lists. Plans sort requirements. Parameter maps are shallow copies.

```luau
local plan = Generate.plan(brief, {
    { id = "candidate", operation = "generate" },
    { id = "technical", operation = "verify", dependsOn = { "candidate" } },
    { id = "review", operation = "review", dependsOn = { "technical" } },
})
```

Planning describes work. It does not invoke a generator and does not publish an asset.
The [modular asset example](../examples/modular-wall.generate.luau) shows a plan with an explicit publication stage and rollback.

### `Generate.execute`

`execute(brief, plan, host, authority) -> Receipt`

`Generate.execute` runs a plan and records a receipt. It uses only host capabilities that consumer authority permits.
It checks destinations and budgets. It sends a stable idempotency key for each stage.
If a stage fails, execution compensates completed mutations in reverse order.
A fault after a change must return its opaque rollback handle.

- Receipts have `schemaVersion` `2`. They bind stages, artifact identities, invocations, derivations, review, economics and recovery.
- Optional economics records keep the calls, costs and reviewers that the host reports. Unknown values stay absent.
- Execution measures stage duration. The consumer combines totals and schedules providers.
- `Generate.canonical(value)` encodes a record deterministically. `Generate.fingerprint(value)` hashes that encoding. `Generate.receiptFingerprint(receipt)` recomputes the binding of a receipt. A fingerprint is not a signature and grants no authority.
- Stage metadata uses an open `{ [string]: unknown }` data map. Receipt ingestion checks it.
  The consumer checks extension field types before use.
- QA facts contain strings, numbers and booleans. Optional measurements stay absent. Generate does not invent them.

### `Generate.continueReview`

`continueReview(brief, plan, receipt, decisions) -> Receipt`

`Generate.continueReview` adds review decisions to a produced receipt. It resolves review for one unchanged, completed `produced` receipt. It does not repeat native work.
It refuses receipt, brief or plan drift, unknown packets, unfinished runs and completed mutations.
Later review does not change the production timing and cost.

---

## Review and delivery

Review binds one decision to exact candidate bytes. Delivery selects the approved bytes.
Production and acceptance are separate outcomes.
A produced candidate needs one decision that binds to its exact bytes under [the review contract of the brief](#generatebrief).

### Packets and decisions

A packet holds the exact candidate, evidence and rubric that a reviewer sees. A decision is the verdict of one reviewer about one packet.

| Task | Call |
| --- | --- |
| Bind the candidate revision, artifacts, evidence and rubric to a stage | `Generate.reviewPacket(draft, binding)` |
| Record the identity, context, verdict and reasons of the reviewer | `Generate.reviewDecision(draft)` |
| Resolve the single eligible decision under the declared contract | `Generate.resolveReview(packet, contract, decisions, staleness?)` returns a `ResolvedReview`. |
| Check that a resolved review binds an artifact digest | `Generate.reviewBinds(review, artifactId, digest)` does not claim that the reviewer is truthful. |

- The packet includes the producer, the requested views and the capture environment.
- A decision includes the actor, the role, the context and the certainty. A decision that is not an approval needs reasons.
- A resolved review has `decisions` (the eligible decisions), `excluded`, `disposition` (`approved`, `rejected`, `unresolved`, `incomplete` or `stale`) and `resolution`. It excludes self-review, duplicate actors, changed bindings, and unmet blindness or independence. Each excluded decision names its actor and reason.
- An extra submission for the same packet leaves review unresolved. This includes a duplicate.
- Changed output makes the prior approval stale. Technical production alone returns `produced`.

### Revisions and provenance

Revisions keep consecutive candidate revisions. Provenance records lineage and rights.

| Task | Call |
| --- | --- |
| Build the ledger of one candidate from its revision entries | `Generate.revisionLedger(candidateId, entries)` |
| Draft the next candidate revision from a ledger | `Generate.rollCandidate(ledger, draft)` |
| Normalize and validate where a candidate came from | `Generate.derivation(draft)` |
| Normalize the rights facts of a candidate | `Generate.rights(draft)` |
| List the lineage and rights faults that block delivery | `Generate.provenanceFaults(derivation, contract, byArtifactId, artifactId)` |

An open head cannot roll. To replace an approved head, declare that replacement.
Derivations and rights do not invent rights facts.

### `Generate.manifest`

`manifest(receipt, artifactIds) -> DeliveryManifest`

`Generate.manifest` lists the approved artifacts for delivery. It selects the exact approved semantic delivery with the required provenance. Its entries name `reviewId` and `reviewFingerprint`.
The consumer owns registry adoption and runtime acceptance.
See [accepted delivery](../examples/accepted-manifest.generate.luau) and [revision rollover](../examples/candidate-revision.luau).

---

## Delivery destinations

A destination records the intended delivery target. Delivery outcomes belong to the transport journal and consumer verification.

### Declare the destination

A brief can declare an optional destination in its `delivery` contract:

- `delivery.destination` has an `adapter` name in lowercase and a `descriptor` data table.
- `delivery.hostVerification` is a boolean. It defaults to `false`. It needs a destination.

Core does not read the descriptor. The named adapter owns and checks it.
Core refuses a descriptor with a secret-shaped key or a value that is not data.
Credentials are never brief values. A descriptor can carry only the name of a credential.
The destination is a record. Generate does not perform the publication.

## Roblox adapter

### Signatures

| Call and return | Type declarations |
| --- | --- |
| `Roblox.assetAudit.referenceViolations(input: Input): { string }` | [Types](../src/roblox/asset-audit.luau) |
| `Roblox.assetReadback.census(options: Options, rootAssetId: string, dependencyAssetIds: { string }): Census` | [Types](../src/roblox/asset-readback.luau) |
| `Roblox.assetReadback.readback(options: Options, assetId: string): Record` | [Types](../src/roblox/asset-readback.luau) |
| `Roblox.delivery.attach(config: Config, key: string, reference: { operation: string?, assetId: string? }): Result` | [Types](../src/roblox/delivery.luau) |
| `Roblox.delivery.key(format: string, digest: string, assetType: string?): string?` | [Types](../src/roblox/delivery.luau) |
| `Roblox.delivery.native.attach(config: Config, key: string, assetId: string): Result` | [Types](../src/roblox/delivery.luau) |
| `Roblox.delivery.native.attributeStore(instance: AttributeInstance, http: AttributeJson): Store` | [Types](../src/roblox/delivery.luau) |
| `Roblox.delivery.native.save(config: Config, host: NativeHost, request: NativeRequest): Result` | [Types](../src/roblox/delivery.luau) |
| `Roblox.delivery.queue(config: Config, items: { Item }, options: QueueOptions?): QueueResult` | [Types](../src/roblox/delivery.luau) |
| `Roblox.delivery.status(config: Config, reference: string, expectedType: string?): Result` | [Types](../src/roblox/delivery.luau) |
| `Roblox.delivery.upload(config: Config, request: UploadRequest): Result` | [Types](../src/roblox/delivery.luau) |
| `Roblox.destination(draft: unknown): Generate.Destination` | [Types](../src/roblox/destination.luau) |
| `Roblox.permissionGrant.attempt(send: SendAuthorized, decode: Decode, prepared: Request): Result` | [Types](../src/roblox/permission-request.luau) |
| `Roblox.permissionGrant.chunks(assetIds: { string }, size: number): { { string } }` | [Types](../src/roblox/permission-request.luau) |
| `Roblox.permissionGrant.prepare(encode: Encode, universeId: number, assetIds: { string }): Request` | [Types](../src/roblox/permission-request.luau) |
| `Roblox.permissionGrant.subjectAuthority( options: AuthorityOptions, credentialValue: unknown, universeId: string, groupId: string ): (AuthorityReceipt?, string)` | [Types](../src/roblox/permission-grant.luau) |
| `Roblox.rbxm.instancePath(tree: Tree, referent: number): string` | [Types](../src/roblox/rbxm.luau) |
| `Roblox.rbxm.instances(bytes: string): Tree` | [Types](../src/roblox/rbxm.luau) |
| `Roblox.rbxm.isBinary(bytes: string): boolean` | [Types](../src/roblox/rbxm.luau) |
| `Roblox.rbxm.read(bytes: string): Document` | [Types](../src/roblox/rbxm.luau) |
| `Roblox.readDestination(value: Generate.Destination): DestinationFields` | [Types](../src/roblox/destination.luau) |
| `Roblox.units.studs(size: unknown): Studs` | [Types](../src/roblox/units.luau) |

Public types: `Roblox.AssetAuditFiles`, `Roblox.AssetAuditConfig`, `Roblox.AssetAuditInput`, `Roblox.AssetAuditReference`, `Roblox.AssetAuditModel`, `Roblox.AssetReadbackOptions`, `Roblox.AssetReadbackOwner`, `Roblox.AssetRecord`, `Roblox.AssetCensus`, `Roblox.DeliveryAuthority`, `Roblox.DeliveryAttributeInstance`, `Roblox.DeliveryAttributeJson`, `Roblox.DeliveryConfig`, `Roblox.DeliveryResult`, `Roblox.DeliveryRecord`, `Roblox.DeliveryStore`, `Roblox.DeliveryReview`, `Roblox.DeliveryCreator`, `Roblox.DeliveryRequest`, `Roblox.DeliveryReply`, `Roblox.DeliveryUpload`, `Roblox.DeliveryItem`, `Roblox.DeliveryRow`, `Roblox.DeliveryQueueResult`, `Roblox.DeliveryNativeHost`, `Roblox.DeliveryNativeRequest`, `Roblox.PermissionAuthorityOptions`, `Roblox.PermissionCredential`, `Roblox.PermissionAssignedRole`, `Roblox.PermissionChunkOutcome`, `Roblox.PermissionAuthorityReceipt`, `Roblox.PermissionPatch`, `Roblox.RbxmClass`, `Roblox.RbxmDocument`, `Roblox.RbxmInstance`, `Roblox.RbxmReference`, `Roblox.RbxmTree`, `Roblox.SizeUnit`, `Roblox.Size`, `Roblox.Studs`, `Roblox.PermissionRequest`, `Roblox.PermissionRequestResult`, `Roblox.CloudRequest`, `Roblox.CloudResponse`, `Roblox.CloudSend`, `Roblox.Destination`, `Roblox.DestinationDraft`.
### Returns and failures

Destination constructors and units raise for invalid descriptors or dimensions.
Permission operations return their declared authority and chunk outcomes. Inspect every refusal before another mutation.
Readback returns an `AssetRecord`, including unknown fields and diagnostics for observations it cannot establish.
`census` returns the root and named dependency observations. It does not discover an exhaustive dependency graph.
`referenceViolations` returns a list of strings. An empty list proves only the declared manifest checks.
Binary readers return parsed records and diagnostics; inspect `ok` before using their class or instance lists.
`isBinary` returns a boolean. `instancePath` returns a dot-separated path, or an empty string for an unknown referent.
Direct delivery uses the verdict and recovery contract below; it does not raise approval from an uncertain response.

See [delivery](../tests/delivery.lute.verify.luau), [cloud contracts](../tests/cloud-contracts.lute.verify.luau)
and [destination cases](../tests/roblox-destination.verify.luau).


The Roblox adapter binds Generate to Roblox: it saves, publishes, grants, reads back and audits assets.
It validates Roblox facts and records them. The consumer supplies every transport, credential and file operation.
Each module does one job.

| Task | Module |
| --- | --- |
| Save a reviewed file or native object without a brief | [`Roblox.delivery`](#direct-delivery) |
| Describe a Roblox destination | `Roblox.destination` and `Roblox.readDestination` |
| Let a universe use assets that your creator owns | [`Roblox.permissionGrant`](#permission-grants) |
| Read an asset, its owner and its moderation state | [`Roblox.assetReadback`](#asset-readback) |
| Audit the reference rows of a manifest | [`Roblox.assetAudit`](#asset-audit) |
| Read a binary instance file | [`Roblox.rbxm`](#binary-instance-files) |
| Convert a size to studs | [`Roblox.units`](#destinations-and-units) |

`Roblox.delivery` owns reviewed file uploads and native-object saves, with one-attempt journals, moderation readback and recovery. It needs no brief.

The transport types are `Roblox.CloudRequest`, `Roblox.CloudResponse` and `Roblox.CloudSend`.
`send(request)` receives a `CloudRequest` and returns a `CloudResponse` with `ok`, `status` and `body`.

### Destinations and units

`Roblox.destination(draft)` validates and normalizes a Roblox destination as a `Generate.Destination`.
`Roblox.readDestination(destination)` reads the typed fields and refuses a descriptor that is not normalized.
Both preserve the declared creator, asset type, restricted visibility and optional universe requirements.
`Roblox.units.studs(size)` converts metres, centimetres or millimetres; one stud is 0.28 metres.

The destination descriptor requires `creator`, `assetType`, `visibility` and `credentialName`.
The `creator` is `group` or `user`. The `visibility` is `private` or `restricted`.
Optional fields are `assetId`, `displayName`, `description`, `grantUniverses` and `verifyDependencies`.
Public visibility is refused. `verifyDependencies` needs `grantUniverses`.

A brief declares `constraints.maxSize = { x, y, z, unit = "m" }`. The unit defaults to metres. Convert the size in the adapter, not in the brief.

### Direct delivery

`Roblox.delivery` saves a reviewed file or a native Studio object and returns a usable asset ID and an optional version.
It has no brief, plan, receipt or transcript.
It uses plain Luau with no `require`. The same source file can load in Studio.
The consumer injects every effect through `Roblox.DeliveryConfig`:

- `creator`: `{ kind = "group" | "user", id }`. It is required. Generate requires it. Generate does not read it from the environment or replace a group with a user.
- `privacy` (default `restricted`), `store`, `json`, `sha256`, `now`, `wait`, `polls`, `interval`.
- `send(request)` and `headers(purpose)`: the transport and the authentication headers. Generate never reads or stores credentials. It redacts the header values from transport error text.
- `authorize(key)`: optional for file uploads. It runs before a fresh send, including an unsent retry. It returns evidence to record, or `nil, reason` to refuse. Native saves do not call it. The consumer must authorize them before it calls `save`.

Every function returns a `DeliveryResult`:

- `verdict` (`approved`, `hold` or `stop`), `reason` and `retry` (`safe`, `poll` or `never`)
- optionally `detail`, `assetId`, `version`, `moderation`, `operation` and the stored `record`

Only `approved` permits the next action.

| Reason | Verdict | Meaning |
| --- | --- | --- |
| `approved` | approved | The creator and type match and moderation is approved. A file readback also requires a version. |
| `malformed` | hold, `poll` | The readback identity or field shapes do not match the declared schema. |
| `pending` | hold, `poll` | The operation or moderation is unfinished. Read again. Never create again. |
| `remote_unreachable`, `rate_limited` | hold | File creates marked `safe` were unsent or got HTTP 429. Read failures use `poll`. Consumer policy bounds retries. |
| `ambiguous` | stop | The request may have been sent and has no recorded outcome. |
| `rejected` | stop | Moderation rejected the asset. |
| `refused` | stop | HTTP 401 or 403, or refusal text. The record keeps a refused file create. The adapter does not send it again. |
| `identity`, `invalid`, `unreviewed`, `not_authorized`, `failed`, `warning`, `inspection`, `concurrent` | stop | The input, record, creator or host result is unacceptable. |

The consumer owns rights, review authenticity, native-object identity and authorized scope.
This adapter checks the supplied records. It does not establish independent review and does not enforce the destination of the brief.
Use a durable store with atomic `create`. Complete record writes before effects.
A record is recovery data. It is not an accepted core receipt.
`stop` ends the assigned action. Recovery needs reconciled evidence.

#### Files

Use `Roblox.delivery.upload` to save one reviewed file.

`Roblox.delivery.upload(config, request)` takes these fields:

- `label`, `bytes`, `name`, `description`
- `format`: `png`, `wav`, `mp3`, `ogg`, `rbxm`, `rbxmx`, `fbx`, `gltf` or `glb`. The binary and XML instance formats request `Animation` unless `assetType` is `Model`; FBX and glTF formats request `Model`, following the [Assets API file formats](https://create.roblox.com/docs/cloud/guides/usage-assets#supported-asset-types-and-limits). The consumer supplies a complete model payload, including its required resources.
- `assetType` (optional): `Animation` or `Model` for `rbxm` and `rbxmx`, where `Animation` is the default. Every other format accepts only its own type. Any other value stops as `invalid` before a send.
- `review`: `by`, `verdict = "complies"`, `shows`, and the `sha256` of those exact bytes

The function runs these steps:

1. It checks the review.
2. It writes the record before it sends.
3. It sends one Open Cloud create.
4. It polls the operation.
5. It reads the asset back for creator, type, version and moderation.

The record under the SHA-256 of the bytes holds the source label, hash, size, reviewer, creator, privacy, authority evidence, operation, asset ID, version and moderation.
A repeated call resumes from the record.

A record is kept per bytes and asset type. The default type of a format keeps the bare SHA-256 as its key. Another type uses `<sha256>_<assetType>`. `Roblox.delivery.key(format, sha256, assetType)` returns the key, or `nil` for an unsupported type. Pass that key to `attach`.

- `status(config, reference, assetType)` reads an operation path or an asset ID. It does not update a stored attempt.
- `queue(config, items, options)` uploads one item at a time. It stops at the first result that is not approved and reports each `Row` through `options.log`. Each item prepares its request when the queue reaches it.

A failure after the request left is `ambiguous`.
To resolve it, find the operation or asset ID outside Generate. Then call `Roblox.delivery.attach(config, key, { operation | assetId })`, which reads it back.
Nothing is sent again before that.

#### Native objects

Use `Roblox.delivery.native.save` to save one native object once.

`Roblox.delivery.native.save(config, host, request)` saves one native object once (EditableMesh, EditableImage or Model).
It uses `AssetService:CreateAssetAsync` through `host.create`.

- `request` carries `key`, `object`, `kind`, `name`, `review` and an optional `identity`.
- Use a stable key that binds to the exact object. A resume checks the kind and the creator. It does not check the object bytes, the review hash or `identity`.
- `host.inspect` can refuse the object before any save.
- A throw, a result that is not `Success`, a missing ID or a warning stops the action and keeps the record.
- `host.readback(assetId)` resumes a recorded asset ID. It returns `assetId`, `creator`, `assetType`, `version` and `moderation`. The object is never saved twice.
- If a call never returned an ID, call `Roblox.delivery.native.attach(config, key, assetId)`. It records the ID and returns `hold`. Then call `save` again to read it back without a create.
- `Roblox.delivery.native.attributeStore(instance, httpService)` keeps the records as JSON attributes on a Studio Instance, so that a session can resume. Keep that Instance durably.
- Native approval does not require a version. It does not require the readback ID to match the requested ID. The host must supply a trustworthy readback.

| Task | Call |
| --- | --- |
| Upload one reviewed file | `Roblox.delivery.upload(config, request)` |
| Read an operation or an asset | `Roblox.delivery.status(config, reference, assetType)` |
| Upload several files, stopping at the first refusal | `Roblox.delivery.queue(config, items, options)` |
| Get the store key of an upload | `Roblox.delivery.key(format, sha256, assetType)` |
| Record an operation or asset ID after an ambiguous upload | `Roblox.delivery.attach(config, key, reference)` |
| Save one native object | `Roblox.delivery.native.save(config, host, request)` |
| Record an asset ID after an ambiguous native save | `Roblox.delivery.native.attach(config, key, assetId)` |
| Keep native records on a Studio Instance | `Roblox.delivery.native.attributeStore(instance, httpService)` |


### Permission grants

`Roblox.permissionGrant` checks the credential subject, prepares ordered asset requests and sends one request per call. The consumer owns authorization, write-ahead records, recovery and destination proof.

| Task | Call |
| --- | --- |
| Read the group membership and roles of the credential owner and record them as facts | `Roblox.permissionGrant.subjectAuthority(options, credential, universeId, groupId)` |
| Split asset IDs into groups of one request | `Roblox.permissionGrant.chunks(assetIds, size)` |
| Build the request for one group | `Roblox.permissionGrant.prepare(encode, universeId, assetIds)` |
| Send one request and check that the response confirms exactly the requested assets | `Roblox.permissionGrant.attempt(send, decode, prepared)` |
| Compare a prepared request with a stored one | `Roblox.permissionGrant.ENDPOINT` and `Roblox.permissionGrant.MAX_ASSETS_PER_REQUEST` |
| Set the decision of a credential record | `Roblox.permissionGrant.CREDENTIAL_DECISION` |
| Match an authority decision | `Roblox.permissionGrant.DECISIONS` has `bound` and `refused`. |
| Match an authority reason | `Roblox.permissionGrant.REASONS` has `membershipAbsent` and `scopesUncovered`. |

- `chunks` orders the IDs, refuses duplicates and IDs that cannot be represented exactly as positive integers below 2^53, and allows at most `MAX_ASSETS_PER_REQUEST` IDs in a group.
- `prepare` builds one `PATCH` request with the action `Use`. It carries the header names and the sorted asset IDs.
- `attempt` never retries. Malformed JSON, response errors and mismatched confirmations refuse the result while retaining the HTTP status and bounded response body. An unconfirmed result does not authorize another attempt.
- `subjectAuthority` needs a credential record with `decision = Roblox.permissionGrant.CREDENTIAL_DECISION`, an `authorizedUserId` and permission operations that include `write`.

### Asset readback

`Roblox.assetReadback` reads an asset and its dependencies through a consumer-supplied transport.
Every request is a `GET`. A readback proves ownership and state. It authorizes no change.

| Task | Call |
| --- | --- |
| Read one asset | `Roblox.assetReadback.readback(options, assetId)` returns a `Record`. |
| Read a root asset and the dependencies that you name | `Roblox.assetReadback.census(options, rootAssetId, dependencyAssetIds)` returns a `Census`. |
| Match the source of a record | `Roblox.assetReadback.SOURCES` has `record` and `details`. |
| Match an unobservable field | `Roblox.assetReadback.UNOBSERVABLE` has `privacy` and `moderation`. |

A `Record` has the creator, type, moderation state, privacy, revision, `source` and a `diagnostic`. A field that the reply does not carry is `unknown` and never a passing value.
A `Census` reports foreign owners, unapproved moderation, unresolved IDs and whether the census is closed. It reads exactly the IDs that you name.

Readback retries only HTTP 429 and 503, within `maxRetries`. A rate-limit reset is capped at 60 seconds. HTTP 401 stops immediately. The optional public-details read after HTTP 403 remains an observation; missing moderation stays unknown.
`options` has `send`, `decode` and `owner`. Optional fields are `sendPublic`, `sleep`, `clock`, `paced`, `baseUrl`, `detailsBaseUrl`, `maxRetries` (default `5`) and `minIntervalSeconds` (default `0.55`).

### Asset audit

`Roblox.assetAudit.referenceViolations(input)` lists the violations of a manifest. It checks that each reference row carries the required fields, a committed original with the recorded digest, a recorded readback and one reviewer verdict.
It also checks that each model row resolves to exactly one reference by SHA-256 and image asset ID.
The `config` may name `requiredReferenceFields` and `receiptFields`. Without them, the audit requires these reference fields:

- `committed_source_path`, `source_sha256` and `prompt_sha256`
- `lineage_path`, `reviewer_verdict_receipt` and `reviewer_verdict_anchor`
- `image_readback_receipt`, `subject`, `family` and `group`
- `rights_basis` and `disposition`

It checks receipt fields `lineage_path`, `reviewer_verdict_receipt` and `image_readback_receipt`.

### Binary instance files

`Roblox.rbxm` reads binary Roblox instance files.

| Task | Call |
| --- | --- |
| Test whether bytes are a binary instance file | `Roblox.rbxm.isBinary(bytes)` |
| Read the classes, the asset references and the asset IDs | `Roblox.rbxm.read(bytes)` |
| Read the instance tree | `Roblox.rbxm.instances(bytes)` |
| Get the path of one instance | `Roblox.rbxm.instancePath(tree, referent)` |

## Media

### Signatures

| Call and return | Type declarations |
| --- | --- |
| `Lute.media.convert(options: Convert, run: Run?): { ok: true } \| Failure` | [Types](../src/lute/media.luau) |
| `Lute.media.convertCommand(options: Convert): { string }` | [Types](../src/lute/media.luau) |
| `Lute.media.loudness(path: string, run: Run?): { ok: true, loudness: Loudness } \| Failure` | [Types](../src/lute/media.luau) |
| `Lute.media.probe(path: string, run: Run?): { ok: true, probe: Probe } \| Failure` | [Types](../src/lute/media.luau) |
| `Lute.media.review( input: string, output: string, size: { width: number, waveHeight: number, spectrumHeight: number }?, run: Run? ): { ok: true } \| Failure` | [Types](../src/lute/media.luau) |
| `Lute.media.reviewCommand( input: string, output: string, width: number, waveHeight: number, spectrumHeight: number ): { string }` | [Types](../src/lute/media.luau) |
| `Media.wav.encode(sampleRate: number, channels: number, samples: { number }): string` | [Types](../src/media/wav.luau) |
| `Media.wav.measure(bytes: string): Outcome` | [Types](../src/media/wav.luau) |

Public types: `Media.WavMeasurement`, `Media.WavOutcome`.
### Returns and failures

`Media.wav.measure(bytes)` returns `{ ok = true, measurement }` or `{ ok = false, diagnostic }`.
`Media.wav.encode(sampleRate, channels, samples)` returns WAVE bytes for a deterministic fixture.
`Lute.media.probe` and `loudness` return `ok` with `probe` or `loudness`; malformed output returns a diagnostic.
`convert` and `review` return `{ ok = true }` or a diagnostic. Command builders return argument arrays without effects.
Injected runners must return real process results. Runner exceptions are not converted into media acceptance.

```luau
local outcome = Media.wav.measure("invalid bytes")
assert(not outcome.ok)
```

Run [the media cases](../tests/media.lute.verify.luau) for valid audio and malformed output.


Media measures, converts and renders audio for review.

WAVE measurement supports 16-, 24- and 32-bit PCM and 32-bit float samples. It refuses incomplete
format chunks and non-finite samples. Probe metadata requires a finite nonnegative duration,
a codec name, a positive whole sample rate and a positive whole channel count.

| Task | Call |
| --- | --- |
| Measure PCM and float WAVE bytes without a process: duration, peak, RMS, silent fraction and leading silence | `Media.wav.measure` |
| Build a small WAVE fixture | `Media.wav.encode` |
| Match the level that counts a frame as silent | `Media.wav.SILENCE` is the peak level `0.001`. |
| Convert audio with ffmpeg | `Lute.media.convert` |
| Build the ffmpeg arguments without running them | `Lute.media.convertCommand` |
| Probe a file with ffprobe | `Lute.media.probe` |
| Measure integrated loudness, range and true peak | `Lute.media.loudness` |
| Write one PNG containing a waveform and a spectrogram for review | `Lute.media.review` |
| Build the review commands without running them | `Lute.media.reviewCommand` |

- Process calls take an optional runner for recorded output.
- Commands use `-y` and overwrite the selected output.

The consumer owns paths, retention, tool versions and invocation evidence.
The consumer sets thresholds, recipes and acceptance criteria. A measurement is not an audition.

---

## Process tools

### Signatures

| Call and return | Type declarations |
| --- | --- |
| `Lute.process.run(options: Options): StageOutcome` | [Types](../src/lute/process.luau) |

Public types: `Lute.MediaRun`, `Lute.MediaResult`, `Lute.MediaProbe`, `Lute.MediaLoudness`, `Lute.MediaConvert`, `Lute.MediaFailure`.
### Returns and failures

`Lute.process.run(options)` returns a `Generate.StageOutcome`.
An empty command or output path returns `rejected`. A nonzero exit or missing output returns `faulted`.
A returned outcome binds the output digest and invocation. It does not approve the content.
Read and process exceptions can propagate. The consumer owns paths and overwrite policy.

See [adapter cases](../tests/adapters.lute.verify.luau).


`Lute.process.run` runs a consumer-declared tool and binds its output bytes, tool identity and invocation to a stage outcome. The consumer supplies the command, paths and acceptance. A successful process is not proof of content quality.

## Image lane

### Signatures

| Call and return | Type declarations |
| --- | --- |
| `Image.codec.copy(image: Image): Image` | [Types](../src/image/codec.luau) |
| `Image.codec.encode(codec: Codec, image: Image): string` | [Types](../src/image/codec.luau) |
| `Image.codec.fromHueSaturation(hue: number, saturation: number, lightness: number): (number, number, number)` | [Types](../src/image/codec.luau) |
| `Image.codec.hueSaturation(r: number, g: number, b: number): (number, number, number)` | [Types](../src/image/codec.luau) |
| `Image.codec.luma(r: number, g: number, b: number): number` | [Types](../src/image/codec.luau) |
| `Image.codec.rgba(image: Image): Image` | [Types](../src/image/codec.luau) |
| `Image.codec.rounded(value: number): number` | [Types](../src/image/codec.luau) |
| `Image.codec.setLuma(pixels: buffer, base: number, wanted: number)` | [Types](../src/image/codec.luau) |
| `Image.deliver.run(config: Config, bytes: string, declaredWidth: number, declaredHeight: number): Result` | [Types](../src/image/deliver.luau) |
| `Image.host.create(options: Options): Generate.Host` | [Types](../src/image/host.luau) |
| `Image.matte.apply(image: Codec.Image, parameters: Parameters): Codec.Image` | [Types](../src/image/matte.luau) |
| `Image.matte.run(codec: Codec.Codec, bytes: string, parameters: Parameters): Result` | [Types](../src/image/matte.luau) |
| `Image.measure.artifact( config: Config, id: string, locator: string, measurement: Measurement, semanticId: string? ): Generate.Artifact` | [Types](../src/image/measure.luau) |
| `Image.measure.measure(config: Config, bytes: string): Outcome` | [Types](../src/image/measure.luau) |
| `Image.measure.pngDimensions(bytes: string): (number?, number?, string)` | [Types](../src/image/measure.luau) |
| `Image.measure.runStage(config: Config, deps: Deps, evidence: { Evidence }): Generate.StageOutcome` | [Types](../src/image/measure.luau) |
| `Image.postprocess.runStage( config: Config, deps: Deps, transform: Transform, artifacts: { Generate.Artifact } ): Generate.StageOutcome` | [Types](../src/image/postprocess.luau) |
| `Image.provider.runStage(config: Config, deps: Deps, request: Request, attempt: number): Generate.StageOutcome` | [Types](../src/image/provider.luau) |
| `Image.qa.assess(config: Config, bytes: string, declaration: Declaration, path: string): Assessment` | [Types](../src/image/qa.luau) |
| `Image.qa.gate(config: Config, deps: Deps, declarations: { Declaration }, located: { [string]: string }): Gate` | [Types](../src/image/qa.luau) |
| `Image.register.facts(image: Codec.Image): Facts` | [Types](../src/image/register.luau) |
| `Image.register.run(config: Config, bytes: string, target: Target): Result` | [Types](../src/image/register.luau) |
| `Image.request.encode(config: Config, document: unknown): string` | [Types](../src/image/request.luau) |
| `Image.review.runStage(config: Config, request: Request, artifacts: { Generate.Artifact }): Generate.StageOutcome` | [Types](../src/image/review.luau) |
| `Image.review.stage(config: Config, request: Request, artifacts: { Generate.Artifact }): Outcome` | [Types](../src/image/review.luau) |

Public types: `Image.Codec`, `Image.Digest`, `Image.Decoded`, `Image.Image`, `Image.Rgba`, `Image.DeliverConfig`, `Image.DeliverFacts`, `Image.DeliverResult`, `Image.DeliverSuccess`, `Image.HostBinding`, `Image.HostMatteBinding`, `Image.HostRegisterBinding`, `Image.HostDeliverBinding`, `Image.HostDeps`, `Image.HostOptions`, `Image.HostTool`, `Image.HostTools`, `Image.MatteParameters`, `Image.MatteResult`, `Image.MatteSuccess`, `Image.MeasureBounds`, `Image.MeasureConfig`, `Image.MeasureOutcome`, `Image.MeasureEvidence`, `Image.Measurement`, `Image.PostprocessConfig`, `Image.PostprocessKind`, `Image.PostprocessTransform`, `Image.ProviderConfig`, `Image.ProviderDeps`, `Image.ProviderPaths`, `Image.ProviderRequest`, `Image.ProviderRunResult`, `Image.QaAssessment`, `Image.QaPair`, `Image.QaRefusal`, `Image.QaConfig`, `Image.QaDeclaration`, `Image.QaDeps`, `Image.QaGate`, `Image.QaThresholds`, `Image.QaHueBand`, `Image.RegisterConfig`, `Image.RegisterResult`, `Image.RegisterSuccess`, `Image.RegisterDeclarationTarget`, `Image.RegisterFacts`, `Image.RegisterTarget`, `Image.RegisterValues`, `Image.RequestConfig`, `Image.ReviewConfig`, `Image.ReviewOutcome`, `Image.ReviewRequest`.
### Returns and failures

`Image.host.create` returns a `Generate.Host`. Routing and stage outcomes retain the declared stage status.
`pngDimensions` returns width, height and an empty diagnostic, or two nils and a diagnostic.
`measure` returns `ok` with a measurement or a diagnostic. `artifact` returns a bound artifact record.
Transform `run` calls return `ok` with transformed bytes and facts, or a diagnostic.
`matte.apply` returns an image directly and requires valid pixels and parameters.
QA returns measured assessments or a gate result with explicit refusals. Missing required thresholds raise.
`request.encode` returns sorted text. It grants no execution authority.
Pixel helpers return copies or scalar measurements; `setLuma` changes the supplied pixel buffer.
`review.stage` returns a review outcome; `runStage` maps it to a stage outcome.
Provider, postprocess and measurement stage calls return `Generate.StageOutcome` with explicit rejection or fault details.

```luau
local width, height, diagnostic = Image.measure.pngDimensions("invalid bytes")
assert(width == nil and height == nil and diagnostic ~= "")
```

Run the [image example](../examples/image-tools.luau), [lane cases](../tests/image-lane.lute.verify.luau)
and [transform cases](../tests/image-transforms.lute.verify.luau).


The image lane binds one provider attempt, deterministic transforms, measured checks and exact review views.
The consumer supplies every threshold, visual target and transform parameter. Generate supplies the measurements and the generic checks.
Acceptance follows [the review contract of the brief](#generatebrief).

| Task | Call |
| --- | --- |
| Encode a recipe document | `Image.request.encode` |
| Route the declared stages to tools | `Image.host.create` |
| Invoke the provider once | `Image.provider.runStage` |
| Run a pinned postprocess script | `Image.postprocess.runStage` |
| Measure the size of a PNG | `Image.measure.pngDimensions` |
| Check a PNG against a declared size envelope | `Image.measure.measure` |
| Record a measured PNG as an artifact | `Image.measure.artifact` |
| Measure the declared evidence in a stage | `Image.measure.runStage` |
| Read the media type of a PNG artifact | `Image.measure.MEDIA_TYPE` |
| Assess one image against declared checks | `Image.qa.assess` |
| Gate one run against its declared artifact list | `Image.qa.gate` |
| Repair a cutout | `Image.matte.run` and `Image.matte.apply` |
| Register colour to a declared target | `Image.register.run` |
| Read the colour and value facts of an image | `Image.register.facts` |
| Resize to a declared size | `Image.deliver.run` |
| Stage a blind review packet | `Image.review.stage` and `Image.review.runStage` |
| Start from the default blindness configuration | `Image.review.DEFAULT_CONFIG` |
| Copy, convert or encode pixels | [Pixel helpers](#pixel-helpers) |

### Execution

The consumer builds typed `HostBinding` values for the stages it declares in a Generate plan.
`Image.host.create` routes those stages and refuses mutating stages; it has no publication authority.
`Image.provider.runStage` spends one invocation and preserves references while confining output paths.
`Image.postprocess.runStage` pins the script bytes and refuses an existing output, silent or nonzero execution and rewritten input.
The consumer owns recipe loading, schema validation and transform algorithms.

`Image.request.encode(config, document)` encodes consumer data with sorted object keys and a final newline.
The config supplies `indent` and a scalar `serialize` function. Encoding grants no execution or acceptance.
Use `QaDeclaration` for image checks and `HostBinding` for execution; there is no intermediate recipe representation.
Read transform bytes and typed facts only after a check that `ok` is `true`.

### Thresholds

`Image.qa` supplies no default pass limit or visual target. The consumer declares every threshold in `QaConfig.thresholds`.
A missing or non-numeric threshold raises an error that names the field.
The table lists each threshold and the check or measurement that reads it.

| Threshold | Used by |
| --- | --- |
| `opaqueAlpha` | Opacity census. A texel at this alpha or above is opaque. |
| `transparentAlpha` | Opacity census, layout, luminance statistics and colour statistics. A texel at this alpha or below is transparent. |
| `keyResidueSaturation` | Opacity census. A transparent texel whose RGB spread reaches this value holds saturated colour. |
| `gutterLumaRange` | Layout. A line whose luminance spread stays within this range is a gutter. |
| `brightMaximaLuma` | Bright maxima. A local maximum must exceed this luminance. |
| `chromaSaturationFloor` | Colour statistics. A pixel above this saturation counts as chromatic. |
| `maxWrapSeamRatio`, `maxInteriorSeamRatio`, `maxFractionalSeamRatio` | The tile checks `tileability`, `interior-seam` and `fractional-interior-seam`. |
| `minEdgeBlurRatio`, `maxEdgeMirrorCorrelation`, `maxHfScreenPatternPeakRatio` | The tile checks `edge-blur-band`, `edge-mirror-symmetry` and `hf-screen-pattern`. |
| `minMedianLuma` | The tile check `median-luma-floor`. |
| `maxUnlitVignetteRatio`, `maxUnlitLightingGradient` | The unlit checks `unlit-vignette` and `unlit-gradient`. |
| `maxBrightMaximaFraction` | The check `bright-maxima`. |
| `minSemiTransparentFraction`, `maxKeyResidueFraction`, `maxHaloRatio` | The transparent-background checks `opacity-census`, `key-residue` and `halo`. |
| `maxPanels`, `minGutterBand` | The single-subject check `layout`. |
| `minPairedLuminanceRatio`, `maxPairedLuminanceRatio`, `minPairedRegistrationCorrelation` | The paired-group checks of `Image.qa.gate`. |
| `warnVignetteRatio`, `warnLightingGradient`, `warnLumaSpread` | The three warnings. |

### Measurements

`Image.qa.assess(config, bytes, declaration, path)` records these facts for every decoded image.
The inputs of a measurement are the image and the listed thresholds. The measurement windows are fixed.

| Measurement | Facts | Inputs and fixed window |
| --- | --- | --- |
| Tileability | `wrapSeamDeltaX`, `wrapSeamDeltaY`, `interiorAdjacentDeltaX`, `interiorAdjacentDeltaY`, `wrapSeamRatioX`, `wrapSeamRatioY`, `wrapSeamRatio` | Luminance of the first and last column and row. |
| Interior seams | `maxInteriorColumnDelta`, `medianInteriorColumnDelta`, `maxInteriorColumnRatio`, `maxInteriorColumnX`, the same four for rows, `fractionalColumnRatio`, `fractionalColumnX`, `fractionalRowRatio`, `fractionalRowY` | Column and row deltas. The fractional hit looks within 3 px of one quarter, one third, one half, two thirds and three quarters. |
| Opacity census | `hasOpacityChannel`, `opaqueFraction`, `transparentFraction`, `semiTransparentFraction`, `keyResidueFraction`, `keyResidueTexels`, `boundaryLuminance`, `interiorLuminance`, `haloRatio` | `opaqueAlpha`, `transparentAlpha`, `keyResidueSaturation`. |
| Layout | `rowPanels`, `columnPanels`, `panelCount`, `borderBandRows`, `borderBandColumns` | `transparentAlpha`, `gutterLumaRange`, `minGutterBand`. A panel is one subject region between gutter lines. |
| Luminance statistics | `vignetteRatio`, `lightingGradient`, `luma5`, `luma50`, `luma95`, `lumaSpread` | `transparentAlpha`. The centre is the middle half of each axis. |
| Bright maxima | `brightMaximaTexels`, `brightMaximaFraction` | `brightMaximaLuma`. A neighbour check over eight texels. |
| Colour statistics | `meanHue`, `meanSaturation`, `hueBandFraction` | `transparentAlpha`, `chromaSaturationFloor`. `hueBandFraction` exists only when the declaration has a `hueBand`. |
| Edge blur | `edgeBlurBand`, `edgeLocalStd`, `interiorLocalStd`, `edgeBlurRatio` | Band of 32 px or one quarter of the shorter side, whichever is smaller. |
| Edge copies | `edgeMatchBand`, `duplicatedEdgeRows`, `mirroredEdgeRows`, `duplicatedEdgeColumns`, `mirroredEdgeColumns` | Band of 8 px or half of the shorter side. |
| Edge mirror | `edgeMirrorBand`, `edgeMirrorRowsCorrelation`, `edgeMirrorColumnsCorrelation`, `edgeMirrorRowsSpatialCorrelation`, `edgeMirrorColumnsSpatialCorrelation`, `edgeMirrorCorrelation` | Band of 16 px or half of the shorter side. |
| High-frequency screen | `hfScreenPatternPeak`, `hfScreenPatternMedian`, `hfScreenPatternPeakRatio` | Periods of 2, 3, 4, 5, 6, 8, 10, 12 and 16 px on up to 8 rows and 8 columns. |

### Checks

A check refuses when its condition holds. Each refusal has a `fact` (the code), a `detail`, the measured value and the threshold.
The `declaration` of an artifact selects the checks.

| Code | Declaration | Refuses when |
| --- | --- | --- |
| `decode` | none | The consumer codec cannot decode the bytes. |
| `tileability` | `tiles` | `wrapSeamRatio` exceeds `maxWrapSeamRatio`. |
| `interior-seam` | `tiles` | An interior column or row ratio exceeds `maxInteriorSeamRatio`. |
| `fractional-interior-seam` | `tiles` | A fractional ratio exceeds `maxFractionalSeamRatio`. |
| `edge-blur-band` | `tiles` | `edgeBlurRatio` is below `minEdgeBlurRatio`. |
| `duplicate-edge` | `tiles` | An opposing edge band is identical or mirrored. |
| `hf-screen-pattern` | `tiles` | `hfScreenPatternPeakRatio` exceeds `maxHfScreenPatternPeakRatio`. |
| `edge-mirror-symmetry` | `tiles` | `edgeMirrorCorrelation` exceeds `maxEdgeMirrorCorrelation`. |
| `median-luma-floor` | `tiles` without `dark` | `luma50` is below `minMedianLuma`. |
| `unlit-vignette` | `unlit` | `vignetteRatio` exceeds `maxUnlitVignetteRatio`. |
| `unlit-gradient` | `unlit` | `lightingGradient` exceeds `maxUnlitLightingGradient`. |
| `hue-band` | `hueBand = { fromDegrees, toDegrees, maxFraction }` | `hueBandFraction` exceeds `maxFraction`. A band with `fromDegrees` above `toDegrees` wraps through 0. |
| `bright-maxima` | `limitBrightMaxima` | `brightMaximaFraction` exceeds `maxBrightMaximaFraction`. |
| `declared-width`, `declared-height` | `declaredWidth`, `declaredHeight` | The delivered size differs from the declared size. |
| `register-saturation` | `registerTarget` | `meanSaturation` exceeds `registerTarget.saturationCeiling`. |
| `register-value-p5`, `register-value-p50`, `register-value-p95` | `registerTarget` | A luminance percentile lies outside its declared `min` and `max`. |
| `opacity-channel` | `transparentBackground` | The image has no transparency. |
| `opacity-census` | `transparentBackground` | `semiTransparentFraction` is below `minSemiTransparentFraction`. |
| `key-residue` | `transparentBackground` | `keyResidueFraction` exceeds `maxKeyResidueFraction`. |
| `halo` | `transparentBackground` | `haloRatio` exceeds `maxHaloRatio`. |
| `layout` | `singleSubject` | `panelCount` exceeds `maxPanels`. |

A warning never refuses. The three warnings read `vignetteRatio`, `lightingGradient` and `lumaSpread`.
`Image.qa.gate` also refuses these conditions:

- The delivered file count differs from the declared count.
- A declared file is missing.
- A paired group does not contain exactly two images.
- A pair has a mean-luminance ratio or registration correlation outside its thresholds.

### Pixel helpers

`Image.codec` holds the pixel helpers that the measurements and transforms use. The consumer supplies the container codec.

| Task | Call |
| --- | --- |
| Copy an image as RGBA | `Image.codec.copy(image)` |
| Convert an RGB or RGBA image to an RGBA copy | `Image.codec.rgba(image)` |
| Encode an image through the consumer codec | `Image.codec.encode(codec, image)` |
| Get the luminance of an RGB value | `Image.codec.luma(r, g, b)` |
| Round a measurement to four decimals | `Image.codec.rounded(value)` |
| Set the luminance of one pixel in a buffer | `Image.codec.setLuma(pixels, base, wanted)` |
| Get the hue, saturation and lightness of an RGB value | `Image.codec.hueSaturation(r, g, b)` |
| Get an RGB value from a hue, a saturation and a lightness | `Image.codec.fromHueSaturation(hue, saturation, lightness)` |

### Transforms and review

Transforms change pixels deterministically. Review prepares blind evidence for one reviewer.

- `Image.matte.run(codec, bytes, parameters)` repairs a cutout with the declared `interiorDistance`, `boundaryDistance` and `featherRadius`. It refuses a source without an opacity channel. The consumer declares the parameters. A host that binds `matte` needs `matteParameters`.
- `Image.register.run(config, bytes, target)` changes colour towards the declared target `hue`, `saturationCeiling` and percentile `values`. The facts count pixels above alpha 5.
- `Image.deliver.run(config, bytes, declaredWidth, declaredHeight)` resamples to the declared size with a Lanczos filter of window 3.
- Each transform records the digests and the facts before and after. It is deterministic.
- A provider `Request` names its output `group`. The `group` is a collection name in lower kebab-case. It becomes a directory under the output root and the first part of the candidate identity.
- Consumer codecs implement container decoding and encoding.
- `Image.review.stage` binds exact evidence views. It rejects evidence that reveals the producer, prompt or previous verdict.

Image checks and transforms do not supply a review decision.
Review identity strings alone do not prove that an independent human or agent reviewed the content.

## Brief diagnostics

### Signatures

| Call and return | Type declarations |
| --- | --- |
| `Consumer.scanSource(path: string, source: string, rulesets: { Consumer.Ruleset }?) -> { Consumer.Finding }` | [Types](../src/consumer/init.luau) |


Public types: `Consumer.Finding`, `Consumer.Ruleset`.
The scan returns an empty list when no textual rule matches. It does not parse or execute the brief.
An unknown ruleset raises. Ruleset `roblox` adds native-specific findings.

```luau
local findings = Consumer.scanSource("fixture.generate.luau", "return {}")
assert(#findings > 0)
```

See [the diagnostic cases](../tests/lint.lute.verify.luau).


`Consumer.scanSource(path, source, rulesets?)` scans the text of an authored brief and returns findings. Each finding has a `code`, a `path`, a `message` and a `fix`.
The default ruleset names no host. `Consumer.RULESETS` lists the optional rulesets. [Lint](lint.md) owns the codes.

## Fixture host

### Signatures

| Call and return | Type declarations |
| --- | --- |
| `Host.fake.create(options: Options?): Host` | [Types](../src/host/fake.luau) |
The fixture records run and compensation calls. Unspecified stage outcomes use its default fixture response.
Use it for deterministic contracts. It establishes no provider, native output or rights evidence.

```luau
local host = Host.fake.create()
```

The [accepted-manifest example](../examples/accepted-manifest.generate.luau) exercises a complete fixture pipeline.


`Host.fake.create(options)` returns a `Generate.Host` for fixtures. The consumer supplies stage outcomes, compensation faults, capabilities and environment.
It does no I/O.
