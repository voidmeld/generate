--!strict

local Canonical = require "./canonical"
local Types = require "./types"

type ArtifactRef = Types.ArtifactRef
type CandidateRevisionDraft = Types.CandidateRevisionDraft
type ResolvedReview = Types.ResolvedReview

local SCHEMA_VERSION = 1

export type RevisionOutcome = "open" | "approved" | "rejected" | "unresolved" | "stale"

export type RevisionEntryDraft = {
	revision: number,
	producer: string,
	outcome: RevisionOutcome,
	packetId: string?,
	candidateFingerprint: string?,
}

export type RevisionEntry = {
	revision: number,
	producer: string,
	outcome: RevisionOutcome,
	packetId: string?,
	candidateFingerprint: string?,
}

export type RevisionLedger = {
	schemaVersion: number,
	candidateId: string,
	entries: { RevisionEntry },
	head: RevisionEntry,
	settled: boolean,
	nextRevision: number?,
	fingerprint: string,
}

export type RollDraft = {
	producer: string,
	artifacts: { ArtifactRef },
	supersede: boolean?,
}

local OUTCOMES: { [string]: boolean } = {
	open = true,
	approved = true,
	rejected = true,
	unresolved = true,
	stale = true,
}

local APPROVED: RevisionOutcome = "approved"
local REJECTED: RevisionOutcome = "rejected"
local UNRESOLVED: RevisionOutcome = "unresolved"
local STALE: RevisionOutcome = "stale"

local REVIEW_OUTCOMES: { [string]: RevisionOutcome } = {
	approved = APPROVED,
	rejected = REJECTED,
	unresolved = UNRESOLVED,
	incomplete = UNRESOLVED,
	stale = STALE,
}

local function nonempty(value: unknown, label: string, level: number): string
	if type(value) ~= "string" or value == "" then
		error("Generate revision " .. label .. " must be a non-empty string", level)
	end
	return value :: string
end

local function positiveInteger(value: unknown, label: string, level: number): number
	if type(value) ~= "number" or value < 1 or value % 1 ~= 0 then
		error("Generate revision " .. label .. " must be a positive integer", level)
	end
	return value :: number
end

local function outcomeFor(review: ResolvedReview): RevisionOutcome
	if type(review) ~= "table" then
		error("Generate.revisionOutcome expects a resolved review", 2)
	end
	local mapped = REVIEW_OUTCOMES[review.disposition]
	if mapped == nil then
		error(("Generate revision cannot read review disposition %q"):format(tostring(review.disposition)), 2)
	end
	return mapped :: RevisionOutcome
end

local function entryFor(review: ResolvedReview): RevisionEntryDraft
	local draft: RevisionEntryDraft = {
		revision = positiveInteger(review.candidateRevision, "entry revision", 3),
		producer = nonempty(review.producer, "entry producer", 3),
		outcome = outcomeFor(review),
		packetId = review.packetId,
		candidateFingerprint = review.candidateFingerprint,
	}
	return draft
end

local function entry(draft: RevisionEntryDraft, ordinal: number): RevisionEntry
	if type(draft) ~= "table" then
		error(("Generate revision entry %d must be a table"):format(ordinal), 3)
	end
	if not OUTCOMES[draft.outcome] then
		error(
			("Generate revision entry %d outcome must be open, approved, rejected, unresolved, or stale"):format(
				ordinal
			),
			3
		)
	end
	local value: RevisionEntry = {
		revision = positiveInteger(draft.revision, ("entry %d revision"):format(ordinal), 4),
		producer = nonempty(draft.producer, ("entry %d producer"):format(ordinal), 4),
		outcome = draft.outcome,
		packetId = draft.packetId,
		candidateFingerprint = draft.candidateFingerprint,
	}
	if value.packetId ~= nil and value.packetId == "" then
		error(("Generate revision entry %d packetId must be omitted or non-empty"):format(ordinal), 3)
	end
	if value.candidateFingerprint ~= nil and value.candidateFingerprint == "" then
		error(("Generate revision entry %d candidateFingerprint must be omitted or non-empty"):format(ordinal), 3)
	end
	return value
