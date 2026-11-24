--!strict

local AssetReadback = require "./asset-readback"
local PermissionRequest = require "./permission-request"
local Wire = require "./wire"
local field = Wire.field

export type SendAuthorized = Wire.SendAuthorized
export type Decode = Wire.Decode
export type Encode = Wire.Encode
type Response = Wire.Response
export type Owner = AssetReadback.Owner
export type Record = AssetReadback.Record

export type AuthorityOptions = {
	send: SendAuthorized,
	decode: Decode,
	baseUrl: string?,
	maxMembershipPages: number?,
	maxRolePages: number?,
	allowedVisibilities: { string }?,
}

export type Credential = {
	decision: string,
	operation: string?,
	nonce: string?,
	freezeCommit: string?,
	authorizedUserId: number,
	permissionOperations: { string },
}

export type AssignedRole = { path: string, id: string, name: string, rank: number }
type Role = { path: string, id: string, displayName: string, rank: number }
type Membership = { path: string, user: string, roles: unknown }

export type AuthorityReceipt = {
	contract: string,
	authorizedUserId: number,
	universeId: string,
	universeCreatorType: string,
	universeCreatorId: string,
	groupId: string,
	membershipPath: string?,
	membership: string,
	assignedRoles: { AssignedRole },
	credentialDecision: string,
	credentialOperation: string?,
	credentialNonce: string?,
	credentialFreezeCommit: string?,
	credentialPermissionOperations: { string }?,
	decision: string,
	boundary: string,
}

export type Patch = {
	attempted: boolean,
	status: number?,
	successAssetIds: { string },
	complete: boolean,
	diagnostic: string,
	responseBody: string,
}

export type ChunkOutcome = {
	index: number,
	attempt: number,
	assetIds: { string },
	status: string,
	patch: Patch,
	writeAheadPath: string,
	writeAheadSha256: string,
}
export type ReceiptPatch = {
	attempted: boolean,
	status: number?,
	successAssetIds: { string },
	complete: boolean?,
	diagnostic: string?,
	responseBody: string,
}
local AUTHORITY_CONTRACT = "generate.roblox.permission-grant.subject-authority.v1"
local CREDENTIAL_DECISION = "CREDENTIAL_SCOPE_BOUND"
local REQUIRED_PERMISSION_OPERATION = "write"
local MEMBERSHIP_ABSENT = "required group membership is absent"
local SCOPES_UNCOVERED = "credential scopes do not cover the asset permission operation"
local BOUND = "SUBJECT_AUTHORITY_BOUND"
local REFUSED = "SUBJECT_AUTHORITY_REFUSED"
local DEFAULT_BASE_URL = "https://apis.roblox.com/cloud/v2"
local DEFAULT_MEMBERSHIP_PAGES = 4
local DEFAULT_ROLE_PAGES = 10
local AUTHORITY_BOUNDARY = "Cloud v2 membership roles and group roles are recorded as facts; "
	.. "the consumer-held, scope-verified key remains the authority"

local function positiveInteger(value: unknown): boolean
	return type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value)
end

local function nonnegativeRank(value: unknown): boolean
	return type(value) == "number" and value >= 0 and value <= 255 and value == math.floor(value)
end

local function decodeAnswer(
	options: AuthorityOptions,
	response: Response,
	label: string
): ({ [string]: unknown }?, string)
	if not response.ok or response.status ~= 200 then
		return nil, label .. " read failed with HTTP " .. tostring(response.status)
	end
	local ok, value = pcall(options.decode, response.body)
	if not ok or type(value) ~= "table" then
		return nil, label .. " read returned malformed JSON"
	end
	local out: { [string]: unknown } = {}
	for key, item in value do
		if type(key) == "string" then
			out[key] = item
		end
	end
	return out, ""
end

local function encodeComponent(value: string): string
	return (
		string.gsub(value, "[^%w%-%._~]", function(character: string): string
			return ("%%%02X"):format(string.byte(character))
		end)
	)
end

local function universeUrl(universeId: string, baseUrl: string?): string
	return (baseUrl or DEFAULT_BASE_URL) .. "/universes/" .. universeId
end

local function membershipUrl(groupId: string, userId: number, pageToken: string?, baseUrl: string?): string
	local filter = "user == 'users/" .. string.format("%.0f", userId) .. "'"
	local url = (baseUrl or DEFAULT_BASE_URL)
		.. "/groups/"
		.. groupId
		.. "/memberships?maxPageSize=100&filter="
		.. encodeComponent(filter)
	return if pageToken == nil then url else url .. "&pageToken=" .. encodeComponent(pageToken)
end

local function rolesUrl(groupId: string, pageToken: string?, baseUrl: string?): string
	local url = (baseUrl or DEFAULT_BASE_URL) .. "/groups/" .. groupId .. "/roles?maxPageSize=20"
	return if pageToken == nil then url else url .. "&pageToken=" .. encodeComponent(pageToken)
