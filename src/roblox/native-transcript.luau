--!strict

local Generate = require "../core"

export type Tool = "execute_luau" | "screen_capture"

export type Binding = {
	artifactDigest: string,
	studio: { [string]: unknown },
}

export type CallDraft = {
	label: string,
	tool: Tool,
	arguments: { [string]: unknown },
}

export type Codec = {
	encode: (value: unknown) -> string,
	sha256: (bytes: string) -> string,
}

export type PlannedCall = {
	label: string,
	tool: Tool,
	arguments: string,
	requestSha256: string,
}

export type BoundPlan = {
	schema: "generate.roblox.native-plan.v1",
	artifactDigest: string,
	studio: { [string]: unknown },
	studioId: string,
	calls: { PlannedCall },
	grant: { string },
	planSha256: string,
}

export type FileReference = { path: string, sha256: string, byteCount: number }

export type Entry = {
	label: string,
	tool: Tool,
	requestSha256: string,
	status: "returned" | "failed" | "ambiguous",
	request: FileReference,
	response: FileReference?,
	image: FileReference?,
	detail: string?,
}

export type Transcript = {
	schema: "generate.roblox.native-transcript.v1",
	planSha256: string,
	artifactDigest: string,
	studioId: string,
	status: "complete" | "stopped",
	entries: { Entry },
}

export type ExecuteHost = {
	call: (tool: Tool, argumentsBytes: string) -> string,
	writeNew: (name: string, bytes: string) -> string,
	readFile: (path: string) -> string,
	sha256: (bytes: string) -> string,
	decode: (bytes: string) -> unknown,
}

export type ReadHost = {
	readFile: (path: string) -> string,
	sha256: (bytes: string) -> string,
	decode: (bytes: string) -> unknown,
}

export type Caps = {
	requestBytes: number,
	responseBytes: number,
	imageBytes: number,
	excludedImages: { string }?,
}

export type ImageResult = FileReference & { mediaType: "image/png" | "image/jpeg" }

export type Verified = {
	results: { [string]: string },
	images: { [string]: ImageResult },
}

local PLAN_SCHEMA: "generate.roblox.native-plan.v1" = "generate.roblox.native-plan.v1"
local TRANSCRIPT_SCHEMA: "generate.roblox.native-transcript.v1" = "generate.roblox.native-transcript.v1"
local TOOLS: { [string]: boolean } = { execute_luau = true, screen_capture = true }
local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_INDEX: { [number]: number } = {}
for index = 1, #BASE64 do
	BASE64_INDEX[string.byte(BASE64, index)] = index - 1
end

local function demand(condition: boolean, detail: string)
	if not condition then
		error("Generate native transcript " .. detail, 3)
	end
end

local function digest(value: unknown): boolean
	return type(value) == "string" and #value == 64 and string.match(value :: string, "^[0-9a-f]+$") ~= nil
end

local function requestBytes(call: PlannedCall): string
	return '{"arguments":' .. call.arguments .. ',"name":"' .. call.tool .. '"}'
end

local function planIdentity(plan: BoundPlan, sha256: (string) -> string): string
	local calls: { unknown } = {}
	for _, call in plan.calls do
		table.insert(calls, {
			label = call.label,
			tool = call.tool,
			arguments = call.arguments,
			requestSha256 = call.requestSha256,
		})
	end
	return sha256(Generate.canonical {
		schema = plan.schema,
		artifactDigest = plan.artifactDigest,
		studio = plan.studio,
		studioId = plan.studioId,
		calls = calls,
		grant = plan.grant,
	})
end

