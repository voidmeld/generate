--!strict

local Generate = require "../core"
local Units = require "./units"

export type Creator = {
	type: "group" | "user",
	id: string,
}

export type Visibility = "private" | "restricted"

export type DestinationDraft = {
	creator: Creator,
	assetType: string,
	displayName: string?,
	description: string?,
	visibility: Visibility?,
	credentialName: string,
	assetId: string?,
	grantUniverses: { number }?,
	verifyDependencies: boolean?,
}

export type DestinationFields = {
	creator: Creator,
	assetType: string,
	displayName: string?,
	description: string?,
	visibility: Visibility,
	credentialName: string,
	assetId: string?,
	grantUniverses: { number }?,
	verifyDependencies: boolean,
}

export type GrantStatus = "granted" | "refused"

export type UniverseGrant = {
	universeId: number,
	status: GrantStatus,
	grantedAtUnix: number?,
	refusal: string?,
}

export type DependencyGrant = {
	assetId: string,
	universeId: number,
	status: GrantStatus,
	grantedAtUnix: number?,
	readable: boolean,
	moderationState: string?,
	refusal: string?,
}

export type AccessClosure = {
	sourceReceiptFingerprint: string,
	intentPath: string,
	intentDigest: string,
}

export type Facts = {
	universeGrants: { UniverseGrant },
	dependencyGrants: { DependencyGrant },
	accessClosure: AccessClosure?,
}

export type CollisionMode = "walkable" | "blocking" | "decorative"

export type RefusalReason = "mesh_not_loaded" | "bounds_violation" | "collision_mismatch" | "asset_error_line"

export type BoundsStuds = Units.Studs

export type Measurements = {
	meshLoaded: boolean,
	triangleCount: number?,
	boundingBoxStuds: BoundsStuds?,
	expectedCollisionMode: CollisionMode?,
	observedCollisionMode: CollisionMode?,
}

export type RequestDraft = {
	receiptId: string,
	sourceReceiptFingerprint: string,
	briefFingerprint: string,
	artifactId: string,
	artifactDigest: string,
	assetId: string,
	version: string,
	grantId: string,
	grantFingerprint: string,
	writeAheadDigest: string,
	creator: Creator,
	universeIds: { number },
	dependencyAssetIds: { string },
	accessFingerprint: string,
	studioMcpVersion: string,
	windowSeconds: number,
	universeId: number,
	placeId: number,
	consumerId: string,
	buildId: string,
}

local ADAPTER = "roblox"
local ACCESS_CLOSURE_PENDING = "access-closure-pending"
local FAILED_COMPENSATION = "failed-compensation"

local DESTINATION_KEYS: { [string]: boolean } = {
	creator = true,
	assetType = true,
	displayName = true,
	description = true,
	visibility = true,
	credentialName = true,
	assetId = true,
	grantUniverses = true,
	verifyDependencies = true,
}

local CREATOR_KEYS: { [string]: boolean } = {
	type = true,
	id = true,
}

local REFUSAL_REASONS: { [string]: boolean } = {
	mesh_not_loaded = true,
	bounds_violation = true,
	collision_mismatch = true,
	asset_error_line = true,
}

local function nonempty(value: unknown): boolean
	return type(value) == "string" and value ~= ""
end

local function sha256(value: unknown): boolean
	return type(value) == "string" and #(value :: string) == 64 and string.match(value :: string, "^[0-9a-f]+$") ~= nil
end

local function positiveInteger(value: unknown): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function exactKeys(value: { [unknown]: unknown }, allowed: { [string]: boolean }, label: string)
	for key in value do
		if type(key) ~= "string" or not allowed[key] then
			error(("Generate Roblox destination %s carries unknown field %s"):format(label, tostring(key)), 4)
		end
	end
end

local function grantUniverses(draft: unknown): { number }?
	if draft == nil then
		return nil
	end
	if type(draft) ~= "table" then
		error("Generate Roblox destination grantUniverses must be an array of universe ids", 3)
	end
	local ids: { number } = {}
	local seen: { [number]: boolean } = {}
	local index = 0
	for key, value in draft :: { [unknown]: unknown } do
		index += 1
		if type(key) ~= "number" or key ~= index or not positiveInteger(value) then
			error(
				"Generate Roblox destination grantUniverses must be a dense array of distinct positive universe ids",
				3
			)
		end
		local id = value :: number
		if seen[id] then
			error("Generate Roblox destination grantUniverses must not repeat a universe id", 3)
		end
		seen[id] = true
		table.insert(ids, id)
	end
	if #ids == 0 then
		error("Generate Roblox destination grantUniverses must be non-empty when declared", 3)
	end
	return ids
