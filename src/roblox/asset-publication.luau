--!strict

local Generate = require "../core"
local Wire = require "./wire"

type Artifact = Generate.Artifact
type Brief = Generate.Brief
type StageOutcome = Generate.StageOutcome
type Response = Wire.Response
type SendAuthorized = Wire.SendAuthorized
type Decode = Wire.Decode
type Encode = Wire.Encode

local text = Wire.text
local numericId = Wire.numericId

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

export type ReadArtifact = (artifact: Generate.Artifact) -> string
export type WaitBeforePoll = (ordinal: number, operationPath: string) -> ()

export type Options = {
	send: SendAuthorized,

	toolVersion: string,

	encode: Encode,
	decode: Decode,

	readArtifact: ReadArtifact,
	maxPolls: number,
	waitBeforePoll: WaitBeforePoll?,
	moderationPollBudget: number?,

	baseUrl: string?,
}

export type Compensation = {
	status: "ok" | "failed",
	detail: string,
}

export type Adapter = Operations & {
	compensate: (token: string) -> Compensation,
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

local REFUSED = "refused"
local AMBIGUOUS = "ambiguous"
local MODERATION_DELAYED = "moderation-delayed"
local MODERATION_PENDING = "moderation-pending"
local TIMED_OUT = "timed-out"
local PARTIAL = "partial"

local FAULT_DISPOSITIONS: { string } =
	{ REFUSED, AMBIGUOUS, MODERATION_DELAYED, MODERATION_PENDING, TIMED_OUT, PARTIAL }

local DEFAULT_BASE_URL = "https://apis.roblox.com/assets/v1"
local DEFAULT_MODERATION_POLL_BUDGET = 3
local APPROVED: { [string]: boolean } = {
	Approved = true,
	MODERATION_STATE_APPROVED = true,
}
local REJECTED: { [string]: boolean } = {
	Rejected = true,
	MODERATION_STATE_REJECTED = true,
}

local function moderationOutcome(state: string): string
	if APPROVED[state] then
		return "approved"
	end
	if REJECTED[state] then
		return "rejected"
	end
	return "pending"
end

local function fault(disposition: string, detail: string, rollbackToken: string?): PublishFault
	return { status = "faulted", detail = disposition .. ": " .. detail, rollbackToken = rollbackToken }
end

local function dispositionOf(detail: string?): string?
	if detail == nil then
		return nil
	end
	local named = string.match(detail, "^([%a%-]+):")
	if named == nil then
		return nil
	end
	for _, known in FAULT_DISPOSITIONS do
		if named == known then
			return named
		end
	end
	return nil
end

local function base(options: Options): string
	return options.baseUrl or DEFAULT_BASE_URL
end

local function publicationRequestJson(options: Options, grant: Grant): string
	local creatorKey = if grant.creator.type == "group" then "groupId" else "userId"
	local displayName = grant.displayName or grant.semanticId
	local description = grant.description or grant.semanticId
	local fields = {
		'"assetType":' .. options.encode(grant.assetType),
		'"displayName":' .. options.encode(displayName),
		'"description":' .. options.encode(description),
	}
	if grant.action == "update" then
		table.insert(fields, '"assetId":' .. options.encode(grant.assetId))
	end
	table.insert(
		fields,
		'"creationContext":{"creator":{"'
			.. creatorKey
			.. '":'
			.. options.encode(grant.creator.id)
			.. "}"
			.. (if grant.action == "create"
				then ',"assetPrivacy":' .. options.encode(
					if grant.visibility == "restricted" then "restricted" else "default"
				)
				else "")
			.. "}"
	)
	return "{" .. table.concat(fields, ",") .. "}"
end

local function safeFilename(id: string): string
	local safe = string.gsub(id, "[^%w._-]", "-")
	return if safe == "" then "artifact" else safe
end

local function multipart(options: Options, request: PublicationRequest): (string, string)
	local bytes = options.readArtifact(request.artifact)
	if type(bytes) ~= "string" then
		error("the artifact reader returned no bytes", 0)
	end
	if request.artifact.byteCount ~= nil and #bytes ~= request.artifact.byteCount then
		error("the artifact byte count disagrees with the accepted artifact", 0)
	end
	local boundary = "generate-" .. string.sub(request.artifact.digest, 1, 48)
	if string.find(bytes, boundary, 1, true) ~= nil then
		error("the deterministic multipart boundary occurs in the artifact bytes", 0)
	end
	local metadata = publicationRequestJson(options, request.grant)
	local body = table.concat({
		"--" .. boundary,
		'Content-Disposition: form-data; name="request"',
		"Content-Type: application/json",
		"",
		metadata,
		"--" .. boundary,
		('Content-Disposition: form-data; name="fileContent"; filename="%s"'):format(safeFilename(request.artifact.id)),
		"Content-Type: " .. request.artifact.mediaType,
		"",
		bytes,
		"--" .. boundary .. "--",
		"",
	}, "\r\n")
	return body, boundary
end

local function decodedResponse(options: Options, response: unknown, operation: string): { [string]: unknown }
	if type(response) ~= "table" or type((response :: { [string]: unknown }).status) ~= "number" then
		error(operation .. " transport returned no readable response", 0)
	end
	local typed = response :: Response
	if not typed.ok then
		error(("%s answered HTTP %d"):format(operation, typed.status), 0)
	end
	local body = options.decode(typed.body)
	if type(body) ~= "table" then
		error(operation .. " answered with an unreadable body", 0)
	end
	return body :: { [string]: unknown }
end

local function assetUrl(options: Options, assetId: string): string
	return base(options) .. "/assets/" .. assetId
end

local function versionUrl(options: Options, assetId: string, version: string): string
	return base(options) .. "/assets/" .. assetId .. "/versions/" .. version
end

local function getDocument(options: Options, url: string, operation: string): { [string]: unknown }
	local sent, answer = pcall(options.send, {
		method = "GET" :: "GET",
		url = url,
		headers = { Accept = "application/json" },
	})
	if not sent then
		error(operation .. " did not resolve: " .. tostring(answer), 0)
	end
	return decodedResponse(options, answer, operation)
end

local function identifiedAssetId(body: { [string]: unknown }): string?
	local fromField = numericId(body.assetId)
	local fromPath = nil :: string?
	local path = text(body.path)
	if path ~= nil then
		fromPath = numericId(string.match(path :: string, "^assets/(%d+)$"))
	end
	if fromField ~= nil and fromPath ~= nil and fromField ~= fromPath then
		return nil
	end
	return fromField or fromPath
end

local function readAssetDocument(options: Options, assetId: string, operation: string): { [string]: unknown }
	local body = getDocument(options, assetUrl(options, assetId), operation)
	if identifiedAssetId(body) ~= assetId then
		error(operation .. " returned another asset", 0)
	end
	return body
end

local function verifyVersionDocument(body: { [string]: unknown }, assetId: string, version: string)
	local expected = "assets/" .. assetId .. "/versions/" .. version
	if text(body.path) ~= expected then
		error("asset-version readback returned another version path", 0)
	end
end

local function operationPath(body: { [string]: unknown }): string?
	local path = text(body.path)
	if path == nil or string.match(path, "^operations/[%w._%-]+$") == nil then
		return nil
	end
	return path
end

local function operationResult(
	options: Options,
	submitted: { [string]: unknown }
): ({ [string]: unknown }?, string?, string?)
	local path = operationPath(submitted)
	if path == nil then
		return nil, nil, "the submission returned no valid operation path"
	end
	local current = submitted
	for ordinal = 0, options.maxPolls do
		if current.done == true then
			if type(current.error) == "table" then
				local message = text((current.error :: { [string]: unknown }).message) or "the operation failed"
				return nil, path, message
			end
			if type(current.response) ~= "table" then
				return nil, path, "the completed operation returned no asset"
			end
			return current.response :: { [string]: unknown }, path, nil
		end
		if ordinal == options.maxPolls then
			break
		end
		if options.waitBeforePoll ~= nil then
			options.waitBeforePoll(ordinal + 1, path)
		end
		current = getDocument(options, base(options) .. "/" .. path, "operation poll")
		if operationPath(current) ~= path then
			return nil, path, "the operation poll returned another operation identity"
		end
	end
	return nil, path, "the operation remained pending after the granted poll budget"
end

local function moderationState(body: { [string]: unknown }): string
	local moderation = body.moderationResult
	return if type(moderation) == "table"
			and text((moderation :: { [string]: unknown }).moderationState) ~= nil
		then text((moderation :: { [string]: unknown }).moderationState) :: string
		else "unknown"
end

local function normalizedAssetType(value: unknown): string
	local named = string.upper(tostring(value))
	named = string.gsub(named, "^ASSET_TYPE_", "")
	return string.gsub(named, "[^A-Z0-9]", "")
end

local function creatorOf(body: { [string]: unknown }): Creator
	local context = body.creationContext
	local creator = if type(context) == "table" then (context :: { [string]: unknown }).creator else nil
	if type(creator) ~= "table" then
		error("asset readback returned no creator", 0)
	end
	local group = numericId((creator :: { [string]: unknown }).groupId)
	if group ~= nil then
		return { type = "group", id = group }
	end
	local user = numericId((creator :: { [string]: unknown }).userId)
	if user ~= nil then
		return { type = "user", id = user }
	end
	error("asset readback returned no creator identity", 0)
end

local function attempt(options: Options, request: PublicationRequest): Published | PublishFault
	local grant = request.grant
	local previousVersion: string? = nil
	if grant.action == "update" then
		local prepared, issue = pcall(function()
			local prior = getDocument(options, assetUrl(options, grant.assetId :: string), "pre-update asset readback")
			local returnedId = numericId(prior.assetId)
			if returnedId ~= grant.assetId then
				error("pre-update readback returned another asset", 0)
			end
			previousVersion = text(prior.revisionId)
			if previousVersion == nil or string.match(previousVersion :: string, "^%d+$") == nil then
				error("pre-update readback returned no rollback version", 0)
			end
			local priorVersion = getDocument(
				options,
				versionUrl(options, grant.assetId :: string, previousVersion :: string),
				"pre-update version readback"
			)
			verifyVersionDocument(priorVersion, grant.assetId :: string, previousVersion :: string)
		end)
		if not prepared then
			return fault(REFUSED, "update rollback preflight failed before mutation: " .. tostring(issue))
		end
	end

	local formed, body, boundary = pcall(multipart, options, request)
	if not formed then
		return fault(REFUSED, "the publication body could not be formed before mutation: " .. tostring(body))
	end
	local url = if grant.action == "create"
		then base(options) .. "/assets"
		else base(options) .. "/assets/" .. (grant.assetId :: string) .. "?updateMask=description%2CdisplayName"
	local sent, answer = pcall(options.send, {
		method = (if grant.action == "create" then "POST" else "PATCH") :: "POST" | "PATCH",
		url = url,
		headers = {
			Accept = "application/json",
			["Content-Type"] = "multipart/form-data; boundary=" .. (boundary :: string),
		},
		body = body :: string,
	})
	if not sent then
		return fault(AMBIGUOUS, "the publication request did not resolve: " .. tostring(answer))
	end
	local response = answer :: Response
	if type(response) ~= "table" or type(response.status) ~= "number" then
		return fault(AMBIGUOUS, "the transport returned no response this adapter can read")
	end
	if response.status == 408 or response.status == 504 then
		return fault(TIMED_OUT, ("the platform did not answer in time (%d)"):format(response.status))
	end
	if response.status == 429 then
		return fault(REFUSED, "the platform throttled the one authorised mutation attempt")
	end
	if not response.ok then
		return fault(REFUSED, ("the platform refused the publication (%d)"):format(response.status))
	end
	local decoded = options.decode(response.body)
	if type(decoded) ~= "table" then
		return fault(AMBIGUOUS, "the platform answered with an operation body this adapter cannot read")
	end
	local okPoll, asset, operationPathValue, pollIssue =
		pcall(operationResult, options, decoded :: { [string]: unknown })
	if not okPoll then
		return fault(AMBIGUOUS, "operation polling did not resolve: " .. tostring(asset))
	end
	if asset == nil then
		local detail = tostring(pollIssue)
		if string.find(detail, "remained pending", 1, true) ~= nil then
			return fault(TIMED_OUT, detail)
		end
		return fault(PARTIAL, detail)
	end
	local durable = asset :: { [string]: unknown }
	local assetId = numericId(durable.assetId)
	local version = text(durable.revisionId)
	local operationId = string.match(operationPathValue :: string, "^operations/(.+)$")
	if assetId == nil or version == nil or operationId == nil then
		return fault(PARTIAL, "the completed operation returned no complete asset/version identity")
	end
	if grant.action == "update" and assetId ~= grant.assetId then
		return fault(PARTIAL, ("the completed operation returned asset %s outside the update grant"):format(assetId))
	end
	local rollbackToken = if grant.action == "create"
		then "archive:" .. assetId
		else "rollback:" .. assetId .. ":" .. (previousVersion :: string)
	local state = moderationState(durable)
	local outcome = moderationOutcome(state)
	if outcome == "rejected" then
		return fault(REFUSED, ("asset %s was rejected by moderation (%s)"):format(assetId, state))
	end
	if outcome ~= "approved" then
		local budget = options.moderationPollBudget or DEFAULT_MODERATION_POLL_BUDGET
		for ordinal = 1, budget do
			if options.waitBeforePoll ~= nil then
				options.waitBeforePoll(ordinal, "assets/" .. assetId)
			end
			local polledOk, polled = pcall(readAssetDocument, options, assetId, "moderation poll")
			if not polledOk then
				return fault(
					MODERATION_PENDING,
					("asset %s version %s remains ambiguous: the moderation poll did not resolve: %s; a created asset is never compensated on an unresolved poll"):format(
						assetId,
						version,
						tostring(polled)
					)
				)
			end
			state = moderationState(polled :: { [string]: unknown })
			outcome = moderationOutcome(state)
			if outcome == "approved" then
				break
			end
			if outcome == "rejected" then
				return fault(REFUSED, ("asset %s was rejected by moderation (%s)"):format(assetId, state))
			end
		end
		if outcome ~= "approved" then
			return fault(
				MODERATION_PENDING,
				("asset %s version %s remains %s after %d poll(s); Roblox resolves moderation independently and a reviewing asset is never compensated"):format(
					assetId,
					version,
					state,
					budget
				)
			)
		end
	end
	return {
		status = "published" :: "published",
		assetId = assetId,
		version = version,
		operationId = operationId,
		previousVersion = previousVersion,
		rollbackToken = rollbackToken,
	}
end

local function readback(options: Options, published: Published, request: PublicationRequest): Readback
	local body = getDocument(options, assetUrl(options, published.assetId), "published asset readback")
	local returnedId = numericId(body.assetId)
	local version = text(body.revisionId)
	local displayName = text(body.displayName)
	local description = text(body.description)
	local creator = creatorOf(body)
	local state = moderationState(body)
	if returnedId ~= published.assetId or version ~= published.version then
		error("published asset readback returned another asset or revision", 0)
	end
	if displayName == nil or description == nil then
		error("published asset readback returned incomplete public metadata", 0)
	end
	if request.grant.description == nil and description ~= request.grant.semanticId then
		error("published asset readback changed the legacy semantic description", 0)
	end
	if normalizedAssetType(body.assetType) ~= normalizedAssetType(request.grant.assetType) then
		error("published asset readback returned another asset type", 0)
	end
	if not APPROVED[state] then
		error("published asset readback is not approved: " .. state, 0)
	end
	local versionBody = getDocument(
		options,
		versionUrl(options, published.assetId, published.version),
		"published asset-version readback"
	)
	verifyVersionDocument(versionBody, published.assetId, published.version)
	local versionCreator = creatorOf(versionBody)
	if versionCreator.type ~= creator.type or versionCreator.id ~= creator.id then
		error("asset and asset-version readback disagree on creator", 0)
	end
	local metadata = table.clone(request.artifact.metadata)
	metadata.assetType = tostring(body.assetType)
	metadata.revisionId = published.version
	metadata.moderationState = state
	metadata.assetRecord = "authenticated"
	metadata.assetVersionRecord = "authenticated"
	metadata.contentDigestReadback = "unavailable-through-assets-api"
	metadata.privacyReadback = "unavailable-through-assets-api"
	metadata.displayName = displayName
	metadata.description = description
	return {
		artifact = {
			id = request.artifact.id,
			digest = request.artifact.digest,
			digestAlgorithm = "sha256" :: "sha256",
			mediaType = request.artifact.mediaType,
			byteCount = request.artifact.byteCount,
			locator = "roblox-asset:" .. published.assetId .. "/versions/" .. published.version,
			semanticId = request.grant.semanticId,
			metadata = metadata,
		},
		assetId = published.assetId,
		version = published.version,
		semanticId = request.grant.semanticId,
		displayName = displayName,
		description = description,

		target = request.grant.target,
		assetType = request.grant.assetType,
		creator = creator,

		visibility = request.grant.visibility,
	}
end

local function compensate(options: Options, token: string): Compensation
	if token == "" then
		return { status = "failed", detail = "no rollback token was recorded for this mutation" }
	end
	local archiveId = string.match(token, "^archive:(%d+)$")
	local rollbackId, rollbackVersion = string.match(token, "^rollback:(%d+):(%d+)$")
	if archiveId == nil and rollbackId == nil then
		return { status = "failed", detail = "the rollback token does not name a supported Open Cloud compensation" }
	end
	local request = if archiveId ~= nil
		then {
			method = "POST" :: "POST",
			url = base(options) .. "/assets/" .. archiveId .. ":archive",
			headers = { Accept = "application/json", ["Content-Type"] = "application/json" },
		}
		else {
			method = "POST" :: "POST",
			url = base(options) .. "/assets/" .. (rollbackId :: string) .. "/versions:rollback",
			headers = { Accept = "application/json", ["Content-Type"] = "application/json" },
			body = options.encode {
				assetVersion = "assets/" .. (rollbackId :: string) .. "/versions/" .. (rollbackVersion :: string),
			},
		}
	local sent, answer = pcall(options.send, request)
	if not sent then
		return { status = "failed", detail = "the compensation request did not resolve: " .. tostring(answer) }
	end
	local checked, response = pcall(decodedResponse, options, answer, "compensation")
	if not checked then
		return { status = "failed", detail = tostring(response) }
	end
	local document = response :: { [string]: unknown }
	if archiveId ~= nil then
		local state = text(document.state)
		if numericId(document.assetId) ~= archiveId or (state ~= "Archived" and state ~= "STATE_ARCHIVED") then
			return { status = "failed", detail = "archive response did not prove the asset became archived" }
		end
		return { status = "ok", detail = "the created asset was archived through the Assets API" }
	end
	local path = text(document.path)
	local newVersion = if path ~= nil
		then string.match(path, "^assets/" .. (rollbackId :: string) .. "/versions/(%d+)$")
		else nil
	if newVersion == nil then
		return { status = "failed", detail = "rollback response returned no resulting asset-version path" }
	end
	local observed, issue = pcall(function()
		local asset = getDocument(options, assetUrl(options, rollbackId :: string), "rollback asset readback")
		if numericId(asset.assetId) ~= rollbackId or text(asset.revisionId) ~= newVersion then
			error("rollback readback returned another asset or revision", 0)
		end
		local version = getDocument(
			options,
			versionUrl(options, rollbackId :: string, newVersion :: string),
			"rollback version readback"
		)
		verifyVersionDocument(version, rollbackId :: string, newVersion :: string)
	end)
	if not observed then
		return { status = "failed", detail = "rollback readback failed: " .. tostring(issue) }
	end
	return {
		status = "ok",
		detail = "the asset was rolled back to version " .. (rollbackVersion :: string) .. " through the Assets API",
	}
end

local function operations(options: Options): Adapter
	if options.toolVersion == "" then
		error("Generate Open Cloud operations require an exact adapter version", 2)
	end
	if type(options.maxPolls) ~= "number" or options.maxPolls < 1 or options.maxPolls % 1 ~= 0 then
		error("Generate Open Cloud operations require a positive integral poll budget", 2)
	end
	if
		options.moderationPollBudget ~= nil
		and (
			type(options.moderationPollBudget) ~= "number"
			or options.moderationPollBudget < 0
			or options.moderationPollBudget % 1 ~= 0
		)
	then
		error("Generate Open Cloud operations require a non-negative integral moderation poll budget", 2)
	end
	return {
		toolVersion = options.toolVersion,
		publish = function(request: PublicationRequest): Published | PublishFault
			return attempt(options, request)
		end,
		readback = function(published: Published, request: PublicationRequest): Readback
			return readback(options, published, request)
		end,
		compensate = function(token: string): Compensation
			return compensate(options, token)
		end,
	}
end

export type Stage = {
	id: string,
	grant: Grant,
	brief: Generate.Brief,
	artifacts: { Generate.Artifact },
}

export type Attempt = {
	ordinal: number,
	stageId: string,
	grantId: string,
	grantFingerprint: string,
	action: string,
	semanticId: string,
	state: string,
	assetId: string?,
	version: string?,
	operationId: string?,
	rollbackToken: string?,
	detail: string?,
}

export type CompensationRecord = {
	ordinal: number,
	stageId: string,
	token: string,
	status: string,
	detail: string,
}

export type Transaction = {
	disposition: string,
	terminal: boolean,
	retried: boolean,
	attemptsAuthorised: number,
	attemptsMade: number,
	attempts: { Attempt },
	compensations: { CompensationRecord },
	delivered: { [string]: unknown }?,
	detail: string?,
}

local PUBLISHED = "published"
local FAILED_READBACK = "failed-readback"
local FAILED_COMPENSATION = "failed-compensation"

local TERMINAL: { string } = {
	PUBLISHED,
	REFUSED,
	AMBIGUOUS,
	MODERATION_DELAYED,
	MODERATION_PENDING,
	TIMED_OUT,
	PARTIAL,
	FAILED_READBACK,
	FAILED_COMPENSATION,
}

local function classify(outcome: Generate.StageOutcome): (string, string?)
	if outcome.status == "returned" then
		return PUBLISHED, nil
	end
	local detail = outcome.detail
	if outcome.status == "rejected" then
		return REFUSED, detail
	end
	local named = dispositionOf(detail)
	if named ~= nil then
		return named, detail
	end
	if type(detail) == "string" then
		if string.find(detail, "readback", 1, true) ~= nil then
			return FAILED_READBACK, detail
		end
		if string.find(detail, "outside the grant", 1, true) ~= nil then
			return REFUSED, detail
		end
		if string.find(detail, "without complete identity", 1, true) ~= nil then
			return PARTIAL, detail
		end
	end
	return AMBIGUOUS, detail
end

local function assetIdFromToken(token: string?): string?
	if token == nil then
		return nil
	end
	local archiveId = string.match(token, "^archive:(%d+)$")
	if archiveId ~= nil then
		return archiveId
	end
	return string.match(token, "^rollback:(%d+):%d+$")
end

local function transaction(adapter: Adapter, stages: { Stage }, fingerprint: (value: unknown) -> string): Transaction
	if #stages == 0 then
		error("Generate Open Cloud transaction requires at least one granted stage", 2)
	end
	local attempts: { Attempt } = {}
	local compensations: { CompensationRecord } = {}
	local disposition, detail = PUBLISHED, nil :: string?
	local delivered: { [string]: unknown }? = nil

	for ordinal, stage in stages do
		local outcome = publish(adapter, stage.brief, stage.artifacts, stage.grant, stage.grant.idempotencyKey)
		local named, faultDetail = classify(outcome)
		local metadata: { [string]: unknown } = if outcome.status == "returned"
			then (outcome.output.metadata or {}) :: { [string]: unknown }
			else {}
		local rollbackToken: string? = if outcome.status == "returned"
			then outcome.output.rollbackToken
			else outcome.rollbackToken
		local detailAssetId, detailVersion = string.match(faultDetail or "", "asset (%d+) version (%d+)")
		if detailAssetId == nil then
			detailAssetId = string.match(faultDetail or "", "asset (%d+)")
		end
		attempts[ordinal] = {
			ordinal = ordinal,
			stageId = stage.id,
			grantId = stage.grant.id,
			grantFingerprint = fingerprint(stage.grant),
			action = stage.grant.action,
			semanticId = stage.grant.semanticId,
			state = named,
			assetId = (metadata.assetId :: string?) or detailAssetId or assetIdFromToken(rollbackToken),
			version = (metadata.version :: string?) or detailVersion,
			operationId = metadata.operationId :: string?,
			rollbackToken = rollbackToken,
			detail = faultDetail,
		}
		if named ~= PUBLISHED then
			disposition, detail = named, faultDetail
			break
		end
		delivered = metadata
	end

	if disposition ~= PUBLISHED then
		local ordinal = 0
		for index = #attempts, 1, -1 do
			local token = attempts[index].rollbackToken
			if token == nil then
				continue
			end
			ordinal += 1
			local result = adapter.compensate(token)
			compensations[ordinal] = {
				ordinal = ordinal,
				stageId = attempts[index].stageId,
				token = token,
				status = result.status,
				detail = result.detail,
			}
			if result.status ~= "ok" then
				disposition = FAILED_COMPENSATION
			end
		end
	end

	return {
		disposition = disposition,
		terminal = true,
		retried = false,
		attemptsAuthorised = #stages,
		attemptsMade = #attempts,
		attempts = attempts,
		compensations = compensations,
		delivered = if disposition == PUBLISHED then delivered else nil,
		detail = detail,
	}
end

return {
	DISPOSITIONS = TERMINAL,
	grant = grant,
	publish = publish,
	operations = operations,
	transaction = transaction,
	classify = classify,
}
