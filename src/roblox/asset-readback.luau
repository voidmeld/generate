--!strict

local Wire = require "./wire"

export type SendAuthorized = Wire.SendAuthorized
export type Decode = Wire.Decode
local field = Wire.field

export type Owner = {
	creatorType: "Group" | "User",
	creatorId: string,
}

export type Options = {
	send: SendAuthorized,
	decode: Decode,
	owner: Owner,
	sendPublic: SendAuthorized?,
	sleep: ((seconds: number) -> ())?,
	clock: (() -> number)?,
	paced: boolean?,
	baseUrl: string?,
	detailsBaseUrl: string?,
	maxRetries: number?,
	minIntervalSeconds: number?,
}

export type Record = {
	assetId: string,
	path: string,
	assetType: string,
	displayName: string,
	creatorType: string,
	creatorId: string,
	ownedByDeclaredCreator: boolean,
	foreignOwnershipPossible: boolean,
	moderationState: string,
	state: string,
	privacy: string,
	revisionId: string,
	status: number,
	diagnostic: string,
	source: string,
}

export type Census = {
	contract: string,
	rootAssetId: string,
	root: Record,
	dependencies: { Record },
	dependencyCount: number,
	ownedCount: number,
	foreignOwned: { string },
	moderationNotApproved: { string },
	foreignOwnershipPossible: boolean,
	unresolved: { string },
	privacyObservable: boolean,
	closed: boolean,
	boundary: { string },
}

local CONTRACT = "generate.roblox.asset-readback.v1"
local DEFAULT_BASE_URL = "https://apis.roblox.com/assets/v1/assets"
local DEFAULT_DETAILS_BASE_URL = "https://economy.roblox.com/v2/assets"
local RECORD_SOURCE = "asset-record"
local DETAILS_SOURCE = "public-asset-details"
local PRIVACY_UNOBSERVABLE = "unobservable-through-the-read-only-asset-record"
local MODERATION_UNOBSERVABLE = "unobservable-through-the-public-asset-details"
local DEFAULT_RETRIES = 5
local DEFAULT_MIN_INTERVAL_SECONDS = 0.55
local RETRY_BASE_SECONDS = 1
local MAX_RESET_SECONDS = 60

local APPROVED_STATES: { [string]: boolean } = { Active = true, Approved = true }
local THROTTLED_STATUSES: { [number]: boolean } = { [429] = true, [503] = true }

local ASSET_TYPE_NAMES: { [number]: string } = {
	[1] = "Image",
	[3] = "Audio",
	[4] = "Mesh",
	[10] = "Model",
	[13] = "Decal",
	[40] = "MeshPart",
}

local BOUNDARY: { string } = {
	"every request this module makes is a GET against a read-only asset record",
	"the only other endpoint is the public asset details read used when the record refuses a raw mesh or image",
	"an unparsed field is reported as unknown and is never defaulted to a passing value",
	"privacy is not carried by either record so it is reported unobservable and never asserted",
	"the dependency census reads exactly the ids it was handed and never discovers more",
	"a readback proves ownership and state and authorizes no mutation of either",
}

local paceValues: { [Options]: number } = {}
local paceState = setmetatable(paceValues, { __mode = "k" })

local function validOwner(owner: unknown): boolean
	local creatorType, creatorId = field(owner, "creatorType"), field(owner, "creatorId")
	return (creatorType == "Group" or creatorType == "User")
		and type(creatorId) == "string"
		and string.match(creatorId, "^[1-9][0-9]*$") ~= nil
end

local function requireOptions(options: Options)
	if type(options) ~= "table" or type(options.send) ~= "function" or type(options.decode) ~= "function" then
		error("Generate asset readback requires an authorized transport and a JSON decoder", 3)
	end
	if not validOwner(options.owner) then
		error("Generate asset readback requires a declared Group or User creator identity", 3)
	end
end

local function assetRecordUrl(assetId: string, baseUrl: string?): string
	return (baseUrl or DEFAULT_BASE_URL) .. "/" .. assetId
end

local function publicDetailsUrl(assetId: string, baseUrl: string?): string
	return (baseUrl or DEFAULT_DETAILS_BASE_URL) .. "/" .. assetId .. "/details"
end

local function normalizedId(value: unknown): string
	return Wire.numericId(value) or ""
end

