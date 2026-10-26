--!strict

local crypto = require "@lute/crypto"
local json = require "@std/json"

local Roblox = require "../src/roblox"
local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local NativeTranscript = Roblox.nativeTranscript

local function sha256(bytes: string): string
	local digest = crypto.digest(crypto.hash.sha256, bytes)
	local pieces: { string } = {}
	for index = 0, buffer.len(digest) - 1 do
		table.insert(pieces, string.format("%02x", buffer.readu8(digest, index)))
	end
	return table.concat(pieces)
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64(bytes: string): string
	local pieces: { string } = {}
	for index = 1, #bytes, 3 do
		local a, b, c = string.byte(bytes, index, index + 2)
		local packed = (a :: number) * 65536 + (b or 0) * 256 + (c or 0)
		local chunk = ""
		for shift = 18, 0, -6 do
			local value = bit32.band(bit32.rshift(packed, shift), 63)
			chunk ..= string.sub(ALPHABET, value + 1, value + 1)
		end
		if c == nil then
			chunk = string.sub(chunk, 1, 3) .. "="
		end
		if b == nil then
			chunk = string.sub(chunk, 1, 2) .. "=="
		end
		table.insert(pieces, chunk)
	end
	return table.concat(pieces)
end

local STUDIO = "studio-fixture"
local ARTIFACT = sha256 "retained fixture bundle"
local PNG = "\137PNG\r\n\26\n" .. "fixture restored frame"
local OTHER_PNG = "\137PNG\r\n\26\n" .. "fixture second frame"
local JPEG = "\255\216\255\224" .. "fixture jpeg frame"
local CAPS = { requestBytes = 65536, responseBytes = 65536, imageBytes = 65536 }

local codec = {
	encode = function(value: unknown): string
		return json.serialize(value :: json.Value)
	end,
	sha256 = sha256,
}

local function textResult(text: string): string
	return json.serialize { isError = false, content = { { type = "text", text = text } } }
end

local function imageResult(bytes: string, mimeType: string): string
	return json.serialize { isError = false, content = { { type = "image", data = base64(bytes), mimeType = mimeType } } }
end

local function plan(extraCapture: boolean?)
	local calls: { Roblox.NativeCallDraft } = {
		{ label = "construct", tool = "execute_luau", arguments = { studio_id = STUDIO, code = "return 1" } },
		{ label = "readback", tool = "execute_luau", arguments = { studio_id = STUDIO, code = "return 2" } },
		{ label = "front", tool = "screen_capture", arguments = { studio_id = STUDIO, capture_id = "front" } },
	}
	if extraCapture then
		table.insert(
			calls,
			{ label = "side", tool = "screen_capture", arguments = { studio_id = STUDIO, capture_id = "side" } }
		)
	end
	return NativeTranscript.prepare({
		artifactDigest = ARTIFACT,
		studio = { studioId = STUDIO, placeId = "1", engineVersion = "fixture" },
	}, calls, codec)
end

type Fixture = {
	files: { [string]: string },
	calls: { string },
	replies: { [string]: () -> string },
	host: Roblox.NativeExecuteHost,
}

local function fixture(): Fixture
	local self: { files: { [string]: string }, calls: { string }, replies: { [string]: () -> string } } =
		{ files = {}, calls = {}, replies = {} }
	self.replies.construct = function()
		return textResult "constructed"
	end
	self.replies.readback = function()
		return textResult "readback"
	end
	self.replies.front = function()
		return imageResult(PNG, "image/png")
	end
	self.replies.side = function()
		return imageResult(OTHER_PNG, "image/png")
	end
	local host: Roblox.NativeExecuteHost = {
		call = function(tool, argumentsBytes)
			local arguments = json.deserialize(argumentsBytes) :: { capture_id: string?, code: string? }
			local label = if tool == "screen_capture"
				then arguments.capture_id :: string
				else (if arguments.code == "return 1" then "construct" else "readback")
			table.insert(self.calls, label)
			return self.replies[label]()
		end,
		writeNew = function(name, bytes)
			local path = "bank/" .. name
			assert(self.files[path] == nil, "exists: " .. path)
			self.files[path] = bytes
			return path
		end,
		readFile = function(path)
			return assert(self.files[path], "missing: " .. path)
		end,
		sha256 = sha256,
		decode = function(bytes)
			return json.deserialize(bytes)
		end,
	}
	return { files = self.files, calls = self.calls, replies = self.replies, host = host }
end

local function readHost(self: Fixture): Roblox.NativeReadHost
	return { readFile = self.host.readFile, sha256 = sha256, decode = self.host.decode }
end

