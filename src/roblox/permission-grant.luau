--!strict

local AssetReadback = require "./asset-readback"
local PermissionRequest = require "./permission-request"
local Wire = require "./wire"

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

export type Partition = {
	contract: string,
	candidateReadbacks: { Record },
	grantAssetIds: { string },
	externalAssetIds: { string },
	externalReadbacks: { Record },
	unresolved: { string },
	foreignOwned: { string },
	closed: boolean,
}

export type ReceiptStore = {
	read: (path: string) -> string?,
	write: (path: string, bytes: string) -> (),
	list: (root: string) -> { string },
	ensure: (root: string) -> (),
}

export type Prepared = {
	endpoint: string,
	method: string,
	body: string,
	headerNames: { string },
	requestedAssetIds: { string },
}

export type AttemptResult = {
	status: number?,
	successAssetIds: { string }?,
	complete: boolean?,
	diagnostic: string?,
	responseBody: string?,
}

export type Patch = {
	attempted: boolean,
	status: number?,
	successAssetIds: { string },
	complete: boolean,
	diagnostic: string,
	responseBody: string,
}

export type Destination = {
	endpoint: string,
	method: string,
	headerNames: { string },
}

export type Terminal = {
	status: string,
	reason: string,
	message: string,
}

export type Chunk = { index: number, count: number, assetIds: { string }, attempt: number }
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
export type Receipt = {
	[string]: unknown,
	contract: string?,
	status: string?,
	reason: string?,
	universeId: string?,
	creatorType: string?,
	creatorId: string?,
	sourceCommit: string?,
	closureSha256: string?,
	grantAssetIds: { string }?,
	grantSetSha256: string?,
	chunkSize: number?,
	patch: ReceiptPatch?,
	chunk: Chunk?,
	chunkOutcome: ChunkOutcome?,
	chunkOutcomes: { ChunkOutcome }?,
	terminalPath: string?,
	outboundDestination: Destination?,
	outboundRequest: { endpoint: string, method: string, headerNames: { string }, bodySha256: string }?,
}

export type Transaction = {
	store: ReceiptStore,
	encode: Encode,
	decode: Decode,
	digest: (bytes: string) -> string,
	contract: string,
	outputRoot: string,
	universeId: string,
	owner: Owner,
	sourceCommit: string,
	closureSha256: string,
	grantAssetIds: { string },
	chunkSize: number,
	context: { [string]: unknown },
	destination: Destination,
	terminal: Terminal,
	prepare: (universeId: string, assetIds: { string }) -> Prepared,
	attempt: (prepared: Prepared) -> AttemptResult,
	priorTerminalPaths: { string }?,
}

local AUTHORITY_CONTRACT = "generate.roblox.permission-grant.subject-authority.v1"
local PARTITION_CONTRACT = "generate.roblox.permission-grant.census.v1"
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
	return type(value) == "number"
		and (value :: number) > 0
		and (value :: number) < math.huge
		and (value :: number) == math.floor(value :: number)
end

