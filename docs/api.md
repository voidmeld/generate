# API reference
Import the packages from `src/core`, `src/image` and `src/roblox`. All record constructors are pure; effects are confined to injected Roblox adapters. Consumers own execution and provider tooling.
Briefs normalize review and provenance requirements before fingerprinting. Plans bind an unchanged brief, order declared dependencies and refuse unsafe mutation declarations. A plan describes work; the consumer executes it.
Review packets bind one candidate revision, exact digests, requested views, capture environment and rubric. Decisions bind that packet and actor. Resolution excludes stale or ineligible decisions and requires the declared independence. Scores cannot override rejection. Review staging refuses unblinding capture fields and missing requested evidence.
Receipts preserve schema-v2 stage, artifact, review, derivation, compensation, cost and checkpoint records. Receipt fingerprints cover their declared fields. Manifests require unchanged accepted receipts and exact approved artifact bindings. Canonical encoding, field selection and `gen-fp2` arithmetic are stable evidence formats.
Roblox delivery requires an explicit creator, private destination, exact review and granted authority. Each mutation retains one attempt and authenticated readback. Ambiguous, refused and unknown outcomes retain recovery state; they do not authorize another route. Destination descriptors remain opaque core data.
Image delivery is deterministic: identity at the declared size, area reduction and Lanczos enlargement. It records digests, dimensions, filter parameters and high-frequency screen measurements. PNG measurement reports actual saved dimensions and consumer-declared bounds. Metrics are observations; consumers choose acceptance thresholds.
## Generate

