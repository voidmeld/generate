--!strict

local Generate = require "../core"

type Artifact = Generate.Artifact
type Brief = Generate.Brief
type StageOutcome = Generate.StageOutcome

export type Creator = {
	type: "group" | "user",
	id: string,
}

export type Grant = {
	schemaVersion: number,
	id: string,
	actor: string,
	policy: string,
	briefFingerprint: string,
	idempotencyKey: string,
	artifactDigest: string,
	semanticId: string,
	displayName: string?,
	description: string?,
	target: string,
	assetType: string,
	creator: Creator,
	action: "create" | "update",
	assetId: string?,
	visibility: "private" | "restricted",
	permissionChanges: boolean,
	maxAttempts: number,
}

export type PublicationRequest = {
	grant: Grant,
	artifact: Artifact,
	idempotencyKey: string,
	grantFingerprint: string,
}

export type Published = {
	status: "published",
	assetId: string,
	version: string,
	operationId: string,
	previousVersion: string?,
	rollbackToken: string,
}

export type PublishFault = {
	status: "faulted",
	detail: string,
	rollbackToken: string?,
}

export type Readback = {
	artifact: Artifact,
	assetId: string,
	version: string,
	semanticId: string,
	displayName: string?,
	description: string?,
	target: string,
	assetType: string,
	creator: Creator,
	visibility: "private" | "restricted",
}

export type Operations = {
	toolVersion: string,

	publish: (request: PublicationRequest) -> Published | PublishFault,
	readback: (published: Published, request: PublicationRequest) -> Readback,
}

local GRANT_KEYS: { [string]: boolean } = {
	schemaVersion = true,
	id = true,
	actor = true,
	policy = true,
	briefFingerprint = true,
	idempotencyKey = true,
	artifactDigest = true,
	semanticId = true,
	displayName = true,
	description = true,
	target = true,
	assetType = true,
	creator = true,
	action = true,
	assetId = true,
	visibility = true,
	permissionChanges = true,
	maxAttempts = true,
}

local CREATOR_KEYS: { [string]: boolean } = {
	type = true,
	id = true,
}

local function exactKeys(value: { [unknown]: unknown }, allowed: { [string]: boolean }, label: string)
	for key in value do
		if type(key) ~= "string" or not allowed[key] then
			error(("Generate Roblox %s carries unknown field %s"):format(label, tostring(key)), 3)
		end
	end
end

local function nonempty(value: unknown): boolean
	return type(value) == "string" and value ~= ""
end

local function sha256(value: unknown): boolean
	return type(value) == "string" and #value == 64 and string.match(value, "^[0-9a-f]+$") ~= nil
end

