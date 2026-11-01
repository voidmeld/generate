--!strict

local json = require "@std/json"
local Lute = require "../.lute/dependencies/verify/src/lute"
local Test = require "./harness"
local Wire = require "../src/roblox/wire"
local Readback = require "../src/roblox/asset-readback"
local Permission = require "../src/roblox/permission-request"

local describe, it, expect = Test.describe, Test.it, Test.expect
local OWNER: Readback.Owner = { creatorType = "Group", creatorId = "4242" }

local function decode(body: string): unknown
	return json.deserialize(body)
end

describe("cloud response contracts", function()
	it("orders and bounds permission chunks before preparing an exact request", function()
		expect(Permission.chunks({ "9", "2", "11" }, 2)):toEqual { { "11", "2" }, { "9" } }
		expect(function()
			Permission.chunks({ "2", "2" }, 2)
		end):toThrow "duplicate asset id"
		expect(function()
			Permission.chunks({ "2" }, Permission.MAX_ASSETS_PER_REQUEST + 1)
		end):toThrow "asset bound"
		local request = Permission.prepare(Lute.encode, 123, { "88", "77" })
		expect(request.requestedAssetIds):toEqual { "77", "88" }
		local calls = 0
		local answer = Permission.attempt(function(sent: Wire.AuthorizedRequest): Wire.Response
			calls += 1
			expect(sent.method):toBe "PATCH"
			expect(sent.body):toBe(request.body)
			return { ok = true, status = 200, body = '{"successAssetIds":[88,77],"errors":[]}' }
		end, decode, request)
		expect(calls):toBe(1)
		expect(answer.granted):toBe(true)
		expect(answer.successAssetIds):toEqual { "77", "88" }
	end)

	it("stops an unauthenticated read without retry or public fallback", function()
		local reads, sleeps, publicReads = 0, 0, 0
		local result = Readback.readback({
			owner = OWNER,
			decode = decode,
			send = function(): Wire.Response
				reads += 1
				return { ok = false, status = 401, body = "unauthenticated" }
			end,
			sleep = function()
				sleeps += 1
			end,
			sendPublic = function(): Wire.Response
				publicReads += 1
				return { ok = true, status = 200, body = "{}" }
			end,
		}, "77")
		expect(reads):toBe(1)
		expect(sleeps):toBe(0)
		expect(publicReads):toBe(0)
		expect(result.status):toBe(401)
		expect(result.ownedByDeclaredCreator):toBe(false)
	end)

	it("uses a bounded reset header and preserves unknown ownership after throttling", function()
		local sleeps: { number } = {}
		local reads = 0
		local result = Readback.readback({
			owner = OWNER,
			decode = decode,
			send = function(): Wire.Response
				reads += 1
				if reads == 1 then
					return { ok = false, status = 429, body = "", headers = { ["X-RateLimit-Reset"] = "900" } }
				end
				return { ok = true, status = 200, body = '{"assetId":"77"}' }
			end,
			sleep = function(seconds: number)
				table.insert(sleeps, seconds)
			end,
		}, "77")
		expect(reads):toBe(2)
		expect(sleeps[1]):toBe(60)
		expect(result.ownedByDeclaredCreator):toBe(false)
		expect(result.moderationState):toBe "unknown"
	end)

	it("ignores malformed reset values and retains the retry bound", function()
		local reads = 0
		local sleeps: { number } = {}
		local result = Readback.readback({
			owner = OWNER,
			decode = decode,
			maxRetries = 1,
			send = function(): Wire.Response
				reads += 1
				return { ok = false, status = 503, body = "", headers = { ["x-ratelimit-reset"] = {} } }
			end,
			sleep = function(seconds: number)
				table.insert(sleeps, seconds)
			end,
		}, "77")
		expect(reads):toBe(2)
		expect(#sleeps):toBe(1)
		expect(sleeps[1]):toBe(1)
		expect(result.status):toBe(503)
	end)

	it("compares the entire ordered array without ignoring extra or sparse entries", function()
		expect(Wire.sameIds({ "77", "88" }, { "77", "88" })):toBe(true)
		expect(Wire.sameIds({ "88", "77" }, { "77", "88" })):toBe(false)
		expect(Wire.sameIds({ [1] = "77", [3] = "88" }, { "77" })):toBe(false)
		expect(Wire.sameIds({ [1] = "77", extra = "88" }, { "77" })):toBe(false)
	end)

	it("refuses an asset id that numeric request construction would round", function()
		local encodes = 0
		expect(function()
			Permission.prepare(function(): string
				encodes += 1
				return "{}"
			end, 123, { "9007199254740993" })
		end):toThrow "positive numeric asset ids"
		expect(encodes):toBe(0)
	end)

	it("retains the HTTP result when the permission response is malformed JSON", function()
		local reads = 0
		local request: Permission.Request = {
			endpoint = Permission.ENDPOINT,
			method = "PATCH",
			headerNames = {},
			body = "{}",
			universeId = 123,
			requestedAssetIds = { "77" },
		}
		local result = Permission.attempt(function(): Wire.Response
			reads += 1
			return { ok = true, status = 200, body = "malformed" }
		end, decode, request)
		expect(reads):toBe(1)
		expect(result.granted):toBe(false)
		expect(result.status):toBe(200)
		expect(result.responseBody):toBe "malformed"
		expect(result.diagnostic):toContain "unreadable permission response"
	end)
end)

return nil