end

local function authorizedGet(options: AuthorityOptions, url: string): Response
	return options.send { method = "GET", url = url, headers = { Accept = "application/json" } }
end

local function nextToken(value: { [string]: unknown }): (string?, string?)
	local token = value.nextPageToken
	if token == nil or token == "" then
		return nil, nil
	end
	if type(token) ~= "string" or #token > 1024 then
		return nil, "pagination token is malformed"
	end
	return token, nil
end

local function listMemberships(options: AuthorityOptions, userId: number, groupId: string): (Membership?, string)
	local maxPages = options.maxMembershipPages or DEFAULT_MEMBERSHIP_PAGES
	local found: Membership? = nil
	local token: string? = nil
	local spent: { [string]: boolean } = {}
	for page = 1, maxPages do
		local value, reason = decodeAnswer(
			options,
			authorizedGet(options, membershipUrl(groupId, userId, token, options.baseUrl)),
			"group membership"
		)
		if value == nil then
			return nil, reason
		end
		local rows = value.groupMemberships
		if type(rows) ~= "table" then
			return nil, "group membership read returned malformed JSON"
		end
		for _, candidate in rows do
			local row = candidate
			if type(row) ~= "table" then
				return nil, "group membership row is malformed"
			end
			local user, membershipPath = field(row, "user"), field(row, "path")
			if type(user) == "string" and user == "users/" .. string.format("%.0f", userId) then
				if
					type(membershipPath) ~= "string"
					or string.match(membershipPath, "^groups/" .. groupId .. "/memberships/[%w._%-]+$") == nil
					or found ~= nil
				then
					return nil, "group membership identity is ambiguous"
				end
				found = { path = membershipPath, user = user, roles = field(row, "roles") }
			elseif type(user) ~= "string" then
				return nil, "group membership user is malformed"
			else
				return nil, "group membership filter returned another user"
			end
		end
		local nextPage, tokenReason = nextToken(value)
		if tokenReason ~= nil then
			return nil, tokenReason
		end
		if nextPage == nil then
			return found, if found == nil then MEMBERSHIP_ABSENT else ""
		end
		if spent[nextPage] or page == maxPages then
			return nil, "group membership pagination is ambiguous"
		end
		spent[nextPage] = true
		token = nextPage
	end
	return nil, "group membership pagination is ambiguous"
end

local function assignedRolePaths(membership: Membership, groupId: string): ({ string }?, string)
	local roles = membership.roles
	if type(roles) ~= "table" or #roles == 0 then
		return nil, "group membership returned no complete roles collection"
	end
	local paths: { string } = {}
	local seen: { [string]: boolean } = {}
	for index, path in roles do
		if
			type(index) ~= "number"
			or index ~= #paths + 1
			or type(path) ~= "string"
			or string.match(path, "^groups/" .. groupId .. "/roles/[%w._%-]+$") == nil
			or seen[path]
		then
			return nil, "group membership roles are malformed"
		end
		seen[path] = true
		table.insert(paths, path)
	end
	table.sort(paths)
	return paths, ""
end

local function listRoles(options: AuthorityOptions, groupId: string): ({ [string]: Role }?, string)
	local maxPages = options.maxRolePages or DEFAULT_ROLE_PAGES
	local roles: { [string]: Role } = {}
	local token: string? = nil
	local spent: { [string]: boolean } = {}
	for page = 1, maxPages do
		local value, reason =
			decodeAnswer(options, authorizedGet(options, rolesUrl(groupId, token, options.baseUrl)), "group roles")
		if value == nil then
			return nil, reason
		end
		local rows = value.groupRoles
		if type(rows) ~= "table" then
			return nil, "group roles read returned malformed JSON"
		end
		for _, candidate in rows do
			local pathValue, id = field(candidate, "path"), field(candidate, "id")
			local displayName, rank = field(candidate, "displayName"), field(candidate, "rank")
			if
				type(pathValue) ~= "string"
				or string.match(pathValue, "^groups/" .. groupId .. "/roles/[%w._%-]+$") == nil
				or type(id) ~= "string"
				or id == ""
				or pathValue ~= "groups/" .. groupId .. "/roles/" .. id
				or type(displayName) ~= "string"
				or displayName == ""
				or type(rank) ~= "number"
				or not nonnegativeRank(rank)
				or roles[pathValue] ~= nil
			then
				return nil, "group role evidence is malformed or duplicated"
			end
			roles[pathValue] = { path = pathValue, id = id, displayName = displayName, rank = rank }
		end
		local nextPage, tokenReason = nextToken(value)
		if tokenReason ~= nil then
			return nil, tokenReason
		end
		if nextPage == nil then
			return roles, ""
		end
		if spent[nextPage] or page == maxPages then
			return nil, "group role pagination is ambiguous"
		end
		spent[nextPage] = true
		token = nextPage
	end
	return nil, "group role pagination is ambiguous"
end

