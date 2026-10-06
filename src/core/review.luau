--!strict

local Canonical = require "./canonical"
local Secret = require "./secret"
local Types = require "./types"

type ArtifactRef = Types.ArtifactRef
type CandidateRevision = Types.CandidateRevision
type EvidenceRef = Types.EvidenceRef
type ExcludedDecision = Types.ExcludedDecision
type ReviewStaleness = Types.ReviewStaleness
type ResolvedReview = Types.ResolvedReview
type ReviewContract = Types.ReviewContract
type ReviewDecision = Types.ReviewDecision
type ReviewDecisionDraft = Types.ReviewDecisionDraft
type ReviewPacket = Types.ReviewPacket
type ReviewPacketDraft = Types.ReviewPacketDraft
type RubricIdentity = Types.RubricIdentity

local SCHEMA_VERSION = 1

local CERTAINTY: { [string]: boolean } = { high = true, medium = true, low = true }
local VERDICT: { [string]: boolean } = { approved = true, rejected = true, abstained = true }
local CONTEXT: { [string]: boolean } = { independent = true, shared = true }

local function nonempty(value: unknown, label: string, level: number): string
	if type(value) ~= "string" or value == "" then
		error("Generate review " .. label .. " must be a non-empty string", level)
	end
	return value
end

local function isSha256(value: string): boolean
	return #value == 64 and string.match(value, "^[0-9a-f]+$") ~= nil
end

local function rubric(identity: RubricIdentity, label: string, level: number): RubricIdentity
	if type(identity) ~= "table" then
		error("Generate review " .. label .. " must be a rubric identity table", level)
	end
	local value: RubricIdentity = {
		id = nonempty(identity.id, label .. ".id", level + 1),
		fingerprint = nonempty(identity.fingerprint, label .. ".fingerprint", level + 1),
		version = identity.version,
	}
	if value.version ~= nil and value.version == "" then
		error("Generate review " .. label .. ".version must be omitted or non-empty", level)
	end
	return value
end

local function artifactRef(reference: ArtifactRef, label: string, level: number): ArtifactRef
	if type(reference) ~= "table" then
		error("Generate review " .. label .. " must be an artifact reference table", level)
	end
	local id = nonempty(reference.id, label .. ".id", level + 1)
	if reference.digestAlgorithm ~= "sha256" or not isSha256(reference.digest or "") then
		error("Generate review " .. label .. " requires a lowercase SHA-256 digest", level)
	end
	return { id = id, digest = reference.digest, digestAlgorithm = "sha256" }
end

local function candidateFingerprint(candidate: {
	candidateId: string,
	revision: number,
	producer: string,
	artifacts: { ArtifactRef },
}): string
	return Canonical.fingerprint {
		candidateId = candidate.candidateId,
		revision = candidate.revision,
		producer = candidate.producer,
		artifacts = candidate.artifacts,
	}
end

local function evidenceFingerprint(evidence: { EvidenceRef }): string
	return Canonical.fingerprint(evidence)
end