end

local function normalize(input: unknown): DestinationFields
	if type(input) ~= "table" then
		error("Generate Roblox destination must be a table", 3)
	end
	local draft = input :: DestinationDraft
	exactKeys(draft :: { [unknown]: unknown }, DESTINATION_KEYS, "destination")
	if type(draft.creator) ~= "table" then
		error("Generate Roblox destination creator must name the asset owner", 3)
	end
	exactKeys(draft.creator :: { [unknown]: unknown }, CREATOR_KEYS, "destination.creator")
	if (draft.creator.type ~= "group" and draft.creator.type ~= "user") or not nonempty(draft.creator.id) then
		error("Generate Roblox destination creator must be { type = group | user, id = <non-empty id> }", 3)
	end
	if not nonempty(draft.assetType) or string.match(draft.assetType, "^[A-Za-z][A-Za-z0-9]*$") == nil then
		error("Generate Roblox destination assetType must be one platform asset type name", 3)
	end
	if
		(draft.displayName ~= nil or draft.description ~= nil)
		and (not nonempty(draft.displayName) or not nonempty(draft.description))
	then
		error("Generate Roblox destination displayName and description must both be non-empty when configured", 3)
	end
	local visibility = draft.visibility or "private"
	if visibility ~= "private" and visibility ~= "restricted" then
		error("Generate Roblox destination visibility may be only private or restricted", 3)
	end
	if
		not nonempty(draft.credentialName)
		or #draft.credentialName > 64
		or string.match(draft.credentialName, "^[A-Z][A-Z0-9_]*$") == nil
	then
		error(
			"Generate Roblox destination credentialName must name an environment variable (for example ASSETS_PUBLISH_KEY), never carry a credential value",
			3
		)
	end
	if draft.assetId ~= nil and not nonempty(draft.assetId) then
		error("Generate Roblox destination assetId must be a non-empty existing asset id when declared", 3)
	end
	local universes = grantUniverses(draft.grantUniverses)
	if draft.verifyDependencies ~= nil and type(draft.verifyDependencies) ~= "boolean" then
		error("Generate Roblox destination verifyDependencies must be a boolean when declared", 3)
	end
	if draft.verifyDependencies == true and universes == nil then
		error(
			"Generate Roblox destination verifyDependencies requires grantUniverses; a dependency is verified against the universes that must load it",
			3
		)
	end
	return {
		creator = { type = draft.creator.type, id = draft.creator.id },
		assetType = draft.assetType,
		displayName = draft.displayName,
		description = draft.description,
		visibility = visibility,
		credentialName = draft.credentialName,
		assetId = draft.assetId,
		grantUniverses = universes,
		verifyDependencies = draft.verifyDependencies == true,
	}
end

local function descriptorOf(fields: DestinationFields): { [string]: unknown }
	return {
		creator = { type = fields.creator.type, id = fields.creator.id },
		assetType = fields.assetType,
		displayName = fields.displayName,
		description = fields.description,
		visibility = fields.visibility,
		credentialName = fields.credentialName,
		assetId = fields.assetId,
		grantUniverses = fields.grantUniverses,
		verifyDependencies = fields.verifyDependencies,
	}
end

local function destination(draft: DestinationDraft): Generate.Destination
	return { adapter = ADAPTER, descriptor = descriptorOf(normalize(draft)) }
end

local function readDestination(value: Generate.Destination): DestinationFields
	if type(value) ~= "table" or value.adapter ~= ADAPTER then
		error("Generate Roblox destination requires the roblox adapter", 2)
	end
	local fields = normalize(value.descriptor)
	if Generate.fingerprint(value.descriptor) ~= Generate.fingerprint(descriptorOf(fields)) then
		error("Generate Roblox destination descriptor must be the normalized descriptor", 2)
	end
	return fields
end

local function tableRows(value: unknown): { unknown }?
	if type(value) ~= "table" then
		return nil
	end
	return value :: { unknown }
end

