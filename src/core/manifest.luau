--!strict

local Canonical = require "./canonical"
local Execution = require "./execution"
local Provenance = require "./provenance"
local Review = require "./review"
local Types = require "./types"

type DeliveryEntry = Types.DeliveryEntry
type DeliveryManifest = Types.DeliveryManifest
type Receipt = Types.Receipt

local SCHEMA_VERSION = 1

local function create(receipt: Receipt, artifactIds: { string }): DeliveryManifest
	if receipt.status ~= "accepted" then
		error("Generate manifest requires an accepted receipt", 2)
	end
	if receipt.fingerprint ~= Execution.receiptFingerprint(receipt) then
		error("Generate manifest refuses a receipt changed after execution", 2)
	end
	if #artifactIds == 0 then
		error("Generate manifest requires at least one explicit deliverable artifact", 2)
	end
	local artifactsById: { [string]: Types.Artifact } = {}
	for _, artifact in receipt.artifacts do
		artifactsById[artifact.id] = artifact
	end
	local derivationsById: { [string]: Types.Derivation } = {}
	for _, derivation in receipt.derivations do
		derivationsById[derivation.artifactId] = derivation
	end
	local seenArtifacts: { [string]: boolean } = {}
	local seenSemantic: { [string]: boolean } = {}
	local entries: { DeliveryEntry } = {}
	for _, artifactId in artifactIds do
		local artifact = artifactsById[artifactId]
		if artifact == nil then
			error(("Generate manifest artifact %q is absent from receipt %q"):format(artifactId, receipt.id), 2)
		end
		if seenArtifacts[artifactId] then
			error(("Generate manifest repeats artifact %q"):format(artifactId), 2)
		end
		if artifact.semanticId == nil or artifact.semanticId == "" then
			error(("Generate manifest artifact %q has no semantic delivery identity"):format(artifactId), 2)
		end
		if seenSemantic[artifact.semanticId] then
			error(("Generate manifest repeats semantic identity %q"):format(artifact.semanticId), 2)
		end

		local bound: Types.ResolvedReview? = nil
		for _, review in receipt.reviews do
			if review.disposition == "approved" and Review.binds(review, artifact.id, artifact.digest) then
				bound = review
				break
			end
		end
		if bound == nil then
			error(
				("Generate manifest artifact %q carries no resolved approval bound to its exact digest"):format(
					artifactId
				),
				2
			)
		end
		local review = bound :: Types.ResolvedReview
		local faults = Provenance.requirementFaults(
			derivationsById[artifact.id],
			receipt.provenanceContract,
			derivationsById,
			artifact.id
		)
		if #faults > 0 then
			error(("Generate manifest refuses unknown required history: %s"):format(faults[1]), 2)
		end
		local derivation = derivationsById[artifact.id]
		seenArtifacts[artifactId] = true
		seenSemantic[artifact.semanticId] = true
		table.insert(entries, {
			semanticId = artifact.semanticId,
			artifactId = artifact.id,
			digest = artifact.digest,
			digestAlgorithm = artifact.digestAlgorithm,
			mediaType = artifact.mediaType,
			byteCount = artifact.byteCount,
			locator = artifact.locator,
			reviewId = review.id,
			reviewFingerprint = review.fingerprint,
			candidateFingerprint = review.candidateFingerprint,
			derivationFingerprint = if derivation ~= nil then derivation.fingerprint else nil,
			metadata = table.clone(artifact.metadata),
		})
	end
	table.sort(entries, function(a, b)
		return a.semanticId < b.semanticId
	end)
	local partial = {
		schemaVersion = SCHEMA_VERSION,
		id = receipt.briefId .. "/delivery",
		receiptId = receipt.id,
		receiptFingerprint = receipt.fingerprint,
		entries = entries,
	}
	local result = table.clone(partial)
	result.fingerprint = Canonical.fingerprint(partial)
	return result
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	create = create,
}