local function prepare(binding: Binding, drafts: { CallDraft }, codec: Codec): BoundPlan
	demand(type(binding) == "table" and digest(binding.artifactDigest), "requires an exact artifact digest")
	demand(type(binding.studio) == "table", "requires a Studio binding")
	local studioId = binding.studio.studioId
	demand(type(studioId) == "string" and studioId ~= "", "requires a bound studioId")
	demand(type(drafts) == "table" and #drafts > 0, "requires at least one declared call")
	local calls: { PlannedCall } = {}
	local grant: { string } = {}
	local labels: { [string]: boolean } = {}
	local requests: { [string]: boolean } = {}
	for _, draft in drafts do
		demand(
			type(draft.label) == "string" and string.match(draft.label, "^[%w_%-]+$") ~= nil,
			"calls require file-safe labels"
		)
		demand(not labels[draft.label], "labels must be unique: " .. draft.label)
		labels[draft.label] = true
		demand(TOOLS[draft.tool] == true, "tool is not admitted: " .. tostring(draft.tool))
		demand(type(draft.arguments) == "table", "calls require an arguments object")
		demand(draft.arguments.studio_id == studioId, "call " .. draft.label .. " targets another Studio")
		if draft.tool == "execute_luau" then
			demand(type(draft.arguments.code) == "string" and draft.arguments.code ~= "", "execute_luau requires code")
		end
		local call: PlannedCall = {
			label = draft.label,
			tool = draft.tool,
			arguments = codec.encode(draft.arguments),
			requestSha256 = "",
		}
		call.requestSha256 = codec.sha256(requestBytes(call))
		demand(not requests[call.requestSha256], "requests must be distinct: " .. draft.label)
		requests[call.requestSha256] = true
		table.insert(calls, call)
		table.insert(grant, call.requestSha256)
	end
	local plan: BoundPlan = {
		schema = PLAN_SCHEMA,
		artifactDigest = binding.artifactDigest,
		studio = binding.studio,
		studioId = studioId :: string,
		calls = calls,
		grant = grant,
		planSha256 = "",
	}
	plan.planSha256 = planIdentity(plan, codec.sha256)
	return plan
end

local function checkPlan(plan: BoundPlan, sha256: (string) -> string)
	demand(type(plan) == "table" and plan.schema == PLAN_SCHEMA, "requires a " .. PLAN_SCHEMA .. " plan")
	demand(digest(plan.artifactDigest), "plan requires an exact artifact digest")
	demand(
		type(plan.studio) == "table" and plan.studio.studioId == plan.studioId and plan.studioId ~= "",
		"plan Studio binding drift"
	)
	demand(
		type(plan.calls) == "table" and #plan.calls > 0 and #plan.grant == #plan.calls,
		"plan grant must name every call"
	)
	for index, call in plan.calls do
		demand(TOOLS[call.tool] == true, "plan tool is not admitted")
		demand(sha256(requestBytes(call)) == call.requestSha256, "plan request drift: " .. call.label)
		demand(plan.grant[index] == call.requestSha256, "plan grant order drift: " .. call.label)
	end
	demand(planIdentity(plan, sha256) == plan.planSha256, "plan digest drift")
end

local function reference(path: string, bytes: string, sha256: (string) -> string): FileReference
	return { path = path, sha256 = sha256(bytes), byteCount = #bytes }
end

local function base64Decode(text: string): string?
	local clean = string.gsub(text, "%s", "")
	if #clean % 4 ~= 0 then
		return nil
	end
	local pieces: { string } = {}
	for index = 1, #clean, 4 do
		local values: { number } = {}
		local padding = 0
		for offset = 0, 3 do
			local byte = string.byte(clean, index + offset) :: number
			if byte == 61 then
				if index + 3 ~= #clean or offset < 2 then
					return nil
				end
				padding += 1
				values[offset + 1] = 0
			else
				if padding > 0 then
					return nil
				end
				local value = BASE64_INDEX[byte]
				if value == nil then
					return nil
				end
				values[offset + 1] = value
			end
		end
		local packed = values[1] * 262144 + values[2] * 4096 + values[3] * 64 + values[4]
		local decoded =
			string.char(bit32.rshift(packed, 16), bit32.band(bit32.rshift(packed, 8), 255), bit32.band(packed, 255))
		table.insert(pieces, string.sub(decoded, 1, 3 - padding))
	end
	return table.concat(pieces)
end

local function sniff(bytes: string): string?
	if string.sub(bytes, 1, 8) == "\137PNG\r\n\26\n" then
		return "image/png"
	end
	if string.sub(bytes, 1, 3) == "\255\216\255" then
		return "image/jpeg"
	end
	return nil
end

type Content = { kind: "text", text: string } | { kind: "image", bytes: string, mediaType: string }

local function content(tool: Tool, response: unknown): (Content?, string?)
	if type(response) ~= "table" then
		return nil, "response is not a tool result"
	end
	local result = response :: { [string]: unknown }
	if result.isError ~= false then
		return nil, "tool reported an error"
	end
	local items = result.content
	if type(items) ~= "table" or #(items :: { unknown }) ~= 1 or type((items :: { unknown })[1]) ~= "table" then
		return nil, "tool result requires exactly one content item"
	end
	local item = (items :: { unknown })[1] :: { [string]: unknown }
	if tool == "execute_luau" then
		if item.type ~= "text" or type(item.text) ~= "string" then
			return nil, "execute_luau requires one text result"
		end
		return { kind = "text", text = item.text }, nil
	end
	if item.type ~= "image" or type(item.data) ~= "string" or type(item.mimeType) ~= "string" then
		return nil, "screen_capture requires one image result"
	end
	local bytes = base64Decode(item.data)
	if bytes == nil then
		return nil, "screen_capture image is not base64"
	end
	local sniffed = sniff(bytes :: string)
	if sniffed == nil or sniffed ~= item.mimeType then
		return nil, "screen_capture media type mismatch"
	end
	return { kind = "image", bytes = bytes :: string, mediaType = sniffed :: string }, nil
end

local function execute(plan: BoundPlan, host: ExecuteHost): Transcript
	checkPlan(plan, host.sha256)
	local transcript: Transcript = {
		schema = TRANSCRIPT_SCHEMA,
		planSha256 = plan.planSha256,
		artifactDigest = plan.artifactDigest,
		studioId = plan.studioId,
		status = "complete",
		entries = {},
	}
	for index, call in plan.calls do
		local stem = string.format("%03d-%s", index, call.label)
		local bytes = requestBytes(call)
		local written, path = pcall(host.writeNew, stem .. ".request.json", bytes)
		demand(written, "refuses to overwrite or retry a prior attempt: " .. tostring(path))
		demand(host.readFile(path :: string) == bytes, "request readback mismatch: " .. call.label)
		local entry: Entry = {
			label = call.label,
			tool = call.tool,
			requestSha256 = call.requestSha256,
			status = "ambiguous",
			request = reference(path :: string, bytes, host.sha256),
		}
		table.insert(transcript.entries, entry)
		local returned, response = pcall(host.call, call.tool, call.arguments)
		if not returned or type(response) ~= "string" then
			entry.detail = "call outcome unknown: " .. tostring(response)
			transcript.status = "stopped"
			return transcript
		end
		local saved, responsePath = pcall(host.writeNew, stem .. ".response.json", response :: string)
		if not saved then
			entry.detail = "response could not be retained: " .. tostring(responsePath)
			transcript.status = "stopped"
			return transcript
		end
		entry.response = reference(responsePath :: string, response :: string, host.sha256)
		local decodedOk, decoded = pcall(host.decode, response :: string)
		local item, problem = content(call.tool, if decodedOk then decoded else nil)
		if item == nil then
			entry.status = "failed"
			entry.detail = problem or "response is not decodable"
			transcript.status = "stopped"
			return transcript
		end
		local found = item :: Content
		if found.kind == "image" then
			local extension = if found.mediaType == "image/png" then ".png" else ".jpg"
			local imageSaved, imagePath = pcall(host.writeNew, stem .. extension, found.bytes)
			if not imageSaved then
				entry.detail = "image could not be retained: " .. tostring(imagePath)
				transcript.status = "stopped"
				return transcript
			end
			entry.image = reference(imagePath :: string, found.bytes, host.sha256)
		end
		entry.status = "returned"
	end
	return transcript
end

local function readReference(label: string, value: unknown, cap: number, host: ReadHost): string
	demand(type(value) == "table", label .. " file reference missing")
	local ref = value :: FileReference
	demand(
		type(ref.path) == "string" and type(ref.byteCount) == "number" and digest(ref.sha256),
		label .. " file reference malformed"
	)
	demand(ref.byteCount <= cap, label .. " exceeds its size cap")
	local bytes = host.readFile(ref.path)
	demand(#bytes == ref.byteCount and #bytes <= cap, label .. " size drift")
	demand(host.sha256(bytes) == ref.sha256, label .. " hash drift")
	return bytes
end

local function verify(plan: BoundPlan, transcript: Transcript, host: ReadHost, caps: Caps): Verified
	checkPlan(plan, host.sha256)
	demand(type(caps) == "table", "requires explicit size caps")
	demand(
		type(transcript) == "table" and transcript.schema == TRANSCRIPT_SCHEMA,
		"requires a " .. TRANSCRIPT_SCHEMA .. " transcript"
	)
	demand(transcript.planSha256 == plan.planSha256, "transcript belongs to another plan")
	demand(transcript.artifactDigest == plan.artifactDigest, "artifact digest drift")
	demand(transcript.studioId == plan.studioId, "Studio binding drift")
	demand(transcript.status == "complete", "transcript stopped before completion")
	demand(#transcript.entries == #plan.calls, "transcript is missing a declared call")
	local excluded: { [string]: boolean } = {}
	for _, sha in caps.excludedImages or ({} :: { string }) do
		excluded[sha] = true
	end
	local verified: Verified = { results = {}, images = {} }
	for index, call in plan.calls do
		local entry = transcript.entries[index]
		demand(
			entry.label == call.label and entry.tool == call.tool and entry.requestSha256 == call.requestSha256,
			"call order drift at " .. call.label
		)
		demand(entry.status == "returned", "call did not return: " .. call.label)
		local request = readReference(call.label .. " request", entry.request, caps.requestBytes, host)
		demand(request == requestBytes(call), "request bytes drift: " .. call.label)
		local response = readReference(call.label .. " response", entry.response, caps.responseBytes, host)
		local decodedOk, decoded = pcall(host.decode, response)
		local item, problem = content(call.tool, if decodedOk then decoded else nil)
		demand(item ~= nil, call.label .. ": " .. tostring(problem))
		local found = item :: Content
		if found.kind == "text" then
			demand(entry.image == nil, "execute_luau carries an image: " .. call.label)
			verified.results[call.label] = found.text
		else
			local bytes = readReference(call.label .. " image", entry.image, caps.imageBytes, host)
			demand(bytes == found.bytes, "image file differs from the response: " .. call.label)
			local sha = (entry.image :: FileReference).sha256
			demand(not excluded[sha], "capture reused: " .. call.label)
			excluded[sha] = true
			verified.images[call.label] = {
				path = (entry.image :: FileReference).path,
				sha256 = sha,
				byteCount = #bytes,
				mediaType = found.mediaType :: "image/png" | "image/jpeg",
			}
		end
	end
	return verified
end

return {
	prepare = prepare,
	execute = execute,
	verify = verify,
	requestBytes = requestBytes,
}
