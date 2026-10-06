--!strict

local Canonical = require "./canonical"
local Secret = require "./secret"
local Types = require "./types"

type Derivation = Types.Derivation
type DerivationDraft = Types.DerivationDraft
type ParentRef = Types.ParentRef
type ProvenanceContract = Types.ProvenanceContract
type RightsFact = Types.RightsFact
type RightsFacts = Types.RightsFacts
type RightsFactsDraft = Types.RightsFactsDraft

local SCHEMA_VERSION = 1

local FACT_NAMES: { Types.RightsFactName } = { "consent", "license", "owner", "source" }
local ORIGINS: { [string]: boolean } = { original = true, derived = true, imported = true }
local DISPOSITIONS: { [string]: boolean } = {
	active = true,
	rejected = true,
	parked = true,
	superseded = true,
	approved = true,
}

local function isSha256(value: string): boolean
	return #value == 64 and string.match(value, "^[0-9a-f]+$") ~= nil
end

local function fact(value: RightsFact?, name: string): RightsFact
	if value == nil then
		return { state = "unknown", value = nil }
	end
	if type(value) ~= "table" then
		error(("Generate rights fact %q must be a table"):format(name), 3)
	end
	if value.state == "unknown" then
		if value.value ~= nil then
			error(("Generate rights fact %q is unknown and may not carry a value"):format(name), 3)
		end
		return { state = "unknown", value = nil }
	end
	if value.state ~= "known" then
		error(("Generate rights fact %q state must be known or unknown"):format(name), 3)
	end
	if type(value.value) ~= "string" or value.value == "" then
		error(("Generate rights fact %q claims knowledge without a recorded fact"):format(name), 3)
	end
	return { state = "known", value = value.value }
end

local function rights(draft: RightsFactsDraft?): RightsFacts
	local source: RightsFactsDraft = draft or {}
	Secret.validate(source, "Generate rights facts")
	local facts: RightsFacts = {
		state = "unknown",
		source = fact(source.source, "source"),
		license = fact(source.license, "license"),
		owner = fact(source.owner, "owner"),
		consent = fact(source.consent, "consent"),
		notes = table.clone(source.notes or {}),
	}
	local known = 0
	for _, name in FACT_NAMES do
		if facts[name].state == "known" then
			known += 1
		end
	end
	facts.state = if known == #FACT_NAMES then "known" elseif known == 0 then "unknown" else "partial"
	return facts
end

local function parent(reference: ParentRef, index: number): ParentRef
	if type(reference) ~= "table" then
		error(("Generate derivation parent %d must be a table"):format(index), 3)
	end
	local named = false
	local fields: { "artifactId" | "artifactDigest" | "receiptId" | "receiptFingerprint" | "jobId" | "briefFingerprint" } =
		{ "artifactId", "artifactDigest", "receiptId", "receiptFingerprint", "jobId", "briefFingerprint" }
	for _, field in fields do
		local value = reference[field]
		if value ~= nil then
			if type(value) ~= "string" or value == "" then
				error(("Generate derivation parent %d field %s must be a non-empty string"):format(index, field), 3)
			end
			named = true
		end
	end
	if not named then
		error(("Generate derivation parent %d names no parent artifact, receipt, or job identity"):format(index), 3)
	end
	if reference.artifactDigest ~= nil and not isSha256(reference.artifactDigest) then
		error(("Generate derivation parent %d artifactDigest must be a lowercase SHA-256"):format(index), 3)
	end
	return {
		artifactId = reference.artifactId,
		artifactDigest = reference.artifactDigest,
		receiptId = reference.receiptId,
		receiptFingerprint = reference.receiptFingerprint,
		jobId = reference.jobId,
		briefFingerprint = reference.briefFingerprint,
	}
end

local function digests(values: { string }?, label: string): { string }
	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	local source: { string } = values or {}
	for _, value in source do
		if type(value) ~= "string" or not isSha256(value) then
			error(("Generate derivation %s requires lowercase SHA-256 digests"):format(label), 3)
		end
		if not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end
	table.sort(result)
	return result
end

