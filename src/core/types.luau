--!strict

export type AssetKind =
	"image"
	| "video"
	| "texture"
	| "material"
	| "rigid-mesh"
	| "modular-mesh"
	| "skinned-mesh"
	| "animation"
	| "audio"
	| "voice"
	| "music"
	| "sound-effect"
	| "text"
	| "dialogue"
	| "quest"
	| "localization"
	| "structured-content"
	| "font"
	| "dataset"
	| "other"

export type StringMap = { [string]: string }
export type NumberMap = { [string]: number }

export type Intent = {
	role: string,
	style: string?,
	description: string?,
}

export type RubricIdentity = {
	id: string,
	fingerprint: string,
	version: string?,
}

export type ReviewRequirement = "required" | "optional"

export type ReviewContract = {
	rubric: RubricIdentity,
	views: { string },
	blindness: ReviewRequirement,
	independence: ReviewRequirement,
}

export type RightsFactName = "source" | "license" | "owner" | "consent"

export type ProvenanceContract = {
	requireParentLineage: boolean,
	requiredRightsFacts: { RightsFactName },
}

export type Destination = {
	adapter: string,
	descriptor: { [string]: unknown },
}

export type DeliveryContract = {
	semanticId: string,
	target: string,
	destination: Destination?,
	hostVerification: boolean?,
}

export type HostVerification = {
	schemaVersion: number,
	requested: boolean,
	disposition: "verified" | "refused",
	refusalReason: string?,
	detail: string?,
	contentId: string,
	hostBuild: string,
	windowSeconds: number,
	measurements: { [string]: unknown },
	diagnostics: { string },
	captureRef: string?,
	observationFingerprint: string?,
}

export type HostVerificationRequestPayload = {
	schemaVersion: number,
	receiptId: string,
	sourceReceiptFingerprint: string,
	briefFingerprint: string,
	artifactId: string,
	artifactDigest: string,
	contentId: string,
	version: string,
	grantId: string,
	grantFingerprint: string,
	writeAheadDigest: string,
	stateFingerprint: string,
	host: string,
	hostBuild: string,
	windowSeconds: number,
	binding: { [string]: unknown },
}

export type HostVerificationCompletion = {
	requestFingerprint: string,
	pendingReceiptFingerprint: string,
	evidencePath: string,
	evidenceDigest: string,
	stateFingerprint: string,
}

export type HostVerificationRequest = HostVerificationRequestPayload & { fingerprint: string }

export type BriefDraft = {
	schemaVersion: number?,
	id: string,
	kind: AssetKind,
	intent: Intent,
	constraints: unknown?,
	review: {
		rubric: string,
		rubricFingerprint: string,
		rubricVersion: string?,
		views: { string },
		blindness: ReviewRequirement?,
		independence: ReviewRequirement?,
	},
	provenance: {
		requireParentLineage: boolean?,
		requiredRightsFacts: { RightsFactName }?,
	}?,
	delivery: DeliveryContract,
	metadata: StringMap?,
}

export type Brief = {
	schemaVersion: number,
	id: string,
	kind: AssetKind,
	intent: Intent,
	constraints: { [string]: unknown },
	review: ReviewContract,
	provenance: ProvenanceContract,
	delivery: DeliveryContract,
	metadata: StringMap,
}

export type Operation = "generate" | "import" | "transform" | "verify" | "review" | "publish" | "custom"
export type RollbackContract = "none" | "required"

export type StageDraft = {
	id: string,
	operation: Operation,
	dependsOn: { string }?,
	requires: { string }?,
	mutation: boolean?,
	rollback: RollbackContract?,
	parameters: StringMap?,
	deterministic: boolean?,
	estimatedCostMicros: number?,
}

export type Stage = {
	id: string,
	operation: Operation,
	dependsOn: { string },
	requires: { string },
	mutation: boolean,
	rollback: RollbackContract,
	parameters: StringMap,
	deterministic: boolean,
	estimatedCostMicros: number,
}