`Generate.RIGHTS_FACT_NAMES` lists the supported provenance rights facts.
| Public call or value | Contract |
| --- | --- |
| `Generate.brief` | Public record value; see the package source. |
| `Generate.briefFingerprint` | Public record value; see the package source. |
| `Generate.canonical` | Public record value; see the package source. |
| Normalize and validate where a candidate came from | `Generate.derivation(draft)` |
| `Generate.fingerprint` | Public record value; see the package source. |
| `Generate.manifest` | Public record value; see the package source. |
| `Generate.plan` | Public record value; see the package source. |
| List the lineage and rights faults that block delivery | `Generate.provenanceFaults(derivation, contract, byArtifactId)` |
| `Generate.receiptFingerprint` | Public record value; see the package source. |
| Resolve the single eligible decision under the declared contract | `Generate.resolveReview(packet, contract, decisions, staleness?)` returns a `ResolvedReview`. |
| Check that a resolved review binds an artifact digest | `Generate.reviewBinds(review, artifactId, digest)` does not claim that the reviewer is truthful. |
| Record the identity, context, verdict and reasons of the reviewer | `Generate.reviewDecision(draft)` |
| Bind the candidate revision, artifacts, evidence and rubric to a stage | `Generate.reviewPacket(draft, binding)` |
| Build the ledger of one candidate from its revision entries | `Generate.revisionLedger(candidateId, entries)` |
| Normalize the rights facts of a candidate | `Generate.rights(draft)` |
| Draft the next candidate revision from a ledger | `Generate.rollCandidate(ledger, draft)` |
Public types (definitions in [package source](../src/core/init.luau)):
- `Generate.ArtifactRef`
- `Generate.CandidateDisposition`
- `Generate.CandidateRevision`
- `Generate.Certainty`
- `Generate.Verdict`
- `Generate.RightsFactName`
- `Generate.ReviewRequirement`
- `Generate.PacketBinding`
- `Generate.Derivation`
- `Generate.DerivationDraft`
- `Generate.EvidenceRef`
- `Generate.ExcludedDecision`
- `Generate.ReviewDisposition`
- `Generate.ParentRef`
- `Generate.ProvenanceContract`
- `Generate.ResolvedReview`
- `Generate.ReceiptStatus`
- `Generate.ReviewContract`
- `Generate.Metadata`
- `Generate.DerivationOrigin`
- `Generate.ReviewDecision`
- `Generate.ReviewDecisionDraft`
- `Generate.ReviewPacket`
- `Generate.ReviewPacketDraft`
- `Generate.RightsFact`
- `Generate.RightsFacts`
- `Generate.RubricIdentity`
- `Generate.RevisionEntry`
- `Generate.RevisionEntryDraft`
- `Generate.RevisionLedger`
- `Generate.RevisionOutcome`
- `Generate.RevisionRollDraft`
- `Generate.CandidateRevisionDraft`
- `Generate.Artifact`
- `Generate.AssetKind`
- `Generate.Authority`
- `Generate.Brief`
- `Generate.BriefDraft`
- `Generate.Host`
- `Generate.Invocation`
- `Generate.Destination`
- `Generate.DeliveryContract`
- `Generate.PublicationAttemptEconomics`
- `Generate.DeliveryEntry`
- `Generate.DeliveryManifest`
- `Generate.Plan`
- `Generate.Receipt`
- `Generate.ProviderCallEconomics`
- `Generate.ReviewerEconomics`
- `Generate.StageEconomics`
- `Generate.RunContext`
- `Generate.RollbackOutcome`
- `Generate.Stage`
- `Generate.StageDraft`
- `Generate.StageOutcome`
- `Generate.StageRecord`
## Image
| Public call or value | Contract |
| --- | --- |
| Copy an image as RGBA | `Image.codec.copy(image)` |
| Encode an image through the consumer codec | `Image.codec.encode(codec, image)` |
| Get an RGB value from a hue, a saturation and a lightness | `Image.codec.fromHueSaturation(hue, saturation, lightness)` |
| Get the hue, saturation and lightness of an RGB value | `Image.codec.hueSaturation(r, g, b)` |
| Get the luminance of an RGB value | `Image.codec.luma(r, g, b)` |
| Convert an RGB or RGBA image to an RGBA copy | `Image.codec.rgba(image)` |
| Round a measurement to four decimals | `Image.codec.rounded(value)` |
| Set the luminance of one pixel in a buffer | `Image.codec.setLuma(pixels, base, wanted)` |
| `Image.deliver.run` | Public record value; see the package source. |
| `Image.measure.MEDIA_TYPE` | Public record value; see the package source. |
| `Image.measure.artifact` | Public record value; see the package source. |
| `Image.measure.measure` | Public record value; see the package source. |
| `Image.measure.pngDimensions` | Public record value; see the package source. |
| `Image.measure.runStage` | Public record value; see the package source. |
| `Image.review.DEFAULT_CONFIG` | Stable record constants; see the package source. |
| `Image.review.runStage` | Public record value; see the package source. |
| `Image.review.stage` | Public record value; see the package source. |
Public types (definitions in [package source](../src/image/init.luau)):
- `Image.Codec`
- `Image.Digest`
- `Image.Decoded`
- `Image.Image`
- `Image.Rgba`
- `Image.DeliverConfig`
- `Image.DeliverFacts`
- `Image.DeliverResult`
- `Image.DeliverSuccess`
- `Image.MeasureBounds`
- `Image.MeasureConfig`
- `Image.MeasureOutcome`
- `Image.MeasureEvidence`
- `Image.Measurement`
- `Image.ReviewConfig`
- `Image.ReviewOutcome`
- `Image.ReviewRequest`
## Roblox
| Public call or value | Contract |
| --- | --- |
| `Roblox.assetAudit.referenceViolations` | Public record value; see the package source. |
| `Roblox.assetReadback.SOURCES` | Stable record constants; see the package source. |
| `Roblox.assetReadback.UNOBSERVABLE` | Stable record constants; see the package source. |
| Read a root asset and the dependencies that you name | `Roblox.assetReadback.census(options, rootAssetId, dependencyAssetIds)` returns a `Census`. |
| Read one asset | `Roblox.assetReadback.readback(options, assetId)` returns a `Record`. |
| Record an operation or asset ID after an ambiguous upload | `Roblox.delivery.attach(config, key, reference)` |
| Get the store key of an upload | `Roblox.delivery.key(format, sha256, assetType)` |
| Record an asset ID after an ambiguous native save | `Roblox.delivery.native.attach(config, key, assetId)` |
| Keep native records on a Studio Instance | `Roblox.delivery.native.attributeStore(instance, httpService)` |
| Save one native object | `Roblox.delivery.native.save(config, host, request)` |
| Upload several files, stopping at the first refusal | `Roblox.delivery.queue(config, items, options)` |
| Read an operation or an asset | `Roblox.delivery.status(config, reference, assetType)` |
| Upload one reviewed file | `Roblox.delivery.upload(config, request)` |
| `Roblox.destination` | Public record value; see the package source. |
| `Roblox.permissionGrant.CREDENTIAL_DECISION` | Public record value; see the package source. |
| `Roblox.permissionGrant.DECISIONS` | Stable record constants; see the package source. |
| `Roblox.permissionGrant.ENDPOINT` | Public record value; see the package source. |
| `Roblox.permissionGrant.MAX_ASSETS_PER_REQUEST` | Public record value; see the package source. |
| `Roblox.permissionGrant.REASONS` | Stable record constants; see the package source. |
| Send one request and check that the response confirms exactly the requested assets | `Roblox.permissionGrant.attempt(send, decode, prepared)` |
| Split asset IDs into groups of one request | `Roblox.permissionGrant.chunks(assetIds, size)` |
| Build the request for one group | `Roblox.permissionGrant.prepare(encode, universeId, assetIds)` |
| Read the group membership and roles of the credential owner and record them as facts | `Roblox.permissionGrant.subjectAuthority(options, credential, universeId, groupId)` |
| Get the path of one instance | `Roblox.rbxm.instancePath(tree, referent)` |
| Read the instance tree | `Roblox.rbxm.instances(bytes)` |
| Test whether bytes are a binary instance file | `Roblox.rbxm.isBinary(bytes)` |
| Read the classes, the asset references and the asset IDs | `Roblox.rbxm.read(bytes)` |
| `Roblox.readDestination` | Public record value; see the package source. |
Public types (definitions in [package source](../src/roblox/init.luau)):
- `Roblox.AssetAuditFiles`
- `Roblox.AssetAuditConfig`
- `Roblox.AssetAuditInput`
- `Roblox.AssetAuditReference`
- `Roblox.AssetAuditModel`
- `Roblox.AssetReadbackOptions`
- `Roblox.AssetReadbackOwner`
- `Roblox.AssetRecord`
- `Roblox.AssetCensus`
- `Roblox.DeliveryAuthority`
- `Roblox.DeliveryAttributeInstance`
- `Roblox.DeliveryAttributeJson`
- `Roblox.DeliveryConfig`
- `Roblox.DeliveryResult`
- `Roblox.DeliveryRecord`
- `Roblox.DeliveryStore`
- `Roblox.DeliveryReview`
- `Roblox.DeliveryCreator`
- `Roblox.DeliveryRequest`
- `Roblox.DeliveryReply`
- `Roblox.DeliveryUpload`
- `Roblox.DeliveryItem`
- `Roblox.DeliveryRow`
- `Roblox.DeliveryQueueResult`
- `Roblox.DeliveryNativeHost`
- `Roblox.DeliveryNativeRequest`
- `Roblox.PermissionAuthorityOptions`
- `Roblox.PermissionCredential`
- `Roblox.PermissionAssignedRole`
- `Roblox.PermissionChunkOutcome`
- `Roblox.PermissionAuthorityReceipt`
- `Roblox.PermissionPatch`
- `Roblox.RbxmClass`
- `Roblox.RbxmDocument`
- `Roblox.RbxmInstance`
- `Roblox.RbxmReference`
- `Roblox.RbxmTree`
- `Roblox.PermissionRequest`
- `Roblox.PermissionRequestResult`
- `Roblox.CloudRequest`
- `Roblox.CloudResponse`
- `Roblox.CloudSend`
- `Roblox.Destination`
- `Roblox.DestinationDraft`
## Record construction

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
| List the lineage and rights faults that block delivery | `Generate.provenanceFaults(derivation, contract, byArtifactId)` |