local function creatorOf(document: unknown): (string, string)
	local creator = field(field(document, "creationContext"), "creator")
	if type(creator) ~= "table" then
		creator = field(document, "creator")
	end
	local groupId = normalizedId(field(creator, "groupId"))
	if groupId ~= "" then
		return "Group", groupId
	end
	local userId = normalizedId(field(creator, "userId"))
	if userId ~= "" then
		return "User", userId
	end
	return "unknown", ""
end

local function unknownRecord(assetId: string, status: number, diagnostic: string): Record
	return {
		assetId = assetId,
		path = "",
		assetType = "unknown",
		displayName = "",
		creatorType = "unknown",
		creatorId = "",
		ownedByDeclaredCreator = false,
		foreignOwnershipPossible = true,
		moderationState = "unknown",
		state = "unknown",
		privacy = PRIVACY_UNOBSERVABLE,
		revisionId = "",
		status = status,
		diagnostic = diagnostic,
		source = RECORD_SOURCE,
	}
end

local function text(value: unknown, fallback: string): string
	return if type(value) == "string" then value else fallback
end

local function parse(options: Options, assetId: string, status: number, body: string): Record
	if status ~= 200 then
		return unknownRecord(assetId, status, ("the asset record answered HTTP %d"):format(status))
	end
	local ok, document = pcall(options.decode, body)
	if not ok or type(document) ~= "table" then
		return unknownRecord(assetId, status, "the asset record is not deserializable JSON")
	end
	local creatorType, creatorId = creatorOf(document)
	local owned = creatorType == options.owner.creatorType and creatorId == options.owner.creatorId
	local moderationState = text(field(field(document, "moderationResult"), "moderationState"), "unknown")
	local returned = normalizedId(field(document, "assetId"))
	local record: Record = {
		assetId = if returned == "" then assetId else returned,
		path = text(field(document, "path"), ""),
		assetType = text(field(document, "assetType"), "unknown"),
		displayName = text(field(document, "displayName"), ""),
		creatorType = creatorType,
		creatorId = creatorId,
		ownedByDeclaredCreator = owned,
		foreignOwnershipPossible = not owned,
		moderationState = moderationState,
		state = text(field(document, "state"), "unknown"),
		privacy = PRIVACY_UNOBSERVABLE,
		revisionId = text(field(document, "revisionId"), ""),
		status = status,
		diagnostic = "",
		source = RECORD_SOURCE,
	}
	if returned ~= "" and returned ~= assetId then
		record.diagnostic = ("the record answered for %s rather than %s"):format(returned, assetId)
	end
	return record
end

local function parseDetails(options: Options, assetId: string, refused: Record, status: number, body: string): Record
	if status ~= 200 then
		return refused
	end
	local ok, document = pcall(options.decode, body)
	if not ok or type(document) ~= "table" then
		return refused
	end
	if normalizedId(field(document, "AssetId")) ~= assetId then
		return refused
	end
	local creator = field(document, "Creator")
	if type(creator) ~= "table" then
		return refused
	end
	local creatorTypeValue = field(creator, "CreatorType")
	local creatorType = if creatorTypeValue == "Group"
		then "Group"
		elseif creatorTypeValue == "User" then "User"
		else "unknown"
	local creatorId = normalizedId(field(creator, "CreatorTargetId"))
	if creatorType == "unknown" or creatorId == "" then
		return refused
	end
	local owned = creatorType == options.owner.creatorType and creatorId == options.owner.creatorId
	local declaredType = field(document, "AssetTypeId")
	local typeId = if type(declaredType) == "number" then declaredType else -1
	return {
		assetId = assetId,
		path = "",
		assetType = ASSET_TYPE_NAMES[typeId] or ("AssetTypeId:" .. tostring(typeId)),
		displayName = text(field(document, "Name"), ""),
		creatorType = creatorType,
		creatorId = creatorId,
		ownedByDeclaredCreator = owned,
		foreignOwnershipPossible = not owned,
		moderationState = MODERATION_UNOBSERVABLE,
		state = "Active",
		privacy = PRIVACY_UNOBSERVABLE,
		revisionId = "",
		status = 200,
		diagnostic = "",
		source = DETAILS_SOURCE,
	}
end

local function resetSeconds(headers: unknown): number?
	if type(headers) ~= "table" then
		return nil
	end
	for name, value in headers do
		if type(name) == "string" and string.lower(name) == "x-ratelimit-reset" then
			local seconds = if type(value) == "string" or type(value) == "number" then tonumber(value) else nil
			if seconds ~= nil and seconds > 0 then
				return math.min(seconds, MAX_RESET_SECONDS)
			end
		end
	end
	return nil