export type Plan = {
	schemaVersion: number,
	id: string,
	briefId: string,
	briefFingerprint: string,
	fingerprint: string,
	stages: { Stage },
}

export type Artifact = {
	id: string,
	digest: string,
	digestAlgorithm: "sha256",
	mediaType: string,
	byteCount: number?,
	locator: string?,
	semanticId: string?,
	metadata: StringMap,
}

export type Invocation = {
	tool: string,
	toolVersion: string,
	provider: string?,
	model: string?,
	seed: string?,
	parametersFingerprint: string,
	deterministic: boolean,
	costMicros: number?,
}

export type ProviderCallEconomics = {
	provider: string,
	kind: string,
	count: number,
	costMicros: number?,
	creditUnits: number?,
}

export type ReviewerEconomics = {
	actor: string,
	model: string?,
	inputTokens: number?,
	outputTokens: number?,
}

export type PublicationAttemptEconomics = {
	ordinal: number,
	disposition: string,
}

export type StageEconomics = {
	wallSeconds: number?,
	attemptCount: number?,
	providerCalls: { ProviderCallEconomics }?,
	reviewers: { ReviewerEconomics }?,
	publicationAttempts: { PublicationAttemptEconomics }?,
}

export type ArtifactRef = {
	id: string,
	digest: string,
	digestAlgorithm: "sha256",
}

export type EvidenceRef = {
	id: string,
	digest: string,
	digestAlgorithm: "sha256",
	view: string,
	role: string,
}

export type CandidateRevisionDraft = {
	candidateId: string,
	revision: number,
	producer: string,
	artifacts: { ArtifactRef },
}

export type CandidateRevision = {
	candidateId: string,
	revision: number,
	producer: string,
	artifacts: { ArtifactRef },
	fingerprint: string,
}

export type PacketBinding = {
	briefId: string,
	briefFingerprint: string,
	planFingerprint: string,
	stageId: string,
}

export type ReviewPacketDraft = {
	id: string,
	candidate: CandidateRevisionDraft,
	evidence: { EvidenceRef },
	rubric: RubricIdentity,
	requestedViews: { string },
	captureEnvironment: StringMap,
}

export type ReviewPacket = {
	schemaVersion: number,
	id: string,
	briefId: string,
	briefFingerprint: string,
	planFingerprint: string,
	stageId: string,
	candidate: CandidateRevision,
	evidence: { EvidenceRef },
	evidenceFingerprint: string,
	rubric: RubricIdentity,
	requestedViews: { string },
	captureEnvironment: StringMap,
	fingerprint: string,
}

export type Certainty = "high" | "medium" | "low"
export type Verdict = "approved" | "rejected" | "abstained"
export type ReviewContextKind = "independent" | "shared"

export type ReviewDecisionDraft = {
	packetId: string,
	packetFingerprint: string,
	candidateFingerprint: string,
	evidenceFingerprint: string,
	rubric: RubricIdentity,
	actor: string,
	role: string,
	context: ReviewContextKind,
	blind: boolean,
	modelFamily: string?,
	providerFamily: string?,
	certainty: Certainty,
	verdict: Verdict,
	reasons: { string },
	score: number?,
	refusals: { string }?,
}

export type ReviewDecision = {
	schemaVersion: number,
	packetId: string,
	packetFingerprint: string,
	candidateFingerprint: string,
	evidenceFingerprint: string,
	rubric: RubricIdentity,
	actor: string,
	role: string,
	context: ReviewContextKind,
	blind: boolean,
	modelFamily: string?,
	providerFamily: string?,
	certainty: Certainty,
	verdict: Verdict,
	reasons: { string },
	score: number?,
	refusals: { string }?,
	fingerprint: string,
}

export type ExclusionReason =
	"unknown-packet"
	| "packet-drift"
	| "candidate-drift"
	| "evidence-drift"
	| "rubric-drift"
	| "producer-self-review"
	| "duplicate-actor"
	| "blindness-required"
	| "independence-required"

export type ExcludedDecision = {
	packetId: string,
	actor: string,
	reason: ExclusionReason,
	detail: string,
}