describe("native transcript", function()
	it("binds the plan grant to exact request digests", function()
		local bound = plan()
		expect(bound.schema):toEqual "generate.roblox.native-plan.v1"
		expect(#bound.grant):toEqual(3)
		for index, call in bound.calls do
			expect(bound.grant[index]):toEqual(sha256(NativeTranscript.requestBytes(call)))
		end
	end)

	it("executes each call once, retains bytes and verifies results and images", function()
		local bound = plan()
		local self = fixture()
		local transcript = NativeTranscript.execute(bound, self.host)
		expect(transcript.status):toEqual "complete"
		expect(self.calls):toEqual { "construct", "readback", "front" }
		local verified = NativeTranscript.verify(bound, transcript, readHost(self), CAPS)
		expect(verified.results.construct):toEqual "constructed"
		expect(verified.results.readback):toEqual "readback"
		expect(verified.images.front.mediaType):toEqual "image/png"
		expect(self.files[verified.images.front.path]):toEqual(PNG)
	end)

	it("refuses a transcript missing a declared call", function()
		local bound = plan()
		local self = fixture()
		local transcript = NativeTranscript.execute(bound, self.host)
		table.remove(transcript.entries)
		expect(function()
			NativeTranscript.verify(bound, transcript, readHost(self), CAPS)
		end):toThrow "missing a declared call"
	end)

	it("refuses artifact digest drift in the plan or the transcript", function()
		local bound = plan()
		local self = fixture()
		local transcript = NativeTranscript.execute(bound, self.host)
		local edited = table.clone(bound)
		edited.artifactDigest = sha256 "another bundle"
		expect(function()
			NativeTranscript.verify(edited, transcript, readHost(self), CAPS)
		end):toThrow "plan digest drift"
		local moved = table.clone(transcript)
		moved.artifactDigest = sha256 "another bundle"
		expect(function()
			NativeTranscript.verify(bound, moved, readHost(self), CAPS)
		end):toThrow "artifact digest drift"
		self.files[assert(transcript.entries[2].response).path] = textResult "readbacX"
		expect(function()
			NativeTranscript.verify(bound, transcript, readHost(self), CAPS)
		end):toThrow "hash drift"
	end)

	it("refuses a reused capture", function()
		local bound = plan(true)
		local self = fixture()
		self.replies.side = self.replies.front
		local transcript = NativeTranscript.execute(bound, self.host)
		expect(transcript.status):toEqual "complete"
		expect(function()
			NativeTranscript.verify(bound, transcript, readHost(self), CAPS)
		end):toThrow "capture reused"
		local fresh = fixture()
		local single = plan()
		local original = NativeTranscript.execute(single, fresh.host)
		local caps = table.clone(CAPS)
		caps.excludedImages = { sha256(PNG) }
		expect(function()
			NativeTranscript.verify(single, original, readHost(fresh), caps)
		end):toThrow "capture reused"
	end)

	it("refuses Studio binding drift", function()
		expect(function()
			NativeTranscript.prepare({ artifactDigest = ARTIFACT, studio = { studioId = STUDIO } }, {
				{ label = "elsewhere", tool = "execute_luau", arguments = { studio_id = "other", code = "return 1" } },
			}, codec)
		end):toThrow "targets another Studio"
		local bound = plan()
		local self = fixture()
		local transcript = NativeTranscript.execute(bound, self.host)
		local moved = table.clone(transcript)
		moved.studioId = "other"
		expect(function()
			NativeTranscript.verify(bound, moved, readHost(self), CAPS)
		end):toThrow "Studio binding drift"
		local rebound = table.clone(bound)
		rebound.studio = { studioId = "other" }
		rebound.studioId = "other"
		expect(function()
			NativeTranscript.verify(rebound, transcript, readHost(self), CAPS)
		end):toThrow "drift"
	end)

	it("refuses a wrong image media type and an image file that differs from the response", function()
		local bound = plan()
		local self = fixture()
		self.replies.front = function()
			return imageResult(PNG, "image/jpeg")
		end
		local transcript = NativeTranscript.execute(bound, self.host)
		expect(transcript.status):toEqual "stopped"
		expect(transcript.entries[3].status):toEqual "failed"
		expect(transcript.entries[3].detail):toEqual "screen_capture media type mismatch"
		local fresh = fixture()
		fresh.replies.front = function()
			return imageResult(JPEG, "image/jpeg")
		end
		local complete = NativeTranscript.execute(bound, fresh.host)
		local image = assert(complete.entries[3].image)
		fresh.files[image.path] = PNG
		image.sha256 = sha256(PNG)
		image.byteCount = #PNG
		expect(function()
			NativeTranscript.verify(bound, complete, readHost(fresh), CAPS)
		end):toThrow "differs from the response"
	end)

	it("stops at the first failed call without invoking later calls", function()
		local bound = plan()
		local self = fixture()
		self.replies.construct = function()
			return json.serialize { isError = true, content = { { type = "text", text = "boom" } } }
		end
		local transcript = NativeTranscript.execute(bound, self.host)
		expect(transcript.status):toEqual "stopped"
		expect(self.calls):toEqual { "construct" }
		expect(#transcript.entries):toEqual(1)
		expect(function()
			NativeTranscript.verify(bound, transcript, readHost(self), CAPS)
		end):toThrow "stopped before completion"
	end)

	it("records an ambiguous result and refuses a retry of the same plan", function()
		local bound = plan()
		local self = fixture()
		self.replies.readback = function(): string
			error "transport closed after send"
		end
		local transcript = NativeTranscript.execute(bound, self.host)
		expect(transcript.status):toEqual "stopped"
		expect(transcript.entries[2].status):toEqual "ambiguous"
		expect(self.calls):toEqual { "construct", "readback" }
		self.replies.readback = function()
			return textResult "readback"
		end
		expect(function()
			NativeTranscript.execute(bound, self.host)
		end):toThrow "refuses to overwrite or retry"
		expect(self.calls):toEqual { "construct", "readback" }
	end)

	it("enforces declared size caps", function()
		local bound = plan()
		local self = fixture()
		local transcript = NativeTranscript.execute(bound, self.host)
		local caps = table.clone(CAPS)
		caps.imageBytes = #PNG - 1
		expect(function()
			NativeTranscript.verify(bound, transcript, readHost(self), caps)
		end):toThrow "size cap"
	end)
end)

return nil