local function factsFault(facts: { [string]: unknown }): string?
	if type(facts) ~= "table" then
		return "publication facts must be a table"
	end
	local universes = tableRows(facts.universeGrants)
	if universes == nil then
		return "publication facts must report their universe grants, even when empty"
	end
	for _, row in universes do
		if type(row) ~= "table" then
			return "publication universe grants must each name a positive universe id"
		end
		local grant = row :: UniverseGrant
		if not positiveInteger(grant.universeId) then
			return "publication universe grants must each name a positive universe id"
		end
		if grant.status ~= "granted" and grant.status ~= "refused" then
			return "publication universe grants must each name granted or refused"
		end
		if grant.status == "granted" then
			if type(grant.grantedAtUnix) ~= "number" or grant.grantedAtUnix <= 0 or grant.refusal ~= nil then
				return "publication universe grants must carry grantedAtUnix and no refusal when granted"
			end
		elseif not nonempty(grant.refusal) or grant.grantedAtUnix ~= nil then
			return "publication universe grants must carry a refusal and no grantedAtUnix when refused"
		end
	end
	local dependencies = tableRows(facts.dependencyGrants)
	if dependencies == nil then
		return "publication facts must report their dependency grants, even when empty"
	end
	for _, row in dependencies do
		if type(row) ~= "table" then
			return "publication dependency grants must each name a positive numeric asset id"
		end
		local grant = row :: DependencyGrant
		if not nonempty(grant.assetId) or string.match(grant.assetId, "^[1-9][0-9]*$") == nil then
			return "publication dependency grants must each name a positive numeric asset id"
		end
		if not positiveInteger(grant.universeId) then
			return "publication dependency grants must each name a positive universe id"
		end
		if grant.status ~= "granted" and grant.status ~= "refused" then
			return "publication dependency grants must each name granted or refused"
		end
		if type(grant.readable) ~= "boolean" then
			return "publication dependency grants must say whether the dependency read back loadable"
		end
		if grant.status == "granted" and (type(grant.grantedAtUnix) ~= "number" or grant.grantedAtUnix <= 0) then
			return "publication dependency grants must carry grantedAtUnix when granted"
		end
		if grant.status == "refused" and grant.grantedAtUnix ~= nil then
			return "publication dependency grants must carry no grantedAtUnix when refused"
		end
		if (grant.status == "refused" or not grant.readable) and not nonempty(grant.refusal) then
			return "publication dependency grants must carry a refusal when not granted and loadable"
		end
		if grant.status == "granted" and grant.readable and grant.refusal ~= nil then
			return "publication dependency grants must carry no refusal when granted and loadable"
		end
	end
	if facts.accessClosure ~= nil then
		local closure = facts.accessClosure :: AccessClosure
		if
			type(closure) ~= "table"
			or not nonempty(closure.sourceReceiptFingerprint)
			or not nonempty(closure.intentPath)
			or not sha256(closure.intentDigest)
		then
			return "publication accessClosure requires a bound source and SHA-256 intent"
		end
	end
	return nil
end

local function facts(value: Facts): { [string]: unknown }
	local result: { [string]: unknown } = {
		universeGrants = value.universeGrants,
		dependencyGrants = value.dependencyGrants,
		accessClosure = value.accessClosure,
	}
	local fault = factsFault(result)
	if fault ~= nil then
		error("Generate Roblox facts are invalid: " .. fault, 2)
	end
	return result
end

local function readFacts(record: Generate.PublicationRecord): Facts
	local fault = factsFault(record.facts)
	if fault ~= nil then
		error("Generate Roblox facts are invalid: " .. fault, 2)
	end
	return (record.facts :: unknown) :: Facts
end

local function bindingFault(request: Generate.HostVerificationRequest): string?
	local binding = request.binding
	if type(binding) ~= "table" then
		return "publication verificationRequest must carry its binding"
	end
	local creator = binding.creator :: unknown
	if
		type(creator) ~= "table"
		or ((creator :: Creator).type ~= "group" and (creator :: Creator).type ~= "user")
		or not nonempty((creator :: Creator).id)
	then
		return "publication verificationRequest binding must name the creator"
	end
	local universeIds = tableRows(binding.universeIds)
	local dependencyAssetIds = tableRows(binding.dependencyAssetIds)
	if universeIds == nil or dependencyAssetIds == nil then
		return "publication verificationRequest binding must list its universe and dependency ids"
	end
	for _, id in universeIds do
		if not positiveInteger(id) then
			return "publication verificationRequest binding universe ids must be positive integers"
		end
	end
	for _, id in dependencyAssetIds do
		if not nonempty(id) then
			return "publication verificationRequest binding dependency ids must be non-empty"
		end
	end
	if
		not positiveInteger(binding.universeId)
		or not positiveInteger(binding.placeId)
		or not nonempty(binding.consumerId)
	then
		return "publication verificationRequest binding must name the universe, place and consumer"
	end
	if not nonempty(request.host) then
		return "publication verificationRequest must name the Studio version"
	end
	return nil
end