local function grant(draft: Grant): Grant
	if type(draft) ~= "table" then
		error("Generate Roblox publication grant must be a table", 2)
	end
	exactKeys(draft :: { [unknown]: unknown }, GRANT_KEYS, "publication grant")
	if
		draft.schemaVersion ~= 1
		or not nonempty(draft.id)
		or not nonempty(draft.actor)
		or not nonempty(draft.policy)
		or not nonempty(draft.briefFingerprint)
		or not nonempty(draft.idempotencyKey)
		or not sha256(draft.artifactDigest)
		or not nonempty(draft.semanticId)
		or not nonempty(draft.target)
		or not nonempty(draft.assetType)
	then
		error("Generate Roblox publication grant has incomplete identity", 2)
	end
	if
		(draft.displayName ~= nil or draft.description ~= nil)
		and (not nonempty(draft.displayName) or not nonempty(draft.description))
	then
		error("Generate Roblox publication grant displayName and description must both be non-empty when configured", 2)
	end
	if type(draft.creator) ~= "table" then
		error("Generate Roblox publication grant requires a creator", 2)
	end
	exactKeys(draft.creator :: { [unknown]: unknown }, CREATOR_KEYS, "publication creator")
	if (draft.creator.type ~= "group" and draft.creator.type ~= "user") or not nonempty(draft.creator.id) then
		error("Generate Roblox publication grant has an invalid creator", 2)
	end
	if draft.action ~= "create" and draft.action ~= "update" then
		error("Generate Roblox publication grant action must be create or update", 2)
	end
	if draft.action == "create" and draft.assetId ~= nil then
		error("Generate Roblox create grant cannot choose an existing asset", 2)
	end
	if draft.action == "update" and not nonempty(draft.assetId) then
		error("Generate Roblox update grant must bind one existing asset", 2)
	end
	if draft.visibility ~= "private" and draft.visibility ~= "restricted" then
		error("Generate Roblox publication grant may create only private or restricted assets", 2)
	end
	if draft.permissionChanges ~= false then
		error("Generate Roblox publication grant cannot authorize permission changes", 2)
	end
	if draft.maxAttempts ~= 1 then
		error("Generate Roblox publication grant must authorize exactly one attempt", 2)
	end
	return {
		schemaVersion = 1,
		id = draft.id,
		actor = draft.actor,
		policy = draft.policy,
		briefFingerprint = draft.briefFingerprint,
		idempotencyKey = draft.idempotencyKey,
		artifactDigest = draft.artifactDigest,
		semanticId = draft.semanticId,
		displayName = draft.displayName,
		description = draft.description,
		target = draft.target,
		assetType = draft.assetType,
		creator = { type = draft.creator.type, id = draft.creator.id },
		action = draft.action,
		assetId = draft.assetId,
		visibility = draft.visibility,
		permissionChanges = false,
		maxAttempts = 1,
	}
end

local function mismatch(granted: Grant, brief: Brief, source: Artifact): string?
	if Generate.briefFingerprint(brief) ~= granted.briefFingerprint then
		return "brief contents do not match the publication grant"
	end
	if source.digest ~= granted.artifactDigest then
		return "source artifact digest does not match the publication grant"
	end
	if brief.delivery.semanticId ~= granted.semanticId then
		return "brief semantic identity does not match the publication grant"
	end
	if brief.delivery.target ~= granted.target then
		return "brief destination does not match the publication grant"
	end
	return nil
end

local function readbackMismatch(readback: Readback, published: Published, granted: Grant): string?
	if readback.assetId ~= published.assetId or readback.version ~= published.version then
		return "asset or version identity"
	end
	if readback.semanticId ~= granted.semanticId or readback.target ~= granted.target then
		return "semantic identity or destination"
	end
	if granted.displayName ~= nil and readback.displayName ~= granted.displayName then
		return "public display name"
	end
	if granted.description ~= nil and readback.description ~= granted.description then
		return "public description"
	end
	if readback.assetType ~= granted.assetType then
		return "asset type"
	end
	if readback.creator.type ~= granted.creator.type or readback.creator.id ~= granted.creator.id then
		return "creator"
	end
	if readback.visibility ~= granted.visibility then
		return "visibility"
	end
	if granted.action == "update" and published.assetId ~= granted.assetId then
		return "updated asset identity"
	end
	if readback.artifact.semanticId ~= granted.semanticId then
		return "delivered artifact semantic identity"
	end
	return nil
end

local function publicationMetadata(
	granted: Grant,
	published: Published,
	grantFingerprint: string,
	idempotencyKey: string
): { [string]: string }
	local metadata: { [string]: string } = {
		grantId = granted.id,
		grantFingerprint = grantFingerprint,
		grantActor = granted.actor,
		grantPolicy = granted.policy,
		publicationAction = granted.action,
		assetId = published.assetId,
		version = published.version,
		operationId = published.operationId,
		creatorType = granted.creator.type,
		creatorId = granted.creator.id,
		assetType = granted.assetType,
		visibility = granted.visibility,
		semanticId = granted.semanticId,
		target = granted.target,
		idempotencyKey = idempotencyKey,
	}
	if granted.displayName ~= nil then
		metadata.displayName = granted.displayName
		metadata.description = granted.description :: string
	end
	return metadata