export type ReviewDisposition = "approved" | "rejected" | "unresolved" | "incomplete" | "stale"

export type ReviewStaleness = {
	stale: boolean,
	reason: string?,
}

export type ResolvedReview = {
	schemaVersion: number,
	id: string,
	packetId: string,
	packetFingerprint: string,
	candidateId: string,
	candidateRevision: number,
	candidateFingerprint: string,
	candidateArtifacts: { ArtifactRef },
	producer: string,
	rubric: RubricIdentity,
	decisions: { ReviewDecision },
	excluded: { ExcludedDecision },
	stale: boolean,
	disposition: ReviewDisposition,
	resolution: string,
	reasons: { string },
	fingerprint: string,
}

export type RightsFact = {
	state: "known" | "unknown",
	value: string?,
}

export type RightsFacts = {
	state: "known" | "partial" | "unknown",
	source: RightsFact,
	license: RightsFact,
	owner: RightsFact,
	consent: RightsFact,
	notes: { string },
}

export type RightsFactsDraft = {
	source: RightsFact?,
	license: RightsFact?,
	owner: RightsFact?,
	consent: RightsFact?,
	notes: { string }?,
}

export type ParentRef = {
	artifactId: string?,
	artifactDigest: string?,
	receiptId: string?,
	receiptFingerprint: string?,
	jobId: string?,
	briefFingerprint: string?,
}

export type DerivationOrigin = "original" | "derived" | "imported"
export type CandidateDisposition = "active" | "rejected" | "parked" | "superseded" | "approved"

export type DerivationDraft = {
	artifactId: string,
	artifactDigest: string,
	origin: DerivationOrigin,
	parents: { ParentRef }?,
	inputDigests: { string }?,
	referenceDigests: { string }?,
	invocation: Invocation?,
	environment: StringMap?,
	attempt: number?,
	disposition: CandidateDisposition?,
	rights: RightsFactsDraft?,
}

export type Derivation = {
	schemaVersion: number,
	artifactId: string,
	artifactDigest: string,
	origin: DerivationOrigin,
	parents: { ParentRef },
	inputDigests: { string },
	referenceDigests: { string },
	invocation: Invocation?,
	environment: StringMap,
	attempt: number,
	disposition: CandidateDisposition,
	rights: RightsFacts,
	fingerprint: string,
}

export type Metadata = { [string]: unknown }

export type StageOutput = {
	artifacts: { Artifact }?,
	invocations: { Invocation }?,
	reviewPacket: ReviewPacketDraft?,
	decisions: { ReviewDecisionDraft }?,
	derivations: { DerivationDraft }?,
	rollbackToken: string?,
	metadata: Metadata?,
	costMicros: number?,
	economics: StageEconomics?,
}

export type StageOutcome =
	{ status: "returned", output: StageOutput }
	| { status: "faulted", detail: string, rollbackToken: string? }
	| { status: "rejected", detail: string, rollbackToken: string? }

export type RollbackOutcome = { status: "returned" } | { status: "faulted", detail: string }

export type Authority = {
	capabilities: { string },
	destinations: { string },
	mutationBudget: number,
	costBudgetMicros: number?,
}

export type RunContext = {
	idempotencyKey: string,
}

export type Host = {
	name: string,
	environment: StringMap,
	capabilities: { string },
	now: () -> number,
	runStage: (
		stage: Stage,
		brief: Brief,
		artifacts: { Artifact },
		authority: Authority,
		context: RunContext
	) -> StageOutcome,
	compensate: ((stage: Stage, token: string, authority: Authority) -> RollbackOutcome)?,
}

export type StageRecord = {
	id: string,
	operation: Operation,
	status: "returned" | "faulted" | "rejected" | "unsupported" | "cancelled" | "not_run",
	startedMicros: number,
	durationMicros: number,
	detail: string?,
	inputArtifacts: { Artifact },
	artifacts: { Artifact },
	invocations: { Invocation },
	reviewPacket: ReviewPacket?,
	decisions: { ReviewDecision },
	derivations: { Derivation },
	rollbackToken: string?,
	idempotencyKey: string,
	costMicros: number,
	metadata: Metadata,
	economics: StageEconomics?,
}