local function packet(draft: ReviewPacketDraft, binding: Types.PacketBinding): ReviewPacket
	if type(draft) ~= "table" or type(binding) ~= "table" then
		error("Generate.reviewPacket expects a draft and its plan binding", 2)
	end
	local candidateDraft = draft.candidate
	if type(candidateDraft) ~= "table" then
		error("Generate review packet requires an exact candidate revision", 2)
	end
	if type(candidateDraft.revision) ~= "number" or candidateDraft.revision < 1 or candidateDraft.revision % 1 ~= 0 then
		error("Generate review packet candidate revision must be a positive integer", 2)
	end
	local artifacts: { ArtifactRef } = {}
	local seenArtifact: { [string]: boolean } = {}
	for index, reference in candidateDraft.artifacts do
		local value = artifactRef(reference, ("packet candidate artifact %d"):format(index), 3)
		if seenArtifact[value.id] then
			error(("Generate review packet repeats candidate artifact %q"):format(value.id), 2)
		end
		seenArtifact[value.id] = true
		table.insert(artifacts, value)
	end
	if #artifacts == 0 then
		error("Generate review packet must bind at least one candidate artifact digest", 2)
	end
	local evidence: { EvidenceRef } = {}
	local seenEvidence: { [string]: boolean } = {}
	for index, reference in draft.evidence do
		local base = artifactRef(reference, ("packet evidence %d"):format(index), 3)
		local view = nonempty(reference.view, ("packet evidence %d view"):format(index), 3)
		local role = nonempty(reference.role, ("packet evidence %d role"):format(index), 3)
		if seenEvidence[base.id] then
			error(("Generate review packet repeats evidence artifact %q"):format(base.id), 2)
		end
		seenEvidence[base.id] = true
		table.insert(evidence, {
			id = base.id,
			digest = base.digest,
			digestAlgorithm = "sha256",
			view = view,
			role = role,
		})
	end
	if #evidence == 0 then
		error("Generate review packet must bind at least one evidence artifact digest", 2)
	end
	local views: { string } = {}
	local seenView: { [string]: boolean } = {}
	for index, view in draft.requestedViews do
		local value = nonempty(view, ("packet requestedViews %d"):format(index), 3)
		if seenView[value] then
			error(("Generate review packet repeats requested view %q"):format(value), 2)
		end
		seenView[value] = true
		table.insert(views, value)
	end
	if #views == 0 then
		error("Generate review packet must name the requested canonical views", 2)
	end
	local capture: Types.StringMap = table.clone((draft.captureEnvironment or {}) :: Types.StringMap)
	Secret.validate(capture, "Generate review packet captureEnvironment")
	if next(capture) == nil then
		error("Generate review packet must record the capture environment it bound", 2)
	end
	local candidate: CandidateRevision = {
		candidateId = nonempty(candidateDraft.candidateId, "packet candidate candidateId", 3),
		revision = candidateDraft.revision,
		producer = nonempty(candidateDraft.producer, "packet candidate producer", 3),
		artifacts = artifacts,
		fingerprint = "",
	}
	candidate.fingerprint = candidateFingerprint(candidate)
	local partial = {
		schemaVersion = SCHEMA_VERSION,
		id = nonempty(draft.id, "packet id", 3),
		briefId = nonempty(binding.briefId, "packet binding briefId", 3),
		briefFingerprint = nonempty(binding.briefFingerprint, "packet binding briefFingerprint", 3),
		planFingerprint = nonempty(binding.planFingerprint, "packet binding planFingerprint", 3),
		stageId = nonempty(binding.stageId, "packet binding stageId", 3),
		candidate = candidate,
		evidence = evidence,
		evidenceFingerprint = evidenceFingerprint(evidence),
		rubric = rubric(draft.rubric, "packet rubric", 3),
		requestedViews = views,
		captureEnvironment = capture,
	}
	local result = table.clone(partial)
	result.fingerprint = Canonical.fingerprint(partial)
	return result
end

local function decision(draft: ReviewDecisionDraft): ReviewDecision
	if type(draft) ~= "table" then
		error("Generate.reviewDecision expects a table", 2)
	end
	if not CERTAINTY[draft.certainty] then
		error("Generate review decision certainty must be high, medium, or low", 2)
	end
	if not VERDICT[draft.verdict] then
		error("Generate review decision verdict must be approved, rejected, or abstained", 2)
	end
	if not CONTEXT[draft.context] then
		error("Generate review decision context must be independent or shared", 2)
	end
	if type(draft.blind) ~= "boolean" then
		error("Generate review decision must state whether the reviewer was blind", 2)
	end
	local reasons: { string } = {}
	for index, reason in draft.reasons do
		table.insert(reasons, nonempty(reason, ("decision reason %d"):format(index), 3))
	end
	if draft.verdict ~= "approved" and #reasons == 0 then
		error("Generate review decision must give at least one reason when it does not approve", 2)
	end
	if draft.modelFamily ~= nil and draft.modelFamily == "" then
		error("Generate review decision modelFamily must be omitted or non-empty", 2)
	end
	if draft.providerFamily ~= nil and draft.providerFamily == "" then
		error("Generate review decision providerFamily must be omitted or non-empty", 2)
	end
	if draft.score ~= nil and (type(draft.score) ~= "number" or draft.score < 0 or draft.score > 10) then
		error("Generate review decision score must be omitted or a number between 0 and 10", 2)
	end
	local refusals: { string }? = nil
	if draft.refusals ~= nil then
		local values: { string } = {}
		for index, value in draft.refusals do
			table.insert(values, nonempty(value, ("decision refusal %d"):format(index), 3))
		end
		refusals = values
	end
	local partial = {
		schemaVersion = SCHEMA_VERSION,
		packetId = nonempty(draft.packetId, "decision packetId", 3),
		packetFingerprint = nonempty(draft.packetFingerprint, "decision packetFingerprint", 3),
		candidateFingerprint = nonempty(draft.candidateFingerprint, "decision candidateFingerprint", 3),
		evidenceFingerprint = nonempty(draft.evidenceFingerprint, "decision evidenceFingerprint", 3),
		rubric = rubric(draft.rubric, "decision rubric", 3),
		actor = nonempty(draft.actor, "decision actor", 3),
		role = nonempty(draft.role, "decision role", 3),
		context = draft.context,
		blind = draft.blind,
		modelFamily = draft.modelFamily,
		providerFamily = draft.providerFamily,
		certainty = draft.certainty,
		verdict = draft.verdict,
		reasons = reasons,
		score = draft.score,
		refusals = refusals,
	}
	local result = table.clone(partial)
	result.fingerprint = Canonical.fingerprint(partial)
	return result
end