local function nonnegativeRank(value: unknown): boolean
	return type(value) == "number"
		and (value :: number) >= 0
		and (value :: number) <= 255
		and (value :: number) == math.floor(value :: number)
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
	return value :: { [string]: unknown }, ""
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
	return options.send { method = "GET" :: "GET", url = url, headers = { Accept = "application/json" } }
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
		for _, candidate in rows :: { unknown } do
			local row = candidate :: { [string]: unknown }
			if type(row) ~= "table" then
				return nil, "group membership row is malformed"
			end
			if row.user == "users/" .. string.format("%.0f", userId) then
				if
					type(row.path) ~= "string"
					or string.match(row.path, "^groups/" .. groupId .. "/memberships/[%w._%-]+$") == nil
					or found ~= nil
				then
					return nil, "group membership identity is ambiguous"
				end
				found = candidate :: Membership
			elseif type(row.user) ~= "string" then
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
	if type(membership.roles) ~= "table" or #(membership.roles :: { unknown }) == 0 then
		return nil, "group membership returned no complete roles collection"
	end
	local paths: { string } = {}
	local seen: { [string]: boolean } = {}
	for index, path in membership.roles :: { [unknown]: unknown } do
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
		for _, candidate in rows :: { unknown } do
			local role = candidate :: { [string]: unknown }
			if
				type(role) ~= "table"
				or type(role.path) ~= "string"
				or string.match(role.path, "^groups/" .. groupId .. "/roles/[%w._%-]+$") == nil
				or type(role.id) ~= "string"
				or role.id == ""
				or role.path ~= "groups/" .. groupId .. "/roles/" .. role.id
				or type(role.displayName) ~= "string"
				or role.displayName == ""
				or not nonnegativeRank(role.rank)
				or roles[role.path] ~= nil
			then
				return nil, "group role evidence is malformed or duplicated"
			end
			roles[role.path :: string] = candidate :: Role
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
	if
		type(value) ~= "table"
		or (value :: { [string]: unknown }).decision ~= CREDENTIAL_DECISION
		or type((value :: { [string]: unknown }).permissionOperations) ~= "table"
	then
		return nil
	end
	local credential = value :: { [string]: unknown }
	local operations: { string } = {}
	local seen: { [string]: boolean } = {}
	for index, operation in credential.permissionOperations :: { [unknown]: unknown } do
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
	local authorizedUserId = if type(credentialValue) == "table"
		then (credentialValue :: { [string]: unknown }).authorizedUserId
		else nil
	if
		type(options) ~= "table"
		or type(options.send) ~= "function"
		or type(options.decode) ~= "function"
		or not positiveInteger(authorizedUserId)
		or string.match(universeId, "^[1-9][0-9]*$") == nil
		or string.match(groupId, "^[1-9][0-9]*$") == nil
	then
		return nil, "subject authority input is malformed"
	end

	local rawCredential = credentialValue :: { [string]: unknown }
	if type(rawCredential.decision) ~= "string" then
		return nil, "subject authority input is malformed"
	end
	for _, name in { "operation", "nonce", "freezeCommit" } do
		if rawCredential[name] ~= nil and type(rawCredential[name]) ~= "string" then
			return nil, "subject authority input is malformed"
		end
	end
	local credential =
		credentialValue :: { decision: string, operation: string?, nonce: string?, freezeCommit: string? }
	local function receiptFor(
		membershipPath: string?,
		observed: { AssignedRole },
		operations: { string }?,
		decision: string
	): AuthorityReceipt
		return {
			contract = AUTHORITY_CONTRACT,
			authorizedUserId = authorizedUserId :: number,
			universeId = universeId,
			universeCreatorType = "Group",
			universeCreatorId = groupId,
			groupId = groupId,
			membershipPath = membershipPath,
			membership = if membershipPath == nil then "ABSENT" else "CURRENT",
			assignedRoles = observed,
			credentialDecision = credential.decision,
			credentialOperation = credential.operation,
			credentialNonce = credential.nonce,
			credentialFreezeCommit = credential.freezeCommit,
			credentialPermissionOperations = operations,
			decision = decision,
			boundary = AUTHORITY_BOUNDARY,
		}
	end

	local operations = operationCovered(credential)
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
		or universe.visibility ~= "PRIVATE"
	then
		return nil, "universe ownership is not the required group"
	end

	local membership, membershipReason = listMemberships(options, authorizedUserId :: number, groupId)
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

local function grantable(record: Record, owner: Owner, unobservableModeration: boolean): boolean
	return type(record) == "table"
		and record.status == 200
		and record.diagnostic == ""
		and record.state == "Active"
		and (AssetReadback.APPROVED_STATES[record.moderationState] == true or (unobservableModeration and record.moderationState == AssetReadback.UNOBSERVABLE.moderation))
		and (record.creatorType == "Group" or record.creatorType == "User")
		and type(record.creatorId) == "string"
		and record.creatorId ~= ""
		and owner ~= nil
end

