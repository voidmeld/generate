--!strict

export type Creator = { kind: "group" | "user", id: string }

export type Review = { by: string, verdict: string, shows: string, sha256: string? }

export type Authority = { [string]: unknown }

export type Record = {
	creator: Creator?,
	review: Review?,
	startedAt: number?,
	attempt: string,
	source: string?,
	sha256: string?,
	byteCount: number?,
	assetType: string?,
	displayName: string?,
	description: string?,
	privacy: string?,
	authority: Authority?,
	kind: string?,
	identity: { [string]: string }?,
	operation: string?,
	assetId: string?,
	version: string?,
	moderation: string?,
	verdict: Verdict?,
	reason: string?,
}

export type Store = {
	read: (key: string) -> Record?,
	create: (key: string, record: Record) -> boolean,
	write: (key: string, record: Record) -> (),
}

export type Request = {
	method: "GET" | "POST",
	url: string,
	headers: { [string]: string },
	body: string?,
}

export type Reply =
	{ status: number, body: string, failure: nil, detail: nil }
	| { failure: "unsent" | "unknown", detail: string, status: nil, body: nil }

export type Json = { encode: (value: unknown) -> string, decode: (text: string) -> unknown }

export type Config = {
	creator: Creator,
	privacy: string?,
	store: Store,
	send: ((request: Request) -> Reply)?,
	headers: ((purpose: "create" | "read") -> { [string]: string })?,
	authorize: ((key: string) -> (Authority?, string?))?,
	json: Json?,
	sha256: ((bytes: string) -> string)?,
	now: (() -> number)?,
	wait: ((seconds: number) -> ())?,
	baseUrl: string?,
	polls: number?,
	interval: number?,
}

export type Verdict = "approved" | "hold" | "stop"

export type Result = {
	verdict: Verdict,
	reason: string,
	detail: string?,
	retry: "safe" | "poll" | "never",
	assetId: string?,
	version: string?,
	moderation: string?,
	operation: string?,
	record: Record?,
}

export type UploadRequest = {
	label: string,
	bytes: string,
	name: string,
	description: string?,
	format: string,
	review: Review,
}

export type Item = {
	name: string,
	prepare: () -> (UploadRequest?, string?, string?),
}

export type Row = { name: string, operation: string, assetId: string, verdict: Verdict, state: string }

export type QueueOptions = {
	spacing: number?,
	log: ((row: Row) -> ())?,
}

export type QueueResult = {
	verdict: Verdict,
	reason: string,
	name: string?,
	detail: string?,
	rows: { Row },
}

export type Info = {
	assetId: string?,
	creator: Creator?,
	assetType: string?,
	version: string?,
	moderation: string?,
}

export type NativeHost = {
	inspect: ((object: unknown) -> (boolean, string?))?,
	create: (
		object: unknown,
		kind: string,
		parameters: { creator: Creator, name: string }
	) -> {
		result: string,
		assetId: unknown,
		warnings: { string }?,
	},
	readback: (assetId: string) -> Info,
}

export type NativeRequest = {
	key: string,
	object: unknown,
	kind: string,
	name: string,
	review: Review,
	identity: { [string]: string }?,
}

type Extra = {
	assetId: string?,
	version: string?,
	moderation: string?,
	operation: string?,
	record: Record?,
}

local DEFAULT_BASE_URL = "https://apis.roblox.com/assets/v1/"
local MAX_BYTES = 20000000

local FORMATS: { [string]: { assetType: string, contentType: string } } = {
	png = { assetType = "Image", contentType = "image/png" },
	wav = { assetType = "Audio", contentType = "audio/wav" },
	mp3 = { assetType = "Audio", contentType = "audio/mpeg" },
	ogg = { assetType = "Audio", contentType = "audio/ogg" },
	rbxm = { assetType = "Animation", contentType = "model/x-rbxm" },
	rbxmx = { assetType = "Animation", contentType = "model/x-rbxm" },
}