An open head cannot roll. To replace an approved head, declare that replacement.
Derivations and rights do not invent rights facts.

### `Generate.manifest`

`manifest(receipt, artifactIds) -> DeliveryManifest`

`Generate.manifest` lists the approved artifacts for delivery. It selects the exact approved semantic delivery with the required provenance. Its entries name `reviewId` and `reviewFingerprint`.
The consumer owns registry adoption and runtime acceptance.

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

`Roblox.delivery` owns reviewed file uploads and native-object saves, with one-attempt journals, moderation readback and recovery. It needs no brief.

The transport types are `Roblox.CloudRequest`, `Roblox.CloudResponse` and `Roblox.CloudSend`.
`send(request)` receives a `CloudRequest` and returns a `CloudResponse` with `ok`, `status` and `body`.

### Roblox destinations

`Roblox.destination(draft)` validates and normalizes a Roblox destination as a `Generate.Destination`.
`Roblox.readDestination(destination)` reads the typed fields and refuses a descriptor that is not normalized.
Both preserve the declared creator, asset type, restricted visibility and optional universe requirements.
The destination descriptor requires `creator`, `assetType`, `visibility` and `credentialName`.
The `creator` is `group` or `user`. The `visibility` is `private` or `restricted`.
Optional fields are `assetId`, `displayName`, `description`, `grantUniverses` and `verifyDependencies`.
Public visibility is refused. `verifyDependencies` needs `grantUniverses`.

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