export type CompensationRecord = {
	stageId: string,
	status: "returned" | "faulted",
	detail: string?,
}

export type ReceiptStatus = "accepted" | "produced" | "rejected" | "failed" | "unsupported" | "cancelled"

export type Checkpoint = {
	schemaVersion: number,
	briefFingerprint: string,
	planFingerprint: string,
	nextStage: number,
	records: { StageRecord },
	artifacts: { Artifact },
	reviewPackets: { ReviewPacket },
	decisions: { ReviewDecision },
	derivations: { Derivation },
	costMicros: number,
}

export type PublicationStageStatus = "passed" | "refused" | "dry-run" | "spent" | "not-run"

export type PublicationStageReport = {
	id: string,
	status: PublicationStageStatus,
	detail: string?,
}

export type PublicationCredential = {
	name: string,
	exposed: boolean,
}

export type PublicationAttempt = {
	ordinal: number,
	stageId: string,
	grantId: string,
	grantFingerprint: string,
	action: string,
	semanticId: string,
	state: string,
	contentId: string?,
	version: string?,
	operationId: string?,
	rollbackToken: string?,
	detail: string?,
}

export type PublicationCompensation = {
	ordinal: number,
	stageId: string,
	rollbackToken: string,
	status: string,
	detail: string,
}

export type PublicationState = "pending" | "confirmed" | "reconciled" | "stopped"

export type PublicationRecord = {
	schemaVersion: number,
	disposition: string,
	state: PublicationState,
	detail: string?,
	dryRun: boolean,
	quarantined: boolean,
	placeholder: boolean,
	contentId: string?,
	version: string?,
	readback: StringMap?,
	grantId: string?,
	grantFingerprint: string?,
	idempotencyKey: string?,
	artifactId: string?,
	artifactDigest: string?,
	writeAheadPath: string?,
	writeAheadDigest: string?,
	credential: PublicationCredential,
	attemptsAuthorised: number,
	attemptsMade: number,
	attempts: { PublicationAttempt },
	compensations: { PublicationCompensation },
	stages: { PublicationStageReport },
	facts: { [string]: unknown },
	verification: HostVerification?,
	verificationRequest: HostVerificationRequest?,
	verificationCompletion: HostVerificationCompletion?,
	verificationRebindings: { { receiptFingerprint: string, requestFingerprint: string, hostBuild: string } }?,
	reconciliation: { sourceReceiptFingerprint: string, evidencePath: string, evidenceDigest: string }?,
	economics: StageEconomics?,
}

export type Receipt = {
	schemaVersion: number,
	id: string,
	fingerprint: string,
	briefId: string,
	briefFingerprint: string,
	planFingerprint: string,
	reviewContract: ReviewContract,
	provenanceContract: ProvenanceContract,
	host: string,
	environment: StringMap,
	status: ReceiptStatus,
	startedMicros: number,
	durationMicros: number,
	stages: { StageRecord },
	compensations: { CompensationRecord },
	artifacts: { Artifact },
	reviewPackets: { ReviewPacket },
	decisions: { ReviewDecision },
	reviews: { ResolvedReview },
	derivations: { Derivation },
	limitations: { string },
	costMicros: number,
	checkpoint: Checkpoint?,
	publication: PublicationRecord?,
}

export type DeliveryEntry = {
	semanticId: string,
	artifactId: string,
	digest: string,
	digestAlgorithm: "sha256",
	mediaType: string,
	byteCount: number?,
	locator: string?,
	reviewId: string,
	reviewFingerprint: string,
	candidateFingerprint: string,
	derivationFingerprint: string?,
	metadata: StringMap,
}

export type DeliveryManifest = {
	schemaVersion: number,
	id: string,
	receiptId: string,
	receiptFingerprint: string,
	entries: { DeliveryEntry },
	fingerprint: string,
}

return nil