end

local function ledger(candidateId: string, drafts: { RevisionEntryDraft }): RevisionLedger
	local id = nonempty(candidateId, "ledger candidateId", 3)
	if type(drafts) ~= "table" then
		error("Generate.revisionLedger expects a candidate id and its revision entries", 2)
	end
	local entries: { RevisionEntry } = {}
	local expected = 1
	for index, draft in drafts do
		local value = entry(draft, index)
		if value.revision ~= expected then
			error(
				("Generate revision ledger expects revision %d at position %d, not %d; revisions start at 1 and rise by one"):format(
					expected,
					index,
					value.revision
				),
				2
			)
		end
		expected += 1
		table.insert(entries, value)
	end
	if #entries == 0 then
		error("Generate revision ledger must carry at least the first revision", 2)
	end
	for index = 1, #entries - 1 do
		if entries[index].outcome == "open" then
			error(
				("Generate revision ledger leaves revision %d open behind a later revision; only the head may be open"):format(
					entries[index].revision
				),
				2
			)
		end
	end
	local head = entries[#entries]
	local settled = head.outcome == "approved"
	local partial = {
		schemaVersion = SCHEMA_VERSION,
		candidateId = id,
		entries = entries,
		head = head,
		settled = settled,
		nextRevision = if head.outcome == "open" then nil else head.revision + 1,
	}
	local result = table.clone(partial)
	result.fingerprint = Canonical.fingerprint(partial)
	return result
end

local function roll(current: RevisionLedger, draft: RollDraft): CandidateRevisionDraft
	if type(current) ~= "table" or current.schemaVersion ~= SCHEMA_VERSION then
		error("Generate.rollCandidate expects a revision ledger", 2)
	end
	if type(draft) ~= "table" then
		error("Generate.rollCandidate expects the next revision's producer and artifacts", 2)
	end
	local revision = current.nextRevision
	if revision == nil then
		error(
			("Generate revision ledger %s leaves revision %d open; a candidate rolls only after its review resolves"):format(
				current.candidateId,
				current.head.revision
			),
			2
		)
	end
	if current.settled and draft.supersede ~= true then
		error(
			("Generate revision ledger %s settled at approved revision %d; rolling past an approval must declare supersede"):format(
				current.candidateId,
				current.head.revision
			),
			2
		)
	end
	local artifacts: { ArtifactRef } = {}
	local seen: { [string]: boolean } = {}
	for index, reference in draft.artifacts do
		if type(reference) ~= "table" then
			error(("Generate revision artifact %d must be an artifact reference"):format(index), 2)
		end
		local artifactId = nonempty(reference.id, ("artifact %d id"):format(index), 3)
		if
			reference.digestAlgorithm ~= "sha256"
			or type(reference.digest) ~= "string"
			or #reference.digest ~= 64
			or string.match(reference.digest, "^[0-9a-f]+$") == nil
		then
			error(("Generate revision artifact %d requires a lowercase SHA-256 digest"):format(index), 2)
		end
		if seen[artifactId] then
			error(("Generate revision artifacts repeat %q"):format(artifactId), 2)
		end
		seen[artifactId] = true
		table.insert(artifacts, { id = artifactId, digest = reference.digest, digestAlgorithm = "sha256" })
	end
	if #artifacts == 0 then
		error("Generate revision roll must bind at least one candidate artifact digest", 2)
	end
	return {
		candidateId = current.candidateId,
		revision = revision :: number,
		producer = nonempty(draft.producer, "roll producer", 3),
		artifacts = artifacts,
	}
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	OUTCOMES = OUTCOMES,
	ledger = ledger,
	entryFor = entryFor,
	outcomeFor = outcomeFor,
	roll = roll,
}
