--!strict

local Canonical = require "./canonical"
local Publication = require "./publication"
local Secret = require "./secret"
local Types = require "./types"

type Brief = Types.Brief
type BriefDraft = Types.BriefDraft

local SCHEMA_VERSION = 1

local KINDS: { [string]: boolean } = {
	image = true,
	video = true,
	texture = true,
	material = true,
	["rigid-mesh"] = true,
	["modular-mesh"] = true,
	["skinned-mesh"] = true,
	animation = true,
	audio = true,
	voice = true,
	music = true,
	["sound-effect"] = true,
	text = true,
	dialogue = true,
	quest = true,
	localization = true,
	["structured-content"] = true,
	font = true,
	dataset = true,
	other = true,
}

local RIGHTS_FACTS: { [string]: boolean } = {
	source = true,
	license = true,
	owner = true,
	consent = true,
}

local function nonempty(value: unknown, label: string): string
	if type(value) ~= "string" or value == "" then
		error("Generate brief " .. label .. " must be a non-empty string", 3)
	end
	return value
end

local function uniqueStrings(values: { string }, label: string): { string }
	local seen: { [string]: boolean } = {}
	local result: { string } = {}
	for _, value in values do
		nonempty(value, label)
		if seen[value] then
			error(("Generate brief %s contains duplicate %q"):format(label, value), 3)
		end
		seen[value] = true
		table.insert(result, value)
	end
	return result
end

local function create(draft: BriefDraft): Brief
	if type(draft) ~= "table" then
		error("Generate.brief expects a table", 2)
	end
	if draft.schemaVersion ~= nil and draft.schemaVersion ~= SCHEMA_VERSION then
		error(("Generate brief schemaVersion must be %d"):format(SCHEMA_VERSION), 2)
	end
	if not KINDS[draft.kind] then
		error("Generate brief kind is unsupported: " .. tostring(draft.kind), 2)
	end
	if type(draft.intent) ~= "table" or type(draft.review) ~= "table" or type(draft.delivery) ~= "table" then
		error("Generate brief requires intent, review, and delivery contracts", 2)
	end
	if draft.constraints ~= nil and type(draft.constraints) ~= "table" then
		error("Generate brief constraints must be a data table", 2)
	end
	Secret.validate(draft.constraints or {}, "Generate brief constraints")
	Secret.validate(draft.metadata or {}, "Generate brief metadata")
	local destination, hostVerification =
		Publication.destination(draft.delivery.destination, draft.delivery.hostVerification)
	local views = uniqueStrings(draft.review.views, "review.views")
	if #views == 0 then
		error("Generate brief review.views must name at least one canonical view", 2)
	end
	local blindness: Types.ReviewRequirement = draft.review.blindness or "optional"
	if blindness ~= "required" and blindness ~= "optional" then
		error("Generate brief review.blindness must be required or optional", 2)
	end
	local independence: Types.ReviewRequirement = draft.review.independence or "required"
	if independence ~= "required" and independence ~= "optional" then
		error("Generate brief review.independence must be required or optional", 2)
	end
	if (draft.review :: typeof(draft.review) & { secondaryAcceptance: unknown? }).secondaryAcceptance ~= nil then
		error("Generate no longer supports review.secondaryAcceptance; the review decision must approve", 2)
	end
	if draft.provenance ~= nil and type(draft.provenance) ~= "table" then
		error("Generate brief provenance must be a contract table", 2)
	end
	local provenanceDraft: {
		requireParentLineage: boolean?,
		requiredRightsFacts: { Types.RightsFactName }?,
	} = draft.provenance
		or {}
	local requireParentLineage = if provenanceDraft.requireParentLineage == nil
		then true
		else provenanceDraft.requireParentLineage
	if type(requireParentLineage) ~= "boolean" then
		error("Generate brief provenance.requireParentLineage must be a boolean", 2)
	end
	local requiredFacts: { Types.RightsFactName } = {}
	local seenFact: { [string]: boolean } = {}
	local declaredFacts: { Types.RightsFactName } = provenanceDraft.requiredRightsFacts or {}
	for _, name in declaredFacts do
		if not RIGHTS_FACTS[name] then
			error(("Generate brief provenance.requiredRightsFacts names unknown fact %q"):format(tostring(name)), 2)
		end
		if seenFact[name] then
			error(("Generate brief provenance.requiredRightsFacts repeats %q"):format(name), 2)
		end
		seenFact[name] = true
		table.insert(requiredFacts, name)
	end
	table.sort(requiredFacts)
	return {
		schemaVersion = SCHEMA_VERSION,
		id = nonempty(draft.id, "id"),
		kind = draft.kind,
		intent = {
			role = nonempty(draft.intent.role, "intent.role"),
			style = draft.intent.style,
			description = draft.intent.description,
		},
		constraints = table.clone((draft.constraints or {}) :: { [string]: unknown }),
		review = {
			rubric = {
				id = nonempty(draft.review.rubric, "review.rubric"),
				fingerprint = nonempty(draft.review.rubricFingerprint, "review.rubricFingerprint"),
				version = draft.review.rubricVersion,
			},
			views = views,
			blindness = blindness,
			independence = independence,
		},
		provenance = {
			requireParentLineage = requireParentLineage,
			requiredRightsFacts = requiredFacts,
		},
		delivery = {
			semanticId = nonempty(draft.delivery.semanticId, "delivery.semanticId"),
			target = nonempty(draft.delivery.target, "delivery.target"),
			destination = destination,
			hostVerification = hostVerification,
		},
		metadata = table.clone(draft.metadata or {}),
	}
end

local function fingerprint(brief: Brief): string
	return Canonical.fingerprint(brief)
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	create = create,
	fingerprint = fingerprint,
}