local function applyExtra(value: Result, extra: Extra)
	value.assetId = extra.assetId
	value.version = extra.version
	value.moderation = extra.moderation
	value.operation = extra.operation
	value.record = extra.record
end

local function result(verdict: Verdict, reason: string, retry: "safe" | "poll" | "never", extra: Extra?): Result
	local value: Result = { verdict = verdict, reason = reason, retry = retry }
	if extra then
		applyExtra(value, extra)
	end
	return value
end

local function stop(reason: string, detail: string?, extra: Extra?): Result
	local value = result("stop", reason, "never", extra)
	value.detail = detail
	return value
end

local function hold(reason: string, retry: "safe" | "poll", detail: string?, extra: Extra?): Result
	local value = result("hold", reason, retry, extra)
	value.detail = detail
	return value
end

local function copy(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local clone: { [unknown]: unknown } = {}
	for key, item in value :: { [unknown]: unknown } do
		clone[key] = copy(item)
	end
	return clone
end

local function copyRecord(value: Record): Record
	return copy(value) :: Record
end

local function copyCreator(value: Creator): Creator
	return copy(value) :: Creator
end

local function copyIdentity(value: { [string]: string }?): { [string]: string }?
	return copy(value) :: { [string]: string }?
end

local function redact(text: string, secrets: { [string]: string }?): string
	if secrets then
		for _, secret in secrets do
			if #secret >= 6 then
				local from = 1
				while true do
					local first, last = string.find(text, secret, from, true)
					if first == nil then
						break
					end
					text = string.sub(text, 1, first - 1) .. "[redacted]" .. string.sub(text, (last :: number) + 1)
					from = first + #"[redacted]"
				end
			end
		end
	end
	return text
end

local function validCreator(creator: Creator): boolean
	return type(creator) == "table"
		and (creator.kind == "group" or creator.kind == "user")
		and type(creator.id) == "string"
		and string.match(creator.id, "^[1-9]%d*$") ~= nil
end

local function creatorMatches(expected: Creator, actual: Creator?): boolean
	return actual ~= nil and actual.kind == expected.kind and tostring(actual.id) == expected.id
end

local function reviewRefusal(review: Review, digest: string?): string?
	if type(review) ~= "table" then
		return "a review record is required"
	end
	if type(review.by) ~= "string" or review.by == "" then
		return "the review names no reviewer"
	end
	if review.verdict ~= "complies" then
		return "the review verdict is not complies"
	end
	if type(review.shows) ~= "string" or #review.shows < 8 then
		return "the review does not describe what the reviewer saw"
	end
	if digest ~= nil and review.sha256 ~= digest then
		return "the review does not match these bytes"
	end
	return nil
end

local function refusalText(text: string): boolean
	local lower = string.lower(text)
	return string.find(lower, "moderat", 1, true) ~= nil
		or string.find(lower, "reject", 1, true) ~= nil
		or string.find(lower, "refus", 1, true) ~= nil
end

local function now(config: Config): number
	return if config.now then config.now() else 0
end

local function exchange(
	config: Config,
	purpose: "create" | "read",
	method: "GET" | "POST",
	path: string,
	body: string?,
	contentType: string?
): (Reply, { [string]: string }?)
	local send = config.send
	if send == nil or config.headers == nil then
		return { failure = "unsent", detail = "no transport is configured" }, nil
	end
	local headers = table.clone(config.headers(purpose))
	headers["Content-Type"] = contentType or "application/json"
	local ok, reply = pcall(send, {
		method = method,
		url = (config.baseUrl or DEFAULT_BASE_URL) .. path,
		headers = headers,
		body = body,
	})
	if not ok then
		return { failure = "unknown", detail = redact(tostring(reply), headers) }, headers
	end
	if type(reply) == "table" and reply.failure then
		reply.detail = redact(tostring(reply.detail), headers)
	end
	return reply, headers
end

local function decodeBody(config: Config, body: string): { [string]: unknown }?
	local json = config.json
	if json == nil then
		return nil
	end
	local ok, value = pcall(json.decode, body)
	if ok and type(value) == "table" then
		return value :: { [string]: unknown }
	end
	return nil
end

local function statusFailure(reply: Reply): Result?
	local status = reply.status :: number
	local body = reply.body :: string
	if status >= 200 and status < 300 then
		return nil
	end
	local text = "HTTP " .. tostring(status) .. " " .. string.sub(body, 1, 200)
	if status == 401 or status == 403 or refusalText(body) then
		return stop("refused", text)
	end
	if status == 429 then
		return hold("rate_limited", "safe", text)
	end
	return stop("failed", text)
end

local function moderationVerdict(
	info: Info,
	expectedType: string?,
	creator: Creator,
	extra: Extra,
	needVersion: boolean
): Result
	if info.assetId == nil or not creatorMatches(creator, info.creator) then
		return stop("identity", "the asset creator is not the configured creator", extra)
	end
	if expectedType ~= nil and info.assetType ~= expectedType then
		return stop("identity", "the asset type differs from the request", extra)
	end
	extra.assetId = info.assetId
	extra.version = info.version
	extra.moderation = info.moderation
	if info.moderation == "Rejected" then
		return stop("rejected", "moderation rejected the asset", extra)
	end
	if info.moderation == "Approved" then
		if needVersion and (info.version == nil or info.version == "") then
			return stop("identity", "the approved asset has no version", extra)
		end
		return result("approved", "approved", "never", extra)
	end
	return hold("pending", "poll", info.moderation, extra)
end

local function readAsset(config: Config, assetId: string, expectedType: string?, extra: Extra): Result
	local reply = exchange(config, "read", "GET", "assets/" .. assetId, nil, nil)
	if reply.failure then
		return hold("remote_unreachable", "poll", reply.detail, extra)
	end
	local failed = statusFailure(reply)
	if failed then
		applyExtra(failed, extra)
		return failed
	end
	local body = decodeBody(config, reply.body :: string)
	if body == nil or tostring(body.assetId) ~= assetId then
		return hold("malformed", "poll", "the asset readback is not a matching document", extra)
	end
	local context = body.creationContext
	if context ~= nil and type(context) ~= "table" then
		return hold("malformed", "poll", "the asset readback carries an invalid creation context", extra)
	end
	local creator = if type(context) == "table" then (context :: { [string]: unknown }).creator else nil
	local actual: Creator? = nil
	if creator ~= nil then
		if type(creator) ~= "table" then
			return hold("malformed", "poll", "the asset readback carries an invalid creator", extra)
		end
		local fields = creator :: { [string]: unknown }
		for _, name in { "groupId", "userId" } do
			local id = fields[name]
			if id ~= nil and type(id) ~= "string" and type(id) ~= "number" then
				return hold("malformed", "poll", "the asset readback carries an invalid creator id", extra)
			end
		end
		if fields.groupId ~= nil and fields.userId == nil then
			actual = { kind = "group", id = tostring(fields.groupId) }
		elseif fields.userId ~= nil and fields.groupId == nil then
			actual = { kind = "user", id = tostring(fields.userId) }
		end
	end
	local assetType = body.assetType
	local moderation: string? = nil
	if assetType ~= nil and type(assetType) ~= "string" then
		return hold("malformed", "poll", "the asset readback carries an invalid asset type", extra)
	end
	if body.moderationResult ~= nil then
		if type(body.moderationResult) ~= "table" then
			return hold("malformed", "poll", "the asset readback carries an invalid moderation result", extra)
		end
		local state = (body.moderationResult :: { [string]: unknown }).moderationState
		if state ~= nil and type(state) ~= "string" then
			return hold("malformed", "poll", "the asset readback carries an invalid moderation state", extra)
		end
		moderation = if type(state) == "string" then state else nil
	end
	local info: Info = {
		assetId = assetId,
		creator = actual,
		assetType = if type(assetType) == "string" then assetType else nil,
		version = if type(body.revisionId) == "string" then body.revisionId else nil,
		moderation = moderation,
	}
	return moderationVerdict(info, expectedType, config.creator, extra, true)
end

local function readOperation(config: Config, operation: string, extra: Extra): (string?, Result?)
	local reply = exchange(config, "read", "GET", operation, nil, nil)
	if reply.failure then
		return nil, hold("remote_unreachable", "poll", reply.detail, extra)
	end
	local failed = statusFailure(reply)
	if failed then
		applyExtra(failed, extra)
		return nil, failed
	end
	local body = decodeBody(config, reply.body :: string)
	if body == nil then
		return nil, hold("malformed", "poll", "the operation readback is not a document", extra)
	end
	if body.error ~= nil then
		local text = if config.json then config.json.encode(body.error) else tostring(body.error)
		if refusalText(text) then
			return nil, stop("rejected", text, extra)
		end
		return nil, stop("failed", text, extra)
	end
	if body.done ~= true then
		return nil, hold("pending", "poll", "operation is not done", extra)
	end
	local response = body.response
	if type(response) ~= "table" or (response :: { assetId: unknown }).assetId == nil then
		return nil, stop("failed", "the finished operation returned no asset", extra)
	end
	return tostring((response :: { assetId: unknown }).assetId), nil
end

local function readState(config: Config, record: Record): Result
	local extra: Extra = { operation = record.operation }
	local assetId = record.assetId
	if assetId == nil then
		if record.operation == nil then
			return stop("ambiguous", "no operation or asset id is recorded", extra)
		end
		local found, pending = readOperation(config, record.operation, extra)
		if pending then
			return pending
		end
		assetId = found
		record.assetId = found
	end
	local state = readAsset(config, assetId :: string, record.assetType, extra)
	if state.version ~= nil then
		record.version = state.version
	end
	if state.moderation ~= nil then
		record.moderation = state.moderation
	end
	return state
end

local function pollSettled(config: Config, key: string, record: Record): Result
	local polls = config.polls or 1
	local interval = config.interval or 0
	local state = readState(config, record)
	for _ = 2, polls do
		if state.verdict ~= "hold" then
			break
		end
		if config.wait then
			config.wait(interval)
		end
		state = readState(config, record)
	end
	record.verdict = state.verdict
	record.reason = state.reason
	config.store.write(key, copyRecord(record))
	state.record = copyRecord(record)
	return state
end

local function multipart(
	config: Config,
	request: UploadRequest,
	digest: string,
	format: { contentType: string }
): (string, string)
	local json = config.json :: Json
	local boundary = "generate" .. digest
	local creator = if config.creator.kind == "group"
		then { groupId = config.creator.id }
		else { userId = config.creator.id }
	local envelope = json.encode {
		assetType = FORMATS[request.format].assetType,
		displayName = request.name,
		description = request.description or "",
		creationContext = { creator = creator, assetPrivacy = config.privacy or "restricted" },
	}
	local body = table.concat {
		"--",
		boundary,
		'\r\nContent-Disposition: form-data; name="request"\r\nContent-Type: application/json\r\n\r\n',
		envelope,
		"\r\n--",
		boundary,
		'\r\nContent-Disposition: form-data; name="fileContent"; filename="asset.',
		request.format,
		'"\r\nContent-Type: ',
		format.contentType,
		"\r\n\r\n",
		request.bytes,
		"\r\n--",
		boundary,
		"--\r\n",
	}
	return body, "multipart/form-data; boundary=" .. boundary
end

local function validateConfig(config: Config): string?
	if not validCreator(config.creator) then
		return "a group or user creator with a numeric id is required"
	end
	if config.store == nil then
		return "a record store is required"
	end
	return nil
end

local function upload(config: Config, request: UploadRequest): Result
	local invalid = validateConfig(config)
	if invalid then
		return stop("invalid", invalid)
	end
	if config.sha256 == nil or config.json == nil or config.send == nil or config.headers == nil then
		return stop("invalid", "sha256, json, send and headers are required for a file upload")
	end
	local format = FORMATS[request.format]
	if format == nil then
		return stop("invalid", "supported formats are png, wav, mp3, ogg, rbxm and rbxmx")
	end
	if type(request.name) ~= "string" or request.name == "" or #request.name > 50 then
		return stop("invalid", "the display name must contain 1 to 50 bytes")
	end
	if #request.bytes == 0 or #request.bytes > MAX_BYTES then
		return stop("invalid", "the file must contain 1 to 20,000,000 bytes")
	end
	local digest = config.sha256(request.bytes)
	local unreviewed = reviewRefusal(request.review, digest)
	if unreviewed then
		return stop("unreviewed", unreviewed)
	end
	local existing = config.store.read(digest)
	if existing then
		if
			existing.sha256 ~= digest
			or not creatorMatches(config.creator, existing.creator)
			or existing.assetType ~= format.assetType
		then
			return stop("identity", "the stored record names different bytes, creator or type")
		end
		if existing.attempt == "refused" or existing.attempt == "failed" then
			return stop(
				existing.attempt,
				"an earlier attempt for these bytes was refused; nothing is sent again",
				{ record = existing }
			)
		end
		if existing.assetId ~= nil or existing.operation ~= nil then
			return pollSettled(config, digest, copyRecord(existing))
		end
		if existing.attempt ~= "unsent" then
			return stop(
				"ambiguous",
				"an earlier send has no recorded outcome; resolve it with attach before anything is sent",
				{ record = existing }
			)
		end
	end
	local evidence: Authority? = nil
	if config.authorize then
		local granted, reason = config.authorize(digest)
		if granted == nil then
			return stop("not_authorized", reason or "authorization refused")
		end
		evidence = granted
	end
	local record: Record = {
		source = request.label,
		sha256 = digest,
		byteCount = #request.bytes,
		assetType = format.assetType,
		displayName = request.name,
		description = request.description or "",
		creator = copyCreator(config.creator),
		privacy = config.privacy or "restricted",
		review = { by = request.review.by, verdict = request.review.verdict, shows = request.review.shows },
		authority = evidence,
		startedAt = now(config),
		attempt = "sending",
	}
	if existing then
		if not pcall(config.store.write, digest, copyRecord(record)) then
			return stop("ambiguous", "the write-ahead record could not be updated")
		end
	elseif not config.store.create(digest, copyRecord(record)) then
		return stop("concurrent", "another invocation owns these bytes")
	end
	local body, contentType = multipart(config, request, digest, format)
	local reply = exchange(config, "create", "POST", "assets", body, contentType)
	local failure = reply.failure
	if failure == "unsent" then
		record.attempt = "unsent"
		config.store.write(digest, copyRecord(record))
		return hold("remote_unreachable", "safe", reply.detail, { record = copyRecord(record) })
	end
	if failure == "unknown" then
		return stop("ambiguous", reply.detail, { record = copyRecord(record) })
	end
	local status = reply.status :: number
	if status >= 200 and status < 300 then
		local decoded = decodeBody(config, reply.body :: string)
		local operation = decoded and decoded.path
		if type(operation) ~= "string" or string.match(operation, "^operations/[%x%-]+$") == nil then
			return stop("ambiguous", "the create call returned no operation", { record = copyRecord(record) })
		end
		record.operation = operation
		record.attempt = "accepted"
		config.store.write(digest, copyRecord(record))
		return pollSettled(config, digest, record)
	end
	if status == 429 then
		record.attempt = "unsent"
		config.store.write(digest, copyRecord(record))
		return hold("rate_limited", "safe", "HTTP 429", { record = copyRecord(record) })
	end
	if status >= 500 then
		return stop(
			"ambiguous",
			"HTTP " .. tostring(status) .. "; the server may have created the asset",
			{ record = copyRecord(record) }
		)
	end
	local refused = statusFailure(reply) :: Result
	record.attempt = if refused.reason == "refused" then "refused" else "failed"
	config.store.write(digest, copyRecord(record))
	refused.record = copyRecord(record)
	return refused
end

local function attach(config: Config, key: string, reference: { operation: string?, assetId: string? }): Result
	local record = config.store.read(key)
	if record == nil then
		return stop("invalid", "no record exists for this key")
	end
	if record.assetId ~= nil or record.operation ~= nil then
		return stop("invalid", "the record already has an outcome")
	end
	if reference.operation ~= nil and string.match(reference.operation, "^operations/[%x%-]+$") then
		record.operation = reference.operation
	elseif reference.assetId ~= nil and string.match(reference.assetId, "^[1-9]%d*$") then
		record.assetId = reference.assetId
	else
		return stop("invalid", "an operation path or numeric asset id is required")
	end
	record.attempt = "resolved"
	config.store.write(key, copyRecord(record))
	return pollSettled(config, key, record)
end

local function nativeAttach(config: Config, key: string, assetId: string): Result
	local invalid = validateConfig(config)
	if invalid then
		return stop("invalid", invalid)
	end
	local record = config.store.read(key)
	if record == nil or record.assetId ~= nil then
		return stop("invalid", "an unresolved record is required")
	end
	if string.match(assetId, "^[1-9]%d*$") == nil then
		return stop("invalid", "a numeric asset id is required")
	end
	record.assetId = assetId
	record.attempt = "resolved"
	config.store.write(key, copyRecord(record))
	return hold(
		"pending",
		"poll",
		"save again to read back the attached asset",
		{ assetId = assetId, record = copyRecord(record) }
	)
end

local function status(config: Config, reference: string, expectedType: string?): Result
	local invalid = validateConfig(config)
	if invalid then
		return stop("invalid", invalid)
	end
	local extra: Extra = {}
	local assetId = reference
	if string.match(reference, "^operations/[%x%-]+$") then
		extra.operation = reference
		local found, pending = readOperation(config, reference, extra)
		if pending then
			return pending
		end
		assetId = found :: string
	end
	if string.match(assetId, "^[1-9]%d*$") == nil then
		return stop("invalid", "expected an asset id or operations/<id>")
	end
	return readAsset(config, assetId, expectedType, extra)
end

local function queue(config: Config, items: { Item }, options: QueueOptions?): QueueResult
	local opts: QueueOptions = options or {}
	local rows: { Row } = {}
	local lastPost: number? = nil
	local function record(name: string, outcome: Result?, reason: string, verdict: Verdict)
		local row: Row = {
			name = name,
			operation = if outcome and outcome.operation then outcome.operation else "",
			assetId = if outcome and outcome.assetId then outcome.assetId else "",
			verdict = verdict,
			state = if outcome and outcome.moderation then outcome.moderation else reason,
		}
		table.insert(rows, row)
		if opts.log then
			opts.log(row)
		end
	end
	for _, item in items do
		local request, reason, detail = item.prepare()
		if request == nil then
			record(item.name, nil, reason or "invalid", "stop")
			return { verdict = "stop", reason = reason or "invalid", name = item.name, detail = detail, rows = rows }
		end
		local digest = if config.sha256 then config.sha256(request.bytes) else ""
		local fresh = config.store.read(digest) == nil
		if fresh and lastPost ~= nil and opts.spacing and config.wait then
			local remaining = opts.spacing - (now(config) - lastPost)
			if remaining > 0 then
				config.wait(remaining)
			end
		end
		if fresh then
			lastPost = now(config)
		end
		local outcome = upload(config, request)
		record(item.name, outcome, outcome.reason, outcome.verdict)
		if outcome.verdict ~= "approved" then
			return {
				verdict = outcome.verdict,
				reason = outcome.reason,
				name = item.name,
				detail = outcome.detail,
				rows = rows,
			}
		end
	end
	return { verdict = "approved", reason = "approved", rows = rows }
end

export type AttributeInstance = {
	GetAttribute: (self: AttributeInstance, name: string) -> unknown,
	SetAttribute: (self: AttributeInstance, name: string, value: string) -> (),
}

export type AttributeJson = {
	JSONEncode: (self: AttributeJson, value: Record) -> string,
	JSONDecode: (self: AttributeJson, text: string) -> Record,
}

local function attributeStore(instance: AttributeInstance, http: AttributeJson): Store
	return {
		read = function(key)
			local text = instance:GetAttribute(key .. "Record")
			return if type(text) == "string" then http:JSONDecode(text) else nil
		end,
		create = function(key, record)
			if instance:GetAttribute(key .. "Record") ~= nil then
				return false
			end
			instance:SetAttribute(key .. "Record", http:JSONEncode(record))
			return true
		end,
		write = function(key, record)
			instance:SetAttribute(key .. "Record", http:JSONEncode(record))
		end,
	}
end

local function nativeReadback(host: NativeHost, assetId: string, kind: string, creator: Creator): Result
	local ok, info = pcall(host.readback, assetId)
	if not ok then
		return hold("remote_unreachable", "poll", tostring(info), { assetId = assetId })
	end
	return moderationVerdict(info, kind, creator, {}, false)
end

local function nativeSave(config: Config, host: NativeHost, request: NativeRequest): Result
	local invalid = validateConfig(config)
	if invalid then
		return stop("invalid", invalid)
	end
	local unreviewed = reviewRefusal(request.review, nil)
	if unreviewed then
		return stop("unreviewed", unreviewed)
	end
	local key = request.key
	local existing = config.store.read(key)
	if existing then
		if existing.kind ~= request.kind or not creatorMatches(config.creator, existing.creator) then
			return stop("identity", "the stored record names a different kind or creator")
		end
		if existing.assetId ~= nil then
			local record = copyRecord(existing)
			local state = nativeReadback(host, record.assetId :: string, request.kind, config.creator)
			record.moderation = state.moderation or record.moderation
			record.version = state.version or record.version
			config.store.write(key, copyRecord(record))
			state.record = copyRecord(record)
			return state
		end
		return stop(
			"ambiguous",
			"an earlier save has no recorded asset id; resolve it with attach before anything is sent",
			{ record = existing }
		)
	end
	if host.inspect then
		local ok, detail = host.inspect(request.object)
		if not ok then
			return stop("inspection", detail or "inspection refused the object")
		end
	end
	local record: Record = {
		kind = request.kind,
		displayName = request.name,
		creator = copyCreator(config.creator),
		review = { by = request.review.by, verdict = request.review.verdict, shows = request.review.shows },
		identity = copyIdentity(request.identity),
		startedAt = now(config),
		attempt = "started",
	}
	if not config.store.create(key, copyRecord(record)) then
		return stop("concurrent", "another invocation owns this key")
	end
	local ok, created =
		pcall(host.create, request.object, request.kind, { creator = copyCreator(config.creator), name = request.name })
	if not ok then
		return stop("ambiguous", tostring(created), { record = copyRecord(record) })
	end
	local assetId = if created.assetId ~= nil and string.match(tostring(created.assetId), "^[1-9]%d*$")
		then tostring(created.assetId)
		else nil
	if assetId ~= nil then
		record.assetId = assetId
	end
	if created.result ~= "Success" then
		record.attempt = tostring(created.result)
		config.store.write(key, copyRecord(record))
		return stop("failed", tostring(created.result), { record = copyRecord(record), assetId = assetId })
	end
	if assetId == nil then
		return stop("ambiguous", "the save reported success without a usable asset id", { record = copyRecord(record) })
	end
	record.attempt = "saved"
	config.store.write(key, copyRecord(record))
	if created.warnings and #created.warnings > 0 then
		return stop("warning", table.concat(created.warnings, "; "), { record = copyRecord(record), assetId = assetId })
	end
	local state = nativeReadback(host, assetId, request.kind, config.creator)
	record.moderation = state.moderation
	record.version = state.version
	config.store.write(key, copyRecord(record))
	state.record = copyRecord(record)
	return state
end

return table.freeze {
	upload = upload,
	status = status,
	attach = attach,
	queue = queue,
	native = table.freeze { save = nativeSave, attach = nativeAttach, attributeStore = attributeStore },
}