local function census(records: { Record }, owner: Owner): Partition
	local partition: Partition = {
		contract = PARTITION_CONTRACT,
		candidateReadbacks = {},
		grantAssetIds = {},
		externalAssetIds = {},
		externalReadbacks = {},
		unresolved = {},
		foreignOwned = {},
		closed = false,
	}
	for _, record in records do
		local unobservable = record.source == AssetReadback.SOURCES.details
		if not grantable(record, owner, unobservable) then
			table.insert(partition.unresolved, tostring(record.assetId))
			continue
		end
		table.insert(partition.candidateReadbacks, record)
		if record.creatorType == owner.creatorType and record.creatorId == owner.creatorId then
			table.insert(partition.grantAssetIds, record.assetId)
		elseif record.creatorType == "Group" then
			table.insert(partition.foreignOwned, record.assetId .. ": Group " .. record.creatorId)
		else
			table.insert(partition.externalAssetIds, record.assetId)
			table.insert(partition.externalReadbacks, record)
		end
	end
	partition.closed = #partition.unresolved == 0 and #partition.foreignOwned == 0 and #partition.grantAssetIds > 0
	return partition
end

local function planChunks(assetIds: { string }, size: number): { { string } }
	if type(size) ~= "number" or size < 1 or size ~= math.floor(size) then
		error("Generate permission grant requires a positive integral chunk size", 3)
	end
	local out: { { string } } = {}
	local current: { string } = {}
	for _, assetId in assetIds do
		table.insert(current, assetId)
		if #current == size then
			table.insert(out, current)
			current = {}
		end
	end
	if #current > 0 then
		table.insert(out, current)
	end
	return out
end

local function immutableWrite(transaction: Transaction, path: string, value: unknown): (boolean, string)
	if transaction.store.read(path) ~= nil then
		return false, "immutable receipt already exists: " .. path
	end
	local bytes = transaction.encode(value)
	local ok, reason = pcall(function()
		transaction.store.write(path, bytes)
	end)
	if not ok then
		return false, "receipt write failed: " .. tostring(reason)
	end
	if transaction.store.read(path) ~= bytes then
		return false, "receipt readback mismatch: " .. path
	end
	return true, transaction.digest(bytes)
end

local function stemFor(transaction: Transaction, grantSetSha256: string, index: number): string
	return transaction.outputRoot
		.. "/"
		.. transaction.sourceCommit
		.. "."
		.. transaction.closureSha256
		.. "."
		.. grantSetSha256
		.. ".chunk-"
		.. string.format("%03d", index)
end

local function attemptPaths(transaction: Transaction, stem: string): ({ string }, { string })
	local writeAheads: { string } = {}
	local terminals: { string } = {}
	local escaped = string.gsub(stem, "([^%w])", "%%%1")
	for _, path in transaction.store.list(transaction.outputRoot) do
		if string.match(path, "^" .. escaped .. "%.attempt%-%d+%.write%-ahead%.json$") then
			table.insert(writeAheads, path)
		elseif string.match(path, "^" .. escaped .. "%.attempt%-%d+%.terminal%.json$") then
			table.insert(terminals, path)
		end
	end
	table.sort(writeAheads)
	table.sort(terminals)
	return writeAheads, terminals
end

local function nextAttempt(writeAheads: { string }, terminals: { string }): number
	local maximum = 0
	for _, path in writeAheads do
		maximum = math.max(maximum, tonumber(string.match(path, "%.attempt%-(%d+)%.write%-ahead%.json$") or "0") or 0)
	end
	for _, path in terminals do
		maximum = math.max(maximum, tonumber(string.match(path, "%.attempt%-(%d+)%.terminal%.json$") or "0") or 0)
	end
	return maximum + 1
end

type PersistedReceipt = {
	sourceCommit: string?,
	closureSha256: string?,
	grantSetSha256: string?,
	status: string?,
	chunk: Chunk?,
	chunkOutcome: ChunkOutcome?,
	patch: ReceiptPatch?,
}

local function rawObject(value: unknown): { [string]: unknown }?
	return if type(value) == "table" then value :: { [string]: unknown } else nil
end

local function fieldShapes(value: { [string]: unknown }, names: { string }, kind: string, optional: boolean): boolean
	for _, name in names do
		if (value[name] ~= nil or not optional) and type(value[name]) ~= kind then
			return false
		end
	end
	return true
