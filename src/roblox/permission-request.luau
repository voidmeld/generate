--!strict

local Wire = require "./wire"

type SendAuthorized = Wire.SendAuthorized
type Decode = Wire.Decode
type Encode = Wire.Encode
type Response = Wire.Response

export type Request = {
	endpoint: string,
	method: "PATCH",
	headerNames: { string },
	body: string,
	universeId: number,
	requestedAssetIds: { string },
}

export type Result = {
	granted: boolean,
	status: number,
	diagnostic: string,
	responseBody: string,
	successAssetIds: { string },
}

local ENDPOINT = "https://apis.roblox.com/asset-permissions-api/v1/assets/permissions"
local BODY_LIMIT = 2000
local MAX_ASSETS_PER_REQUEST = 50
local MAX_ASSET_ID_DIGITS = 20
local MAX_SAFE_ASSET_ID = 9007199254740992
local HEADER_NAMES: { string } = { "Accept", "Content-Type", "x-api-key" }

local function validUniverseId(value: unknown): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function validAssetId(value: unknown): boolean
	return type(value) == "string"
		and #(value :: string) <= MAX_ASSET_ID_DIGITS
		and string.match(value :: string, "^[1-9][0-9]*$") ~= nil
end

local function boundedBody(value: string): string
	local sanitized = string.gsub(value, "[%c]", " ")
	return if #sanitized <= BODY_LIMIT then sanitized else string.sub(sanitized, 1, BODY_LIMIT) .. "[truncated]"
end

local function orderedAssetIds(assetIds: { string }, level: number): { string }
	if type(assetIds) ~= "table" then
		error("Generate universe-use grant requires an array of asset ids", level)
	end
	local ordered: { string } = {}
	local seen: { [string]: boolean } = {}
	for index, assetId in assetIds do
		if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
			error("Generate universe-use grant requires a dense array of asset ids", level)
		end
		if not validAssetId(assetId) then
			error("Generate universe-use grant requires positive numeric asset ids", level)
		end
		if seen[assetId] then
			error("Generate universe-use grant refuses a duplicate asset id " .. assetId, level)
		end
		seen[assetId] = true
		table.insert(ordered, assetId)
	end
	if #ordered == 0 or #ordered ~= #assetIds then
		error("Generate universe-use grant requires a nonempty dense array of asset ids", level)
	end
	table.sort(ordered)
	return ordered
end

local function chunks(assetIds: { string }, size: number): { { string } }
	if type(size) ~= "number" or size < 1 or size ~= math.floor(size) or size > MAX_ASSETS_PER_REQUEST then
		error("Generate universe-use grant chunks require a size within one request's asset bound", 2)
	end
	local ordered = orderedAssetIds(assetIds, 3)
	local output: { { string } } = {}
	for start = 1, #ordered, size do
		local chunk: { string } = {}
		for index = start, math.min(start + size - 1, #ordered) do
			table.insert(chunk, ordered[index])
		end
		table.insert(output, chunk)
	end
	return output
end

local function prepare(encode: Encode, universeId: number, assetIds: { string }): Request
	if not validUniverseId(universeId) then
		error("Generate universe-use grant requires a positive integral universe id", 2)
	end
	local ordered = orderedAssetIds(assetIds, 3)
	if #ordered > MAX_ASSETS_PER_REQUEST then
		error(("Generate universe-use grant admits at most %d asset ids per request"):format(MAX_ASSETS_PER_REQUEST), 2)
	end
	local requests: { { assetId: number, grantToDependencies: boolean } } = {}
	for _, assetId in ordered do
		table.insert(requests, { assetId = tonumber(assetId) :: number, grantToDependencies = false })
	end
	local body = encode {
		subjectType = "Universe",
		subjectId = tostring(universeId),
		action = "Use",
		requests = requests,
	}
	return {
		endpoint = ENDPOINT,
		method = "PATCH" :: "PATCH",
		headerNames = table.clone(HEADER_NAMES),
		body = body,
		universeId = universeId,
		requestedAssetIds = ordered,
	}
end

local function confirmedAssetIds(value: unknown): { string }?
	if type(value) ~= "table" then
		return nil
	end
	local observed: { string } = {}
	local seen: { [string]: boolean } = {}
	local counted = 0
	for index, assetId in value :: { unknown } do
		counted += 1
		if
			type(index) ~= "number"
			or index < 1
			or index ~= math.floor(index)
			or type(assetId) ~= "number"
			or assetId ~= math.floor(assetId)
			or assetId <= 0
			or assetId >= MAX_SAFE_ASSET_ID
		then
			return nil
		end
		local canonical = ("%.0f"):format(assetId)
		if seen[canonical] then
			return nil
		end
		seen[canonical] = true
		table.insert(observed, canonical)
	end
	if counted ~= #(value :: { unknown }) then
		return nil
	end
	table.sort(observed)
	return observed
end

local function refusal(status: number, diagnostic: string, body: string, observed: { string }?): Result
	return {
		granted = false,
		status = status,
		diagnostic = diagnostic,
		responseBody = body,
		successAssetIds = observed or {},
	}
end

local function attempt(send: SendAuthorized, decode: Decode, prepared: Request): Result
	local sent, answer = pcall(send, {
		method = "PATCH" :: "PATCH",
		url = prepared.endpoint,
		headers = { Accept = "application/json", ["Content-Type"] = "application/json" },
		body = prepared.body,
	})
	if not sent then
		return refusal(0, "the permission request did not resolve: " .. tostring(answer), "")
	end
	local response = answer :: Response
	if type(response) ~= "table" or type(response.status) ~= "number" then
		return refusal(0, "the transport returned no response this adapter can read", "")
	end
	if not response.ok or response.status < 200 or response.status >= 300 then
		return refusal(
			response.status,
			("the platform refused the permission grant (%d)"):format(response.status),
			boundedBody(response.body)
		)
	end
	local decoded = decode(response.body)
	if type(decoded) ~= "table" then
		return refusal(
			response.status,
			"the platform answered with an unreadable permission response",
			boundedBody(response.body)
		)
	end
	local body = decoded :: { [string]: unknown }
	for key in body do
		if type(key) == "string" and key ~= "successAssetIds" and key ~= "errors" then
			return refusal(
				response.status,
				"the permission response carried fields this adapter cannot account for",
				boundedBody(response.body)
			)
		end
	end
	local observed = confirmedAssetIds(body.successAssetIds)
	local errors = body.errors
	if type(errors) ~= "table" or next(errors :: { unknown }) ~= nil then
		return refusal(response.status, "the permission response carried errors", boundedBody(response.body), observed)
	end
	if observed == nil then
		return refusal(
			response.status,
			"the permission response did not name its confirmed assets readably",
			boundedBody(response.body)
		)
	end
	if not Wire.sameIds(observed, prepared.requestedAssetIds) then
		return refusal(
			response.status,
			"the permission response did not confirm exactly the requested assets",
			boundedBody(response.body),
			observed
		)
	end
	return {
		granted = true,
		status = response.status,
		diagnostic = "",
		responseBody = boundedBody(response.body),
		successAssetIds = observed,
	}
end

return {
	ENDPOINT = ENDPOINT,
	MAX_ASSETS_PER_REQUEST = MAX_ASSETS_PER_REQUEST,
	chunks = chunks,
	prepare = prepare,
	attempt = attempt,
}