end

local function pace(options: Options, sleep: (seconds: number) -> ())
	local clock = options.clock
	if clock == nil then
		return
	end
	local interval = options.minIntervalSeconds or DEFAULT_MIN_INTERVAL_SECONDS
	local now = clock()
	local last = paceState[options]
	if last ~= nil then
		local wait = interval - (now - last)
		if wait > 0 then
			sleep(wait)
			now = clock()
		end
	end
	paceState[options] = now
end

local function readback(options: Options, assetId: string): Record
	requireOptions(options)
	local id = normalizedId(assetId)
	if id == "" then
		return unknownRecord(tostring(assetId), 0, "the asset id is not a positive integer")
	end
	local sleep = options.sleep or function(_seconds: number) end
	local retries = options.maxRetries or DEFAULT_RETRIES
	local attempt = 0
	while true do
		attempt += 1
		if options.paced == true then
			pace(options, sleep)
		end
		local request: Wire.AuthorizedRequest = {
			method = "GET",
			url = assetRecordUrl(id, options.baseUrl),
			headers = { Accept = "application/json" },
		}
		local ok, response = pcall(options.send, request)
		if not ok then
			return unknownRecord(id, 0, "the read failed: " .. string.sub(tostring(response), 1, 500))
		end
		if THROTTLED_STATUSES[response.status] ~= true or attempt > retries then
			local record = parse(options, id, response.status, response.body)
			local sendPublic = options.sendPublic
			if response.status ~= 403 or sendPublic == nil then
				return record
			end
			local detailsRequest: Wire.AuthorizedRequest = {
				method = "GET",
				url = publicDetailsUrl(id, options.detailsBaseUrl),
				headers = { Accept = "application/json" },
			}
			local detailsOk, details = pcall(sendPublic, detailsRequest)
			if not detailsOk then
				return record
			end
			return parseDetails(options, id, record, details.status, details.body)
		end
		sleep(resetSeconds(field(response, "headers")) or RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
	end
end

local function census(options: Options, rootAssetId: string, dependencyAssetIds: { string }): Census
	requireOptions(options)
	local root = readback(options, rootAssetId)
	local dependencies: { Record } = {}
	local foreignOwned: { string } = {}
	local moderationNotApproved: { string } = {}
	local unresolved: { string } = {}
	local ownedCount = 0
	local foreignPossible = false

	local function account(record: Record)
		if record.diagnostic ~= "" then
			table.insert(unresolved, record.assetId .. ": " .. record.diagnostic)
		end
		if record.ownedByDeclaredCreator then
			ownedCount += 1
		else
			table.insert(foreignOwned, record.assetId .. ": " .. record.creatorType .. " " .. record.creatorId)
			foreignPossible = true
		end
		if APPROVED_STATES[record.moderationState] ~= true and record.moderationState ~= MODERATION_UNOBSERVABLE then
			table.insert(moderationNotApproved, record.assetId .. ": " .. record.moderationState)
		end
	end

	account(root)
	local seen: { [string]: boolean } = { [root.assetId] = true }
	for _, dependencyId in dependencyAssetIds do
		local id = normalizedId(dependencyId)
		if id ~= "" and not seen[id] then
			seen[id] = true
			local record = readback(options, id)
			table.insert(dependencies, record)
			account(record)
		end
	end

	return {
		contract = CONTRACT,
		rootAssetId = root.assetId,
		root = root,
		dependencies = dependencies,
		dependencyCount = #dependencies,
		ownedCount = ownedCount,
		foreignOwned = foreignOwned,
		moderationNotApproved = moderationNotApproved,
		foreignOwnershipPossible = foreignPossible,
		unresolved = unresolved,
		privacyObservable = false,
		closed = #foreignOwned == 0 and #moderationNotApproved == 0 and #unresolved == 0,
		boundary = BOUNDARY,
	}
end

return {
	SOURCES = { record = RECORD_SOURCE, details = DETAILS_SOURCE },
	UNOBSERVABLE = { privacy = PRIVACY_UNOBSERVABLE, moderation = MODERATION_UNOBSERVABLE },
	APPROVED_STATES = APPROVED_STATES,
	readback = readback,
	census = census,
}