end

local function stringArray(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	for key, item in value :: { [unknown]: unknown } do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(item) ~= "string" then
			return false
		end
	end
	return true
end

local function patchShape(value: unknown, complete: boolean): boolean
	local patch = rawObject(value)
	return patch ~= nil
		and type(patch.attempted) == "boolean"
		and stringArray(patch.successAssetIds)
		and type(patch.responseBody) == "string"
		and fieldShapes(patch, { "status" }, "number", true)
		and fieldShapes(patch, { "complete" }, "boolean", not complete)
		and fieldShapes(patch, { "diagnostic" }, "string", not complete)
end

local function parseReceipt(transaction: Transaction, bytes: string?): PersistedReceipt?
	if bytes == nil then
		return nil
	end
	local ok, value = pcall(transaction.decode, bytes)
	local receipt = if ok then rawObject(value) else nil
	if
		receipt == nil
		or not fieldShapes(receipt, { "sourceCommit", "closureSha256", "grantSetSha256", "status" }, "string", true)
	then
		return nil
	end
	if receipt.chunk ~= nil then
		local chunk = rawObject(receipt.chunk)
		if
			chunk == nil
			or not fieldShapes(chunk, { "index", "count", "attempt" }, "number", false)
			or not stringArray(chunk.assetIds)
		then
			return nil
		end
	end
	if receipt.patch ~= nil and not patchShape(receipt.patch, false) then
		return nil
	end
	if receipt.chunkOutcome ~= nil then
		local outcome = rawObject(receipt.chunkOutcome)
		if
			outcome == nil
			or not fieldShapes(outcome, { "index", "attempt" }, "number", false)
			or not fieldShapes(outcome, { "status", "writeAheadPath", "writeAheadSha256" }, "string", false)
			or not stringArray(outcome.assetIds)
			or not patchShape(outcome.patch, true)
		then
			return nil
		end
	end
	return value :: PersistedReceipt
end

local function receiptBase(
	transaction: Transaction,
	grantSetSha256: string,
	status: string,
	reason: string,
	patch: ReceiptPatch
): Receipt
	local receipt: Receipt = {}
	for key, value in transaction.context do
		receipt[key] = value
	end
	receipt.contract = transaction.contract
	receipt.status = status
	receipt.reason = reason
	receipt.universeId = transaction.universeId
	receipt.creatorType = transaction.owner.creatorType
	receipt.creatorId = transaction.owner.creatorId
	receipt.sourceCommit = transaction.sourceCommit
	receipt.closureSha256 = transaction.closureSha256
	receipt.grantAssetIds = transaction.grantAssetIds
	receipt.grantSetSha256 = grantSetSha256
	receipt.chunkSize = transaction.chunkSize
	receipt.patch = patch
	return receipt
end

local function validateDestination(destination: Destination): string?
	if
		type(destination) ~= "table"
		or type(destination.endpoint) ~= "string"
		or destination.endpoint == ""
		or type(destination.method) ~= "string"
		or destination.method == ""
		or type(destination.headerNames) ~= "table"
		or #destination.headerNames == 0
	then
		return "destination contract is malformed"
	end
	local seen: { [string]: boolean } = {}
	for index, name in destination.headerNames do
		if type(index) ~= "number" or type(name) ~= "string" or name == "" or seen[name] then
			return "destination contract is malformed"
		end
		seen[name] = true
	end
	return nil
end

local function validateTerminal(terminal: Terminal): string?
	if
		type(terminal) ~= "table"
		or type(terminal.status) ~= "string"
		or terminal.status == ""
		or type(terminal.reason) ~= "string"
		or terminal.reason == ""
		or type(terminal.message) ~= "string"
		or terminal.message == ""
	then
		return "terminal contract is malformed"
	end
	return nil
end

local function validatePrepared(destination: Destination, prepared: Prepared, assetIds: { string }): string?
	if
		type(prepared) ~= "table"
		or prepared.endpoint ~= destination.endpoint
		or prepared.method ~= destination.method
		or type(prepared.body) ~= "string"
		or prepared.body == ""
		or not Wire.sameIds(prepared.headerNames, destination.headerNames)
		or not Wire.sameIds(prepared.requestedAssetIds, assetIds)
	then
		return "outbound request preparation refused"
	end
	return nil
end

local function grant(transaction: Transaction): (Receipt?, string)
	if #transaction.grantAssetIds == 0 then
		return nil, "the grant set is empty"
	end
	local destinationReason = validateDestination(transaction.destination)
	if destinationReason ~= nil then
		return nil, destinationReason
	end
	local terminalContractReason = validateTerminal(transaction.terminal)
	if terminalContractReason ~= nil then
		return nil, terminalContractReason
	end
	local grantSetSha256 = transaction.digest(table.concat(transaction.grantAssetIds, "\n") .. "\n")
	local planned = planChunks(transaction.grantAssetIds, transaction.chunkSize)
	transaction.store.ensure(transaction.outputRoot)
	local completePath = transaction.outputRoot
		.. "/"
		.. transaction.sourceCommit
		.. "."
		.. transaction.closureSha256
		.. "."
		.. grantSetSha256
		.. ".terminal.json"
	if transaction.store.read(completePath) ~= nil then
		return nil, "transaction already has durable state; retry refused"
	end
	local priorTerminals: { string } = transaction.priorTerminalPaths or {}
	for _, path in priorTerminals do
		if transaction.store.read(path) ~= nil then
			return nil, "transaction already has durable state; retry refused"
		end
	end

	local outcomes: { ChunkOutcome } = {}
	for index, assetIds in planned do
		local stem = stemFor(transaction, grantSetSha256, index)
		local writeAheads, terminals = attemptPaths(transaction, stem)
		local lastTerminalPath = terminals[#terminals]
		local prior =
			parseReceipt(transaction, if lastTerminalPath == nil then nil else transaction.store.read(lastTerminalPath))
		if lastTerminalPath ~= nil then
			if
				type(prior) ~= "table"
				or prior.sourceCommit ~= transaction.sourceCommit
				or prior.closureSha256 ~= transaction.closureSha256
				or prior.grantSetSha256 ~= grantSetSha256
				or type(prior.chunk) ~= "table"
				or prior.chunk.index ~= index
				or prior.chunk.count ~= #planned
				or not Wire.sameIds(prior.chunk.assetIds, assetIds)
			then
				return nil,
					"chunk receipt is malformed or does not bind the full ordered grant set: " .. tostring(index)
			end
		end
		if #writeAheads ~= #terminals then
			return nil, "chunk has a write-ahead without a terminal outcome; retry refused: " .. tostring(index)
		end
		if prior ~= nil and prior.status == "CHUNK_GRANTED" then
			if
				type(prior.chunkOutcome) ~= "table"
				or prior.chunkOutcome.status ~= "GRANTED"
				or not Wire.sameIds(prior.chunkOutcome.assetIds, assetIds)
			then
				return nil, "chunk terminal outcome is malformed: " .. tostring(index)
			end
			table.insert(outcomes, prior.chunkOutcome)
			continue
		end
		if prior ~= nil then
			if type(prior.patch) ~= "table" or type(prior.patch.successAssetIds) ~= "table" then
				return nil, "chunk terminal outcome is malformed: " .. tostring(index)
			end
			if prior.patch.status == nil then
				return nil, "chunk outcome is ambiguous; retry refused: " .. tostring(index)
			end
			if #prior.patch.successAssetIds > 0 then
				return nil, "chunk outcome is partial; retry refused: " .. tostring(index)
			end
		end

		local preparedOk, preparedValue = pcall(transaction.prepare, transaction.universeId, assetIds)
		local refusal = if preparedOk
			then validatePrepared(transaction.destination, preparedValue, assetIds)
			else "outbound request preparation refused"
		if refusal ~= nil then
			return nil, refusal .. " for chunk " .. tostring(index)
		end
		local prepared = preparedValue :: Prepared
		local attempt = nextAttempt(writeAheads, terminals)
		local writeAheadPath = stem .. ".attempt-" .. tostring(attempt) .. ".write-ahead.json"
		local terminalPath = stem .. ".attempt-" .. tostring(attempt) .. ".terminal.json"
		local chunk = { index = index, count = #planned, assetIds = assetIds, attempt = attempt }
		local writeAhead = receiptBase(
			transaction,
			grantSetSha256,
			"WRITE_AHEAD",
			"authorized chunk mutation intent recorded before PATCH",
			{ attempted = false, status = nil, successAssetIds = {}, responseBody = "" }
		)
		writeAhead.chunk = chunk
		writeAhead.outboundRequest = {
			endpoint = prepared.endpoint,
			method = prepared.method,
			headerNames = prepared.headerNames,
			bodySha256 = transaction.digest(prepared.body),
		}
		local written, writeResult = immutableWrite(transaction, writeAheadPath, writeAhead)
		if not written then
			return nil, writeResult
		end

		local patchOk, patchResult = pcall(transaction.attempt, prepared)
		local patch: Patch = if patchOk and type(patchResult) == "table"
			then {
				attempted = true,
				status = patchResult.status,
				successAssetIds = patchResult.successAssetIds or {},
				complete = patchResult.complete == true,
				diagnostic = patchResult.diagnostic or "",
				responseBody = patchResult.responseBody or "",
			}
			else {
				attempted = true,
				status = nil,
				successAssetIds = {},
				complete = false,
				diagnostic = "PATCH outcome ambiguous: " .. tostring(patchResult),
				responseBody = "",
			}
		local chunkOutcome = {
			index = index,
			attempt = attempt,
			assetIds = assetIds,
			status = if patch.complete then "GRANTED" else "FAILED",
			patch = patch,
			writeAheadPath = writeAheadPath,
			writeAheadSha256 = writeResult,
		}
		table.insert(outcomes, chunkOutcome)
		local terminal = receiptBase(
			transaction,
			grantSetSha256,
			if patch.complete then "CHUNK_GRANTED" else "HOLD",
			if patch.complete then "chunk granted" else patch.diagnostic,
			patch
		)
		terminal.chunk = chunk
		terminal.chunkOutcome = chunkOutcome
		terminal.chunkOutcomes = outcomes
		terminal.terminalPath = terminalPath
		local terminalWritten, terminalReason = immutableWrite(transaction, terminalPath, terminal)
		if not terminalWritten then
			return nil, "PATCH was attempted; chunk terminal receipt unavailable; retry refused: " .. terminalReason
		end
		if not patch.complete then
			return terminal, "patch incomplete; resume at chunk " .. tostring(index)
		end
	end

	local complete =
		receiptBase(transaction, grantSetSha256, transaction.terminal.status, transaction.terminal.reason, {
			attempted = true,
			status = 200,
			successAssetIds = transaction.grantAssetIds,
			complete = true,
			diagnostic = "",
			responseBody = "",
		})
	complete.chunkOutcomes = outcomes
	complete.terminalPath = completePath
	complete.outboundDestination = transaction.destination
	local terminalWritten, terminalWriteReason = immutableWrite(transaction, completePath, complete)
	if not terminalWritten then
		return nil, "all chunks were granted; terminal receipt unavailable; retry refused: " .. terminalWriteReason
	end
	return complete, transaction.terminal.message
end

return {
	CREDENTIAL_DECISION = CREDENTIAL_DECISION,
	DECISIONS = { bound = BOUND, refused = REFUSED },
	REASONS = { membershipAbsent = MEMBERSHIP_ABSENT, scopesUncovered = SCOPES_UNCOVERED },
	ENDPOINT = PermissionRequest.ENDPOINT,
	MAX_ASSETS_PER_REQUEST = PermissionRequest.MAX_ASSETS_PER_REQUEST,
	subjectAuthority = subjectAuthority,
	census = census,
	chunks = PermissionRequest.chunks,
	prepare = PermissionRequest.prepare,
	attempt = PermissionRequest.attempt,
	grant = grant,
}