local function recordFault(record: Generate.PublicationRecord): string?
	local fault = Generate.publicationFault(record)
	if fault ~= nil then
		return fault
	end
	local factsProblem = factsFault(record.facts)
	if factsProblem ~= nil then
		return factsProblem
	end
	if record.verification ~= nil and record.verification.disposition == "refused" then
		if not REFUSAL_REASONS[record.verification.refusalReason :: string] then
			return "publication record verification must name one declared refusal reason when refused"
		end
	end
	if record.verificationRequest ~= nil then
		return bindingFault(record.verificationRequest)
	end
	return nil
end

local function request(draft: RequestDraft): Generate.HostVerificationRequest
	local payload: Generate.HostVerificationRequestPayload = {
		schemaVersion = 1,
		receiptId = draft.receiptId,
		sourceReceiptFingerprint = draft.sourceReceiptFingerprint,
		briefFingerprint = draft.briefFingerprint,
		artifactId = draft.artifactId,
		artifactDigest = draft.artifactDigest,
		contentId = draft.assetId,
		version = draft.version,
		grantId = draft.grantId,
		grantFingerprint = draft.grantFingerprint,
		writeAheadDigest = draft.writeAheadDigest,
		stateFingerprint = draft.accessFingerprint,
		host = draft.studioMcpVersion,
		hostBuild = draft.buildId,
		windowSeconds = draft.windowSeconds,
		binding = {
			creator = { type = draft.creator.type, id = draft.creator.id },
			universeIds = draft.universeIds,
			dependencyAssetIds = draft.dependencyAssetIds,
			universeId = draft.universeId,
			placeId = draft.placeId,
			consumerId = draft.consumerId,
		},
	}
	local result = table.clone(payload) :: Generate.HostVerificationRequest
	result.fingerprint = Generate.fingerprint(payload)
	local fault = bindingFault(result)
	if fault ~= nil then
		error("Generate Roblox verification request is invalid: " .. fault, 2)
	end
	return result
end

local function check(record: Generate.PublicationRecord, verb: string)
	local fault = recordFault(record)
	if fault ~= nil then
		error(("Generate Roblox %s refuses an invalid publication record: %s"):format(verb, fault), 3)
	end
end

local function attach(receipt: Generate.Receipt, record: Generate.PublicationRecord): Generate.Receipt
	check(record, "attach")
	return Generate.attachPublication(receipt, record)
end

local function reconcile(receipt: Generate.Receipt, record: Generate.PublicationRecord): Generate.Receipt
	check(record, "reconcile")
	local prior = receipt.publication
	if prior ~= nil and prior.state == "stopped" then
		local priorFacts = readFacts(prior)
		if
			prior.disposition ~= FAILED_COMPENSATION
			or record.disposition ~= ACCESS_CLOSURE_PENDING
			or #priorFacts.universeGrants ~= 0
			or #priorFacts.dependencyGrants ~= 0
			or priorFacts.accessClosure ~= nil
		then
			error(
				"Generate Roblox reconcile requires a failed-compensation receipt with unattempted access and an access-closure-pending record",
				2
			)
		end
	end
	return Generate.reconcilePublication(receipt, record)
end

local function confirm(receipt: Generate.Receipt, record: Generate.PublicationRecord): Generate.Receipt
	check(record, "confirm")
	local pending = receipt.publication
	if pending ~= nil and pending.disposition == ACCESS_CLOSURE_PENDING then
		local closure = readFacts(record).accessClosure
		if
			closure == nil
			or closure.sourceReceiptFingerprint ~= receipt.fingerprint
			or record.verification ~= nil
			or record.verificationCompletion ~= nil
		then
			error("Generate Roblox confirm requires a bound access closure before a deferred verification", 2)
		end
		local changed = table.clone(pending)
		changed.disposition = record.disposition
		changed.detail = record.detail
		changed.state = record.state
		changed.facts = record.facts
		changed.verificationRequest = record.verificationRequest
		for index, stage in pending.stages do
			if Generate.fingerprint(record.stages[index]) ~= Generate.fingerprint(stage) then
				error("Generate Roblox confirm must preserve the access closure source stages", 2)
			end
		end
		changed.stages = record.stages
		if Generate.fingerprint(record) ~= Generate.fingerprint(changed) then
			error("Generate Roblox confirm must preserve the original upload during access closure", 2)
		end
	end
	return Generate.confirmPublication(receipt, record)
end

local function hostVerified(receipt: Generate.Receipt): boolean
	local record = receipt.publication
	return record ~= nil and recordFault(record) == nil and Generate.hostVerified(receipt)
end

return {
	REFUSAL_REASONS = REFUSAL_REASONS,
	destination = destination,
	readDestination = readDestination,
	facts = facts,
	readFacts = readFacts,
	request = request,
	recordFault = recordFault,
	attach = attach,
	confirm = confirm,
	reconcile = reconcile,
	hostVerified = hostVerified,
}