local function derivation(draft: DerivationDraft): Derivation
	if type(draft) ~= "table" then
		error("Generate.derivation expects a table", 2)
	end
	if type(draft.artifactId) ~= "string" or draft.artifactId == "" then
		error("Generate derivation artifactId must be a non-empty string", 2)
	end
	if type(draft.artifactDigest) ~= "string" or not isSha256(draft.artifactDigest) then
		error("Generate derivation artifactDigest must be a lowercase SHA-256", 2)
	end
	if not ORIGINS[draft.origin] then
		error("Generate derivation origin must be original, derived, or imported", 2)
	end
	local parents: { ParentRef } = {}
	local parentDrafts: { ParentRef } = draft.parents or {}
	for index, reference in parentDrafts do
		table.insert(parents, parent(reference, index))
	end
	if draft.origin == "derived" and #parents == 0 then
		error("Generate derived artifact must name its parent lineage", 2)
	end
	local attempt = draft.attempt or 1
	if type(attempt) ~= "number" or attempt < 1 or attempt % 1 ~= 0 then
		error("Generate derivation attempt must be a positive integer ordinal", 2)
	end
	local disposition: Types.CandidateDisposition = draft.disposition or "active"
	if not DISPOSITIONS[disposition] then
		error("Generate derivation disposition must be active, rejected, parked, superseded, or approved", 2)
	end
	local environment = table.clone(draft.environment or {})
	Secret.validate(environment, "Generate derivation environment")
	local invocation = draft.invocation
	if invocation ~= nil then
		if invocation.tool == "" or invocation.toolVersion == "" or invocation.parametersFingerprint == "" then
			error("Generate derivation invocation requires exact tool, version, and parameter identity", 2)
		end
	end
	local partial = {
		schemaVersion = SCHEMA_VERSION,
		artifactId = draft.artifactId,
		artifactDigest = draft.artifactDigest,
		origin = draft.origin,
		parents = parents,
		inputDigests = digests(draft.inputDigests, "inputDigests"),
		referenceDigests = digests(draft.referenceDigests, "referenceDigests"),
		invocation = invocation,
		environment = environment,
		attempt = attempt,
		disposition = disposition,
		rights = rights(draft.rights),
	}
	local result = table.clone(partial)
	result.fingerprint = Canonical.fingerprint(partial)
	return result
end

local function fingerprintOf(value: Derivation): string
	return Canonical.fingerprint {
		schemaVersion = value.schemaVersion,
		artifactId = value.artifactId,
		artifactDigest = value.artifactDigest,
		origin = value.origin,
		parents = value.parents,
		inputDigests = value.inputDigests,
		referenceDigests = value.referenceDigests,
		invocation = value.invocation,
		environment = value.environment,
		attempt = value.attempt,
		disposition = value.disposition,
		rights = value.rights,
	}
end

local function withDisposition(value: Derivation, disposition: Types.CandidateDisposition): Derivation
	if value.disposition == disposition then
		return value
	end
	if not DISPOSITIONS[disposition] then
		error("Generate derivation disposition must be active, rejected, parked, superseded, or approved", 2)
	end
	local updated = table.clone(value)
	updated.disposition = disposition
	updated.fingerprint = fingerprintOf(updated)
	return updated
end

local function requirementFaults(
	value: Derivation?,
	contract: ProvenanceContract,
	byArtifactId: { [string]: Derivation },
	artifactId: string
): { string }
	local faults: { string } = {}
	if value == nil then
		if contract.requireParentLineage or #contract.requiredRightsFacts > 0 then
			table.insert(faults, ("artifact %q carries no derivation record"):format(artifactId))
		end
		return faults
	end
	if contract.requireParentLineage and value.origin ~= "original" and #value.parents == 0 then
		table.insert(faults, ("artifact %q declares %s origin without parent lineage"):format(artifactId, value.origin))
	end
	for _, name in contract.requiredRightsFacts do
		local claim: RightsFact = value.rights[name]
		if claim == nil or claim.state ~= "known" then
			table.insert(faults, ("artifact %q has unknown-history rights fact %q"):format(artifactId, name))
			continue
		end
		for _, reference in value.parents do
			local parentId = reference.artifactId
			if parentId == nil then
				continue
			end
			local ancestor = byArtifactId[parentId]
			if ancestor == nil then
				continue
			end
			local inherited: RightsFact = ancestor.rights[name]
			if inherited == nil or inherited.state ~= "known" then
				table.insert(
					faults,
					("artifact %q claims rights fact %q that its parent %q does not carry"):format(
						artifactId,
						name,
						parentId
					)
				)
			elseif inherited.value ~= claim.value then
				table.insert(
					faults,
					("artifact %q rights fact %q contradicts its parent %q"):format(artifactId, name, parentId)
				)
			end
		end
	end
	return faults
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	FACT_NAMES = FACT_NAMES,
	derivation = derivation,
	fingerprintOf = fingerprintOf,
	withDisposition = withDisposition,
	rights = rights,
	requirementFaults = requirementFaults,
}