local function operationCovered(value: unknown): { string }?
	local declared = field(value, "permissionOperations")
	if field(value, "decision") ~= CREDENTIAL_DECISION or type(declared) ~= "table" then
		return nil
	end
	local operations: { string } = {}
	local seen: { [string]: boolean } = {}
	for index, operation in declared do
		if type(index) ~= "number" or index ~= #operations + 1 or type(operation) ~= "string" or seen[operation] then
			return nil
		end
		seen[operation] = true
		table.insert(operations, operation)
	end
	if not seen[REQUIRED_PERMISSION_OPERATION] then
		return nil
	end
	return operations
end

local function subjectAuthority(
	options: AuthorityOptions,
	credentialValue: unknown,
	universeId: string,
	groupId: string
): (AuthorityReceipt?, string)
	local authorizedUserId = field(credentialValue, "authorizedUserId")
	if
		type(options) ~= "table"
		or type(options.send) ~= "function"
		or type(options.decode) ~= "function"
		or type(authorizedUserId) ~= "number"
		or not positiveInteger(authorizedUserId)
		or string.match(universeId, "^[1-9][0-9]*$") == nil
		or string.match(groupId, "^[1-9][0-9]*$") == nil
	then
		return nil, "subject authority input is malformed"
	end
	local credentialDecision = field(credentialValue, "decision")
	local operation, nonce, freezeCommit =
		field(credentialValue, "operation"), field(credentialValue, "nonce"), field(credentialValue, "freezeCommit")
	if
		type(credentialDecision) ~= "string"
		or (operation ~= nil and type(operation) ~= "string")
		or (nonce ~= nil and type(nonce) ~= "string")
		or (freezeCommit ~= nil and type(freezeCommit) ~= "string")
	then
		return nil, "subject authority input is malformed"
	end
	local function receiptFor(
		membershipPath: string?,
		observed: { AssignedRole },
		operations: { string }?,
		decision: string
	): AuthorityReceipt
		return {
			contract = AUTHORITY_CONTRACT,
			authorizedUserId = authorizedUserId,
			universeId = universeId,
			universeCreatorType = "Group",
			universeCreatorId = groupId,
			groupId = groupId,
			membershipPath = membershipPath,
			membership = if membershipPath == nil then "ABSENT" else "CURRENT",
			assignedRoles = observed,
			credentialDecision = credentialDecision,
			credentialOperation = operation,
			credentialNonce = nonce,
			credentialFreezeCommit = freezeCommit,
			credentialPermissionOperations = operations,
			decision = decision,
			boundary = AUTHORITY_BOUNDARY,
		}
	end

	local operations = operationCovered(credentialValue)
	if operations == nil then
		return receiptFor(nil, {}, nil, REFUSED), SCOPES_UNCOVERED
	end

	local universeValue, universeReason =
		decodeAnswer(options, authorizedGet(options, universeUrl(universeId, options.baseUrl)), "universe ownership")
	if universeValue == nil then
		return nil, universeReason
	end
	local universe = universeValue
	if
		universe.path ~= "universes/" .. universeId
		or universe.group ~= "groups/" .. groupId
		or universe.user ~= nil
		or type(universe.visibility) ~= "string"
		or not table.find(options.allowedVisibilities or { "PRIVATE" }, universe.visibility)
	then
		return nil, "universe ownership is not the required group"
	end

	local membership, membershipReason = listMemberships(options, authorizedUserId, groupId)
	if membership == nil then
		if membershipReason == MEMBERSHIP_ABSENT then
			return receiptFor(nil, {}, operations, REFUSED), MEMBERSHIP_ABSENT
		end
		return nil, membershipReason
	end
	local assigned, assignedReason = assignedRolePaths(membership, groupId)
	if assigned == nil then
		return nil, assignedReason
	end
	local roles, rolesReason = listRoles(options, groupId)
	if roles == nil then
		return nil, rolesReason
	end
	local observed: { AssignedRole } = {}
	for _, path in assigned do
		local role = roles[path]
		if role == nil then
			return nil, "assigned group role is absent from the authoritative role collection"
		end
		table.insert(observed, { path = path, id = role.id, name = role.displayName, rank = role.rank })
	end
	return receiptFor(membership.path, observed, operations, BOUND), "bound"
end

return {
	CREDENTIAL_DECISION = CREDENTIAL_DECISION,
	DECISIONS = { bound = BOUND, refused = REFUSED },
	REASONS = { membershipAbsent = MEMBERSHIP_ABSENT, scopesUncovered = SCOPES_UNCOVERED },
	ENDPOINT = PermissionRequest.ENDPOINT,
	MAX_ASSETS_PER_REQUEST = PermissionRequest.MAX_ASSETS_PER_REQUEST,
	subjectAuthority = subjectAuthority,
	chunks = PermissionRequest.chunks,
	prepare = PermissionRequest.prepare,
	attempt = PermissionRequest.attempt,
}