end

local function publish(
	operations: Operations,
	brief: Brief,
	artifacts: { Artifact },
	draft: Grant,
	idempotencyKey: string
): StageOutcome
	if operations.toolVersion == "" then
		return { status = "faulted", detail = "Roblox publication requires an exact adapter version" }
	end
	if idempotencyKey == "" then
		return { status = "faulted", detail = "Roblox publication requires a stable idempotency key" }
	end
	local source = artifacts[#artifacts]
	if source == nil then
		return { status = "rejected", detail = "Roblox publication requires an accepted source artifact" }
	end
	local grantedOk, granted = pcall(grant, draft)
	if not grantedOk then
		return { status = "rejected", detail = tostring(granted) }
	end
	local issue = mismatch(granted :: Grant, brief, source)
	if issue ~= nil then
		return { status = "rejected", detail = "Roblox publication refused: " .. issue }
	end
	if idempotencyKey ~= (granted :: Grant).idempotencyKey then
		return { status = "rejected", detail = "Roblox publication refused: stage idempotency key is outside the grant" }
	end
	local grantFingerprint = Generate.fingerprint(granted)
	local request: PublicationRequest = {
		grant = granted :: Grant,
		artifact = source,
		idempotencyKey = idempotencyKey,
		grantFingerprint = grantFingerprint,
	}
	local ok, result = pcall(operations.publish, request)
	if not ok then
		return {
			status = "faulted",
			detail = "Roblox asset publication raised ambiguously: " .. tostring(result),
		}
	end
	if type(result) ~= "table" then
		return { status = "faulted", detail = "Roblox publication returned no result" }
	end
	if result.status == "faulted" then
		local failure = result :: PublishFault
		return {
			status = "faulted",
			detail = failure.detail,
			rollbackToken = failure.rollbackToken,
		}
	end
	local published = result :: Published
	local partialRollbackToken: string? = if nonempty(published.rollbackToken) then published.rollbackToken else nil
	if
		published.status ~= "published"
		or not nonempty(published.assetId)
		or not nonempty(published.version)
		or not nonempty(published.operationId)
		or partialRollbackToken == nil
	then
		return {
			status = "faulted",
			detail = "Roblox publication returned without complete identity and rollback data",
			rollbackToken = partialRollbackToken,
		}
	end
	local rollbackToken = published.rollbackToken
	if (granted :: Grant).action == "update" and published.assetId ~= (granted :: Grant).assetId then
		return {
			status = "faulted",
			detail = "Roblox publication updated an asset outside the grant",
			rollbackToken = rollbackToken,
		}
	end
	local checked, observed = pcall(operations.readback, published, request)
	if not checked then
		return {
			status = "faulted",
			detail = "Roblox asset readback failed after publication: " .. tostring(observed),
			rollbackToken = rollbackToken,
		}
	end
	if type(observed) ~= "table" or type(observed.creator) ~= "table" then
		return {
			status = "faulted",
			detail = "Roblox asset readback returned no bound identity",
			rollbackToken = rollbackToken,
		}
	end
	local readback = observed :: Readback
	local drift = readbackMismatch(readback, published, granted :: Grant)
	if drift ~= nil then
		return {
			status = "faulted",
			detail = "Roblox asset readback disagreed with granted " .. drift,
			rollbackToken = rollbackToken,
		}
	end
	local metadata = publicationMetadata(granted :: Grant, published, grantFingerprint, idempotencyKey)
	return {
		status = "returned",
		output = {
			artifacts = { readback.artifact },
			rollbackToken = rollbackToken,
			invocations = {
				{
					tool = "Roblox asset publication and readback",
					toolVersion = operations.toolVersion,
					provider = "roblox",
					parametersFingerprint = Generate.fingerprint {
						grantFingerprint = grantFingerprint,
						idempotencyKey = idempotencyKey,
					},
					deterministic = false,
				},
			},
			metadata = metadata,
		},
	}
end

return { grant = grant, publish = publish }