local function ineligibility(
	value: ReviewDecision,
	target: ReviewPacket,
	contract: ReviewContract,
	seenActor: { [string]: boolean }
): (Types.ExclusionReason?, string?)
	if value.packetId ~= target.id then
		return "unknown-packet", ("decision names packet %q, review resolves %q"):format(value.packetId, target.id)
	end
	if value.rubric.fingerprint ~= target.rubric.fingerprint or value.rubric.id ~= target.rubric.id then
		return "rubric-drift",
			("reviewer judged rubric %q/%s, packet bound %q/%s"):format(
				value.rubric.id,
				value.rubric.fingerprint,
				target.rubric.id,
				target.rubric.fingerprint
			)
	end
	if value.evidenceFingerprint ~= target.evidenceFingerprint then
		return "evidence-drift", "reviewer judged evidence that is not the evidence bound by this packet"
	end
	if value.candidateFingerprint ~= target.candidate.fingerprint then
		return "candidate-drift", "reviewer judged a candidate revision other than the one this packet binds"
	end
	if value.packetFingerprint ~= target.fingerprint then
		return "packet-drift", "decision does not bind this exact review packet"
	end
	if contract.independence == "required" and value.actor == target.candidate.producer then
		return "producer-self-review", ("actor %q produced the candidate it reviewed"):format(value.actor)
	end
	if seenActor[value.actor] then
		return "duplicate-actor", ("actor %q already submitted a decision for this packet"):format(value.actor)
	end
	if contract.blindness == "required" and not value.blind then
		return "blindness-required",
			("reviewer %q reported without blindness the contract requires"):format(value.actor)
	end
	if contract.independence == "required" and value.context ~= "independent" then
		return "independence-required", ("reviewer %q reported from a shared review context"):format(value.actor)
	end
	return nil, nil
end

local function resolve(
	target: ReviewPacket,
	contract: ReviewContract,
	decisions: { ReviewDecision },
	staleness: ReviewStaleness?
): ResolvedReview
	if type(target) ~= "table" or type(contract) ~= "table" then
		error("Generate.resolveReview expects a review packet and its review contract", 2)
	end
	if contract.independence ~= "required" and contract.independence ~= "optional" then
		error("Generate.resolveReview requires a declared independence", 2)
	end
	local stale: ReviewStaleness = staleness or { stale = false, reason = nil }
	local counted: { ReviewDecision } = {}
	local excluded: { ExcludedDecision } = {}
	local seenActor: { [string]: boolean } = {}
	local submitted = 0
	for _, value in decisions do
		if value.packetId == target.id then
			submitted += 1
		end
		local reason, detail = ineligibility(value, target, contract, seenActor)
		if reason ~= nil then
			table.insert(excluded, {
				packetId = value.packetId,
				actor = value.actor,
				reason = reason :: Types.ExclusionReason,
				detail = detail :: string,
			})
			continue
		end
		seenActor[value.actor] = true
		table.insert(counted, value)
	end
	local disposition: Types.ReviewDisposition
	local reasons: { string }
	if stale.stale then
		disposition = "stale"
		reasons = { stale.reason or "the reviewed candidate revision no longer describes the current artifact" }
	elseif #counted == 0 then
		disposition = "incomplete"
		reasons = { "review requires one eligible decision under the declared independence contract" }
	elseif submitted ~= 1 then
		disposition = "unresolved"
		reasons = { "review requires exactly one submitted decision from an eligible reviewer" }
	elseif counted[1].verdict == "rejected" then
		disposition = "rejected"
		reasons = Canonical.sortedStrings(counted[1].reasons)
	elseif counted[1].verdict == "approved" then
		disposition = "approved"
		reasons = Canonical.sortedStrings(counted[1].reasons)
	else
		disposition = "unresolved"
		reasons = { "the reviewer abstained" }
	end

	local partial = {
		schemaVersion = SCHEMA_VERSION,
		id = target.id .. "/review",
		packetId = target.id,
		packetFingerprint = target.fingerprint,
		candidateId = target.candidate.candidateId,
		candidateRevision = target.candidate.revision,
		candidateFingerprint = target.candidate.fingerprint,
		candidateArtifacts = target.candidate.artifacts,
		producer = target.candidate.producer,
		rubric = target.rubric,
		decisions = counted,
		excluded = excluded,
		stale = stale.stale,
		disposition = disposition,
		resolution = ("submitted=%d eligible=%d excluded=%d"):format(submitted, #counted, #excluded),
		reasons = reasons,
	}
	local result = table.clone(partial)
	result.fingerprint = Canonical.fingerprint(partial)
	return result
end

local function binds(review: ResolvedReview, artifactId: string, digest: string): boolean
	for _, reference in review.candidateArtifacts do
		if reference.id == artifactId and reference.digest == digest then
			return true
		end
	end
	return false
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	packet = packet,
	decision = decision,
	resolve = resolve,
	binds = binds,
	candidateFingerprint = candidateFingerprint,
	evidenceFingerprint = evidenceFingerprint,
}
