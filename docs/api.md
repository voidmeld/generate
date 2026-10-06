# API reference

Generate turns a brief into a plan, a retained candidate, a review decision and a receipt.
Core owns those records. The consumer supplies art direction, host operations and authority.

| Task | Start here |
| --- | --- |
| Describe an asset and run its stages | [Brief, plan and execution](#brief-plan-and-execution) |
| Review exact bytes and select delivery | [Review and delivery](#review-and-delivery) |
| Declare the destination of a brief and record its outcome | [Delivery destination and publication records](#delivery-destination-and-publication-records) |
| Use Roblox: save, publish, grant, read back or audit assets | [Roblox adapter](#roblox-adapter) |
| Measure, convert or render audio for review | [Media](#media) |
| Bind a content compiler, a process tool or a reviewer | [Content, process and reviewer adapters](#content-process-and-reviewer-adapters) |
| Produce and review an image | [Image lane](#image-lane) |
| Check an authored brief | [Brief diagnostics](#brief-diagnostics) |

The examples use the public package roots. Replace the path with the location of your mounted package:

```luau
local Generate = require(path.to.generate.core)
```

The exported Luau types define the record fields. This page explains their contracts.
Every public function appears here with its full name. The [architecture](architecture.md) page owns the public package map. The [getting started guide](getting-started.md) owns the workflow.
The [terms](index.md#terms) define the words that this page uses.

---

## Brief, plan and execution

A brief declares an asset, a plan orders its stages and execution runs them under authority.

### `Generate.brief`

`brief(draft) -> Brief`

`Generate.brief` declares one asset. It normalizes a schema-v1 brief: identity, kind, intent, delivery, review and provenance.

- Every contract requires exactly one decision. One decision covers the entire rubric.
- The contract has no decision count and no rule. `independence` normalizes to `required`.
- Review declares the rubric identity and fingerprint, the canonical views and the blindness.
- `independence = "optional"` explicitly permits a producer inspection in a shared context. Record the real actor and `blind = false`. Consumer policy decides which intermediate inputs allow this mode. Finished assets normally keep required independence.
- A change to the contract changes the brief fingerprint. It invalidates earlier receipt bindings. A receipt that an earlier version made does not verify, because the review fields changed.
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

`Generate.execute` runs a plan and records a receipt. It intersects the host capabilities with the consumer authority. It checks destinations and budgets, and dispatches stable stage idempotency keys.
If a stage fails, completed mutations compensate newest first. A post-change fault must return its opaque rollback handle.

- Receipts have `schemaVersion` `2`. They bind stages, artifact identities, invocations, derivations, review, economics and recovery.
- Optional economics records keep the calls, costs and reviewers that the host reports. Unknown values stay absent.
- Execution measures stage duration. The consumer owns rollups and provider scheduling.
- `Generate.canonical(value)` encodes a record deterministically. `Generate.fingerprint(value)` hashes that encoding. `Generate.receiptFingerprint(receipt)` recomputes the binding of a receipt. A fingerprint is not a signature and grants no authority.
- Stage metadata is an open `{ [string]: unknown }` data map that receipt ingestion checks. The consumer narrows extension fields before use.
- QA facts contain strings, numbers and booleans. Optional measurements stay absent. Generate does not invent them.

### `Generate.continueReview`

`continueReview(brief, plan, receipt, decisions) -> Receipt`

`Generate.continueReview` adds review decisions to a produced receipt. It resolves new review for one unchanged, completed `produced` receipt. It does not invoke native work again.
It refuses receipt, brief or plan drift, unknown packets, unfinished runs and completed mutations.
Later review does not change the production timing and cost.

---

## Review and delivery

Review binds one decision to the exact bytes of a candidate, and delivery selects the approved bytes.
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
- A resolved review has `decisions` (the eligible decisions), `excluded`, `disposition` (`approved`, `rejected`, `unresolved`, `incomplete` or `stale`) and `resolution`. It records exclusions for self-review, duplicate actors, drift, and unmet blindness or independence. Each excluded decision names its actor and reason.
- An extra submission for the same packet, including a duplicate, leaves review unresolved.
- Changed output makes the prior approval stale. Technical production alone returns `produced`.

### Revisions and provenance

Revisions keep consecutive candidate revisions. Provenance records lineage and rights.

| Task | Call |
| --- | --- |
| Build the ledger of one candidate from its revision entries | `Generate.revisionLedger(candidateId, entries)` |
| Draft the next candidate revision from a ledger | `Generate.rollCandidate(ledger, draft)` |
| Normalize and validate where a candidate came from | `Generate.derivation(draft)` |
| Normalize the rights facts of a candidate | `Generate.rights(draft)` |
| List the lineage and rights faults that block delivery | `Generate.provenanceFaults(derivation, contract, byArtifactId)` |

An open head cannot roll. To supersede an approved head, say so explicitly.
Derivations and rights do not invent rights facts.

### `Generate.manifest`

`manifest(receipt, artifactIds) -> DeliveryManifest`

`Generate.manifest` lists the approved artifacts for delivery. It selects the exact approved semantic delivery with the required provenance. Its entries name `reviewId` and `reviewFingerprint`.
The consumer owns registry adoption and runtime acceptance.
See [accepted delivery](../examples/accepted-manifest.generate.luau) and [revision rollover](../examples/candidate-revision.luau).

### Quotas and capture evidence

Quotas compare measured values with ceilings. Capture brackets check that evidence follows the declared capture order.

| Task | Call |
| --- | --- |
| Compare measured values and a kind with their declared ceilings and allowed kinds | `Generate.evaluateQuota` |
| Declare the ordered poses of a capture | `Generate.evidenceBracket` |
| Check captured evidence against the declared bracket | `Generate.bindEvidence` |
| List the checked evidence in capture order | `Generate.evidenceManifest` |
| Match a refusal reason of a bracket | `Generate.EVIDENCE_BRACKET_REASONS` |

`Generate.evaluateQuota` takes values that the consumer measured. It does not measure native assets and does not choose budgets.
A bracket requires the exact declared capture order, poses and digest mode. A refused bracket yields no manifest. A bracket does not capture or hash bytes.

See [quotas](../examples/asset-quota.generate.luau) and [capture brackets](../examples/evidence-bracket.generate.luau).

---

## Delivery destination and publication records

A destination says where a brief delivers. A publication record says what happened there.

### Declare the destination

A destination tells core where a brief delivers. A brief can declare an optional destination in its `delivery` contract:

- `delivery.destination` has an `adapter` name in lowercase and a `descriptor` data table.
- `delivery.hostVerification` is a boolean. It defaults to `false`. It needs a destination.

Core does not read the descriptor. The adapter that the `adapter` field names owns and validates it.
Core refuses a descriptor with a secret-shaped key or a value that is not data.
Credentials are never brief values. A descriptor can carry only the name of a credential.
The destination is a record. Generate does not perform the publication.

### Record the outcome

A `PublicationRecord` is the delivery receipt of one destination. It contains these items:

- the `disposition`, which is a name that the adapter chooses, and the `state`
- the `contentId` and `version` that the destination assigned, and the `readback` of the destination
- the `credential` name and a `false` exposure attestation
- the attempt journal, the compensation journal, the stages and the optional economics
- `facts`, an adapter-owned data table
- an optional `verification`, `verificationRequest` and `verificationCompletion`

A record is always `quarantined`. Promotion is the decision of the consumer.
`dryRun` and `placeholder` are explicit booleans.

### States

The state of a record says how far its destination settled.

| State | Meaning |
| --- | --- |
| `pending` | The destination has not settled. Confirm it later. |
| `confirmed` | The destination settled. |
| `reconciled` | Source-bound read-only evidence recovered a stopped record. Confirm it later. |
| `stopped` | The record is final. It is a refusal, a dry run, a partial result or a failed recovery. |

- `Generate.attachPublication(receipt, record)` binds a quarantined, secret-free record to an unchanged receipt. It refuses a receipt that already records a non-dry-run attempt.
- `Generate.confirmPublication(receipt, record)` replaces only a `pending` or `reconciled` record.
- `Generate.reconcilePublication(receipt, record)` accepts only a source-bound recovery of a `stopped` record. That record has one failed-readback create and one failed compensation. The new record keeps the attempt history.
- `Generate.publicationFault(record)` returns the first generic fault of a record, or `nil`.

Each call returns a receipt with a new fingerprint.
The consumer must use records that its own delivery path produces. It must not substitute hand-authored acceptance assertions.

### Host verification

A host verification record is an observation that the delivered content was exercised in a named host build.
It has a `contentId`, a `hostBuild`, an observation window, adapter `measurements`, scanned `diagnostics` and a `verified` or `refused` disposition.
A `refused` record names a refusal reason.

- A `verificationRequest` binds the exact publication identity, the source receipt, the host and the host build. It defers verification.
- `confirmPublication` completes a request only with a `verificationCompletion` that binds the request and the pending receipt.
- `confirmPublication` can also rebind an uncompleted request to a different `hostBuild`. It keeps the prior lineage in `verificationRebindings`.
- `Generate.hostVerified(receipt)` is `true` only for an accepted receipt with a confirmed, non-dry-run, non-placeholder record and a `verified` observation of the same `contentId`.

## Roblox adapter

The Roblox adapter binds Generate to Roblox: it saves, publishes, grants, reads back and audits assets.
It validates Roblox facts and records them. The consumer supplies every transport, credential and file operation.
Each module does one job.

| Task | Module |
| --- | --- |
| Save a reviewed file or native object without a brief | [`Roblox.delivery`](#direct-delivery) |
| Publish one planned asset under a grant, with readback and rollback | [`Roblox.assetPublication`](#asset-publication) |
| Describe a Roblox destination and record its publication facts | [`Roblox.publicationRecord`](#publication-records) |
| Let a universe use assets that your creator owns | [`Roblox.permissionGrant`](#permission-grants) |
| Read an asset, its owner and its moderation state | [`Roblox.assetReadback`](#asset-readback) |
| Prove the provenance of a reference image and add its row to a manifest | [`Roblox.referenceProvenance`](#reference-provenance) |
| Audit the reference rows of a manifest | [`Roblox.assetAudit`](#asset-audit) |
| Read a binary instance file | [`Roblox.rbxm`](#binary-instance-files) |
| Keep exact Studio calls and captures | [`Roblox.nativeTranscript`](#native-transcripts) |
| Convert a size to studs | [`Roblox.units`](#publication-records) |

`Roblox.delivery` and `Roblox.assetPublication` both create assets through the Assets API.
Use `Roblox.delivery` for one reviewed file or native object. It needs no brief.
Use `Roblox.assetPublication` for a plan stage. It needs a brief, a grant and rollback data.

The transport types are `Roblox.CloudRequest`, `Roblox.CloudResponse` and `Roblox.CloudSend`.
`send(request)` receives a `CloudRequest` and returns a `CloudResponse` with `ok`, `status` and `body`.

### Publication records

`Roblox.publicationRecord` describes a Roblox destination and maps Roblox facts onto the [publication records](#delivery-destination-and-publication-records). Core never reads them.

| Task | Call |
| --- | --- |
| Declare a destination | `Roblox.publicationRecord.destination(draft)` returns a `Generate.Destination` with the adapter name `roblox`. |
| Read a destination | `Roblox.publicationRecord.readDestination(destination)` returns the typed fields. |
| Build the facts of a record | `Roblox.publicationRecord.facts(facts)` returns the `facts` table. It holds `universeGrants`, `dependencyGrants` and an optional `accessClosure`. |
| Read the facts of a record | `Roblox.publicationRecord.readFacts(record)` returns the typed facts. |
| Build a verification request | `Roblox.publicationRecord.request(draft)` maps the creator, universes, place, consumer, Studio version and build onto the generic request. |
| Find the first fault of a record | `Roblox.publicationRecord.recordFault(record)` |
| Attach a record to a receipt | `Roblox.publicationRecord.attach(receipt, record)` |
| Confirm a pending record | `Roblox.publicationRecord.confirm(receipt, record)` |
| Reconcile a stopped record | `Roblox.publicationRecord.reconcile(receipt, record)` |
| Test host verification | `Roblox.publicationRecord.hostVerified(receipt)` |
| Match a refusal reason | `Roblox.publicationRecord.REFUSAL_REASONS` lists the reasons. |
| Convert a size to studs | `Roblox.units.studs(size)` converts a size in metres, centimetres or millimetres. One stud is 0.28 metres. |

The destination descriptor has a `creator` (`group` or `user`), an `assetType`, a `visibility` (`private` or `restricted`), a `credentialName`, and optional `assetId`, `displayName`, `description`, `grantUniverses` and `verifyDependencies`.
Public visibility is refused. `verifyDependencies` needs `grantUniverses`.

The Roblox functions run the Roblox checks and then the generic calls.
`Roblox.publicationRecord.confirm` also checks the bound access closure of an `access-closure-pending` record.
`Roblox.publicationRecord.reconcile` accepts only a `failed-compensation` record with unattempted access.

A brief declares `constraints.maxSize = { x, y, z, unit = "m" }`. The unit defaults to metres. Convert the size in the adapter, not in the brief.

### Direct delivery

`Roblox.delivery` saves a reviewed file or a native Studio object and returns a usable asset ID and an optional version.
It has no brief, plan, receipt or transcript.
It is plain Luau with no `require`, so one source file can also load in Studio.
The consumer injects every effect through `Roblox.DeliveryConfig`:

- `creator`: `{ kind = "group" | "user", id }`. It is required. Generate never defaults it, never reads it from the environment and never falls back from a group to a user.
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
Use a durable store with atomic `create` and with successful writes before effects.
A record is recovery data. It is not an accepted core receipt.
`stop` ends the assigned action. Recovery needs reconciled evidence.

#### Files

Use `Roblox.delivery.upload` to save one reviewed file.

`Roblox.delivery.upload(config, request)` takes these fields:

- `label`, `bytes`, `name`, `description`
- `format`: `png`, `wav`, `mp3`, `ogg`, `rbxm` or `rbxmx`. The binary and XML instance formats request `Animation`, not `Model`.
- `review`: `by`, `verdict = "complies"`, `shows`, and the `sha256` of those exact bytes

The function runs these steps:

1. It checks the review.
2. It writes the record before it sends.
3. It sends one Open Cloud create.
4. It polls the operation.
5. It reads the asset back for creator, type, version and moderation.

The record under the SHA-256 of the bytes holds the source label, hash, size, reviewer, creator, privacy, authority evidence, operation, asset ID, version and moderation.
A repeated call resumes from the record.

- `status(config, reference, assetType)` reads an operation path or an asset ID. It does not update a stored attempt.
- `queue(config, items, options)` uploads one item at a time. It stops at the first result that is not approved and reports each `Row` through `options.log`. Each item prepares its own request lazily.

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
| Record an operation or asset ID after an ambiguous upload | `Roblox.delivery.attach(config, key, reference)` |
| Save one native object | `Roblox.delivery.native.save(config, host, request)` |
| Record an asset ID after an ambiguous native save | `Roblox.delivery.native.attach(config, key, assetId)` |
| Keep native records on a Studio Instance | `Roblox.delivery.native.attributeStore(instance, httpService)` |


### Asset publication

`Roblox.assetPublication` publishes one planned asset through the Assets API under a grant, reads it back and keeps the data for rollback.
The grant authorizes exactly one attempt. A failure after the request left is never sent again.

| Task | Call |
| --- | --- |
| Check a grant: creator, asset type, visibility, action and attempt limit | `Roblox.assetPublication.grant(draft)` |
| Build the Assets API operations with a poll budget | `Roblox.assetPublication.operations(options)` |
| Run one granted publication as a stage and return its outcome | `Roblox.assetPublication.publish(operations, brief, artifacts, draft, idempotencyKey)` |
| Run several granted stages in order, with compensation | `Roblox.assetPublication.transaction(adapter, stages, fingerprint)` |
| Name the disposition of a stage outcome | `Roblox.assetPublication.classify(outcome)` |
| Match a disposition | `Roblox.assetPublication.DISPOSITIONS` lists every name that a transaction can return. |

A grant has a `schemaVersion` of `1`, an `id`, an `actor`, a `policy`, the `briefFingerprint`, an `idempotencyKey`, the `artifactDigest`, the `semanticId`, a `target`, an `assetType`, a `creator`, an `action` (`create` or `update`), an optional `assetId`, a `visibility` (`private` or `restricted`), `permissionChanges = false` and `maxAttempts = 1`.
It may also carry a `displayName` and a `description`. Both are then required.
An update grant binds one existing asset. A create grant binds none.

`operations(options)` needs `send`, `toolVersion`, `encode`, `decode`, `readArtifact` and `maxPolls`.
Optional fields are `waitBeforePoll`, `moderationPollBudget` (default `3`) and `baseUrl`.
It returns an adapter with `publish`, `readback` and `compensate`.

The functions follow these rules:

1. An update first reads the asset and its current version, so that a rollback is possible.
2. The adapter sends one create or update request and polls the operation within the poll budget.
3. It reads the asset back and compares the creator, type, names, visibility and version with the grant.
4. A rejected or unreadable result returns a fault with the rollback token, when one exists.
5. A moderation state that is still pending stays `moderation-pending`. The adapter never compensates it.
6. `transaction` stops at the first stage that is not `published`. It then compensates earlier stages, newest first.

The dispositions are `published`, `refused`, `ambiguous`, `moderation-delayed`, `moderation-pending`, `timed-out`, `partial`, `failed-readback` and `failed-compensation`.
A `transaction` returns the `disposition`, the attempts, the compensations and the delivered metadata. It never retries.

### Permission grants

`Roblox.permissionGrant` lets a universe use assets that one creator owns. It checks authority, sorts the assets and records each request before and after it runs.

| Task | Call |
| --- | --- |
| Read the group membership and roles of the credential owner and record them as facts | `Roblox.permissionGrant.subjectAuthority(options, credential, universeId, groupId)` |
| Split read-back assets into those that the owner can grant and external assets | `Roblox.permissionGrant.census(records, owner)` |
| Split asset IDs into groups of one request | `Roblox.permissionGrant.chunks(assetIds, size)` |
| Build the request for one group | `Roblox.permissionGrant.prepare(encode, universeId, assetIds)` |
| Send one request and check that the response confirms exactly the requested assets | `Roblox.permissionGrant.attempt(send, decode, prepared)` |
| Run all chunks of one transaction | `Roblox.permissionGrant.grant(transaction)` |
| Compare a prepared request with a stored one | `Roblox.permissionGrant.ENDPOINT` and `Roblox.permissionGrant.MAX_ASSETS_PER_REQUEST` |
| Set the decision of a credential record | `Roblox.permissionGrant.CREDENTIAL_DECISION` |
| Match an authority decision | `Roblox.permissionGrant.DECISIONS` has `bound` and `refused`. |
| Match an authority reason | `Roblox.permissionGrant.REASONS` has `membershipAbsent` and `scopesUncovered`. |

- `chunks` orders the IDs, refuses duplicates and non-numeric IDs, and allows at most `MAX_ASSETS_PER_REQUEST` IDs in a group.
- `prepare` builds one `PATCH` request with the action `Use`. It carries the header names and the sorted asset IDs.
- `grant(transaction)` records each chunk before and after its attempt. It refuses to repeat a settled attempt. A terminal receipt that cannot be written refuses a retry.
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
`options` has `send`, `decode` and `owner`. Optional fields are `sendPublic`, `sleep`, `clock`, `paced`, `baseUrl`, `detailsBaseUrl`, `maxRetries` (default `5`) and `minIntervalSeconds` (default `0.55`).
The adapter retries only a throttled read. It falls back to the public details only when the record refuses the read and `sendPublic` exists.

### Reference provenance

`Roblox.referenceProvenance.record` proves the provenance of one reference image and adds its row to a manifest text.
A reference image is an image that guides generation. The row binds these facts:

- the committed source file of the image, its tool, model, prompt, date and SHA-256, as read from a lineage file
- the uploaded asset, as proved by a recorded readback
- exactly one independent reviewer verdict, with its receipt and anchor
- a disposition that the consumer names

`record(config, codecs, files, draft)` runs the checks and returns an `Outcome`. It writes only when all checks pass:

1. The readback names the declared creator, an approved moderation state, a closed dependency census and the same asset ID.
2. The image is a committed PNG under `config.referenceRoot`. Its bytes match the SHA-256 of its lineage row. Exactly one lineage file names it.
3. The receipt paths are committed paths. A path that starts with `.` or has a hidden segment is refused, because a fresh checkout does not carry it.
4. The disposition is not the terminal disposition. The consumer sets that one after the dependent content is published and linked back.
5. The renderer reproduces the rendered table from the current manifest. Then the row is spliced into the manifest text. An existing key is never overwritten.

The `config` names the creator `owner`, the manifest `sections`, the `referenceSection` that receives the rows, the `manifestPath`, the `renderedPath`, the `lineagePath` (a file, a directory or a list of files), the `referenceRoot` and the consumer `render` function. No section name has a default.
Optional fields are `terminalDisposition` (default `accepted`) and `activeState` (default `Active`).
The row has these keys. The audit reads the same keys.

| Key | Value |
| --- | --- |
| `id` | The key of the row. |
| `committed_source_path` | The committed path of the reference image. |
| `source_sha256` | The SHA-256 of the image bytes. |
| `generation_tool`, `generation_model`, `generation_date` | From the lineage row. |
| `lineage_path` | The lineage file that names the image. |
| `prompt` or `prompt_path`, and `prompt_sha256` | The inline prompt or the committed prompt file, and its SHA-256. |
| `image_asset_id`, `source_asset_id` | The uploaded asset and the asset that the image came from. |
| `owner`, `owner_id`, `state` | The declared creator and the active state. |
| `creator_transfer_pending` | Always `false`. |
| `moderation_state` | From the readback. |
| `image_readback_receipt` | The committed path of the readback receipt. |
| `reviewer_verdict_ids`, `reviewer_verdict_receipt`, `reviewer_verdict_anchor` | The one reviewer verdict. |
| `rights_basis` | Always `generated_by_owner`. |
| `disposition` | The disposition that the consumer names. |

A lineage file holds text rows. Each row is `source_path = "...", tool = "...", model = "...", prompt = "..."?, date = "...", sha256 = "..."`.
A model row names its reference with `reference_sha256` and `reference_image_asset_id`, its prompt with `model_prompt_sha256` and its verdict with `comparison_verdict_receipt`.

The module reads no credential and makes no request.

### Asset audit

`Roblox.assetAudit.referenceViolations(input)` lists the violations of a manifest. It checks that each reference row carries the required fields, a committed original with the recorded digest, a recorded readback and one reviewer verdict.
It also checks that each model row resolves to exactly one reference by SHA-256 and image asset ID.
The `config` may name `requiredReferenceFields` and `receiptFields`. Without them, the audit requires `committed_source_path`, `source_sha256`, `prompt_sha256`, `lineage_path`, `reviewer_verdict_receipt`, `reviewer_verdict_anchor`, `image_readback_receipt`, `subject`, `family`, `group`, `rights_basis` and `disposition`, and it checks the receipt fields `lineage_path`, `reviewer_verdict_receipt` and `image_readback_receipt`.

### Binary instance files

`Roblox.rbxm` reads binary Roblox instance files.

| Task | Call |
| --- | --- |
| Test whether bytes are a binary instance file | `Roblox.rbxm.isBinary(bytes)` |
| Read the classes, the asset references and the asset IDs | `Roblox.rbxm.read(bytes)` |
| Read the instance tree | `Roblox.rbxm.instances(bytes)` |
| Get the path of one instance | `Roblox.rbxm.instancePath(tree, referent)` |

### Native transcripts

`Roblox.nativeTranscript` keeps the exact Studio calls and captures of one retained artifact. It binds consumer-declared Studio calls to the artifact and records exactly what the native host returned.
It does not open a Studio session and does not choose a route.

| Task | Call |
| --- | --- |
| Plan the calls | `Roblox.nativeTranscript.prepare(binding, calls, codec)` returns a `generate.roblox.native-plan.v1` plan. Its ordered `grant` lists each request SHA-256. |
| Run the calls | `Roblox.nativeTranscript.execute(plan, host)` spends one attempt for each call, in order. It returns a `generate.roblox.native-transcript.v1` transcript. |
| Verify the retained bytes | `Roblox.nativeTranscript.verify(plan, transcript, readHost, caps)` returns `{ results, images }` from exact retained bytes, or refuses. |
| Get the request bytes of one call | `Roblox.nativeTranscript.requestBytes` returns the exact bytes that the plan hashes. |

- `binding` names the exact `artifactDigest` and a `studio` record that contains `studioId`.
- Each call has a file-safe `label`, a `tool` of `execute_luau` or `screen_capture`, and `arguments`. The `studio_id` in `arguments` is the bound Studio.
- `codec` supplies the JSON `encode` and the `sha256` of the consumer.
- A request is the bytes `{"arguments":<encoded arguments>,"name":"<tool>"}`. Duplicates and other Studios are refused.

`execute` writes each request before it calls `host.call(tool, argumentsBytes)`. It writes the raw tool result after the call.
`host.writeNew` must refuse existing names. Then a second run of the same plan refuses before any call.
A thrown call is `ambiguous`. A tool error or an undecodable result is `failed`. Both stop the transcript. Neither is retried.
A `screen_capture` result must hold one base64 image whose PNG or JPEG signature matches its media type. Its decoded bytes are written as a separate file.

`verify` recomputes the plan digest and the grant. It requires the same artifact, Studio, ordered labels, tools and request digests.
It rereads and hashes every file within `caps.requestBytes`, `responseBytes` and `imageBytes`.
It requires each image file to equal its decoded response.
It refuses a missing, stopped or reordered call. It refuses an image that the transcript repeats or that `caps.excludedImages` names.
Hashes bind retained bytes. They do not prove that the host ran the call truthfully.


## Media

Media measures, converts and renders audio for review.

| Task | Call |
| --- | --- |
| Measure PCM and float WAVE bytes without a process: duration, peak, RMS, silent fraction and leading silence | `Media.wav.measure` |
| Build a small WAVE fixture | `Media.wav.encode` |
| Match the level that counts a frame as silent | `Media.wav.SILENCE` is the peak level `0.001`. |
| Convert audio with ffmpeg | `Lute.media.convert` |
| Build the ffmpeg arguments without running them | `Lute.media.convertCommand` |
| Probe a file with ffprobe | `Lute.media.probe` |
| Measure integrated loudness, range and true peak | `Lute.media.loudness` |
| Write a waveform PNG and a spectrogram PNG for a human reviewer | `Lute.media.review` |
| Build the review commands without running them | `Lute.media.reviewCommand` |

- Process calls take an optional runner for recorded output.
- Commands use `-y` and overwrite the selected output.

The consumer owns paths, retention, tool versions and invocation evidence.
Thresholds, recipes and the definition of acceptable stay with the consumer. A measurement is not an audition.

---

## Content, process and reviewer adapters

These adapters bind a content compiler, a process tool and a reviewer to a stage.

| Task | Call |
| --- | --- |
| Compile structured content with a compiler that the consumer supplies | `Content.compile` |
| Run a declared native audio tool or another tool | `Lute.process.run` |
| Select the reviewer executable from the configuration or the named environment variable | `Agent.reviewerCli.resolve` |
| Read one reviewer event stream with one thread and one terminal answer | `Agent.reviewerStream.parse` |
| Turn exactly one reviewer stream into a decision draft bound to the packet | `Agent.reviewerStream.decisions` |

- `Content.compile` requires the source, schema and tool identity from the consumer. It returns the artifact of the compiler.
- `Lute.process.run` binds declared tools. A successful execution does not prove audibility.
- `Agent.reviewerCli.resolve` selects only the consumer configuration or the named environment variable, through the supplied readers.
- `Agent.reviewerStream.parse` and `decisions` normalize an event contract that the consumer declares. `decisions` accepts exactly one stream and rejects malformed verdicts.

These adapters do not establish real independence and do not choose a vendor.

## Image lane

The image lane binds one provider attempt, deterministic transforms, measured checks and exact review views.
The consumer supplies every threshold, every look and every transform parameter. Generate supplies the measurements and the generic checks.
Acceptance follows [the review contract of the brief](#generatebrief).

| Task | Call |
| --- | --- |
| Derive recipe data from a brief | `Image.request.fromBrief` |
| Decode recipe data | `Image.request.decode` |
| Bind recipe data to the stages of a plan | `Image.request.bindings` |
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
| Summarize the gates and transform facts of a run | `Image.lane.summary` |
| Copy, convert or encode pixels | [Pixel helpers](#pixel-helpers) |

### Request and execution

Request and execution bind recipe data to plan stages and run those stages.

- `Image.request.fromBrief`, `decode`, `bindings` and `encode` bind recipe data to exactly declared, non-mutating plan stages.
- `Image.host.create` routes those stages. It has no publication authority.
- `Image.provider.runStage` spends one invocation that the consumer selects. It preserves references and confines output paths. It refuses a missing or mismatched reply.
- `Image.postprocess.runStage` pins the script bytes. It refuses an existing output, a silent or nonzero execution and a rewritten input.

Each recipe artifact declares `id`, `slug`, `role`, `tiles`, `transparentBackground` and `singleSubject`. It can also declare `unlit`, `dark`, `pairedGroup`, `hueBand`, `limitBrightMaxima`, `declaredWidth`, `declaredHeight` and `registerTarget`. The [checks](#checks) read these declarations.

Request bindings accept the kind `postprocess` with the existing `Postprocess.Transform` fields:

- the exact artifact ID and the supported transform kind
- the pinned script path and digest
- the input role and paths
- the immutable output path
- string parameters
- a positive whole attempt number

The binding keeps those identities and the optional rights. It does not interpret the projection of the consumer or any other transform algorithm.
Undeclared bindings and mutating stages refuse before host execution.
Recipe decoders accept `unknown`. Raw binding values remain `unknown` until the binding checks.
Before binding, the adapter checks nested provider requests, review requests and register targets against their declared field shapes. Adapters keep their semantic checks.
Successful transform results expose bytes and typed facts only after `ok` narrows to `true`.

### Thresholds

`Image.qa` has no built-in pass line and no built-in look. The consumer declares every threshold in `QaConfig.thresholds`.
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
`Image.qa.gate` also refuses a run that delivers a different number of files than it declares, a declared file that is missing, a paired group that does not hold exactly two images, and a pair whose mean-luminance ratio or registration correlation lies outside its thresholds.

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

Transforms change pixels deterministically. Review stages blind evidence for one reviewer.

- `Image.matte.run(codec, bytes, parameters)` repairs a cutout with the declared `interiorDistance`, `boundaryDistance` and `featherRadius`. It refuses a source without an opacity channel. The consumer declares the parameters. A host that binds `matte` needs `matteParameters`.
- `Image.register.run(config, bytes, target)` pulls colour towards the declared target `hue`, `saturationCeiling` and percentile `values`. The facts count pixels above alpha 5.
- `Image.deliver.run(config, bytes, declaredWidth, declaredHeight)` resamples to the declared size with a Lanczos filter of window 3.
- Each transform records the digests and the facts before and after. It is deterministic.
- A provider `Request` names its output `group`. The `group` is a lower kebab-case collection name. It becomes a directory under the output root and the first part of the candidate identity.
- Consumer codecs implement container decoding and encoding.
- `Image.review.stage` binds exact evidence views. It rejects leakage of the producer, the prompt and the previous verdict.
- `Image.lane.summary` records the gates and the transform facts.

Image checks and transforms do not supply a review decision.
Review identity strings alone do not prove that an independent human or agent reviewed the content.

## Brief diagnostics

`Consumer.scanSource(path, source, rulesets?)` scans the text of an authored brief and returns findings. Each finding has a `code`, a `path`, a `message` and a `fix`.
The default ruleset names no host. `Consumer.RULESETS` lists the optional rulesets. [Lint](lint.md) owns the codes.

## Fixture host

`Host.fake.create(options)` returns a `Generate.Host` for fixtures. The consumer scripts its stage outcomes, compensation faults, capabilities and environment.
It does no I/O.
