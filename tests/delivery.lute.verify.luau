--!strict

local crypto = require "@lute/crypto"
local json = require "@std/json"
local Lute = require "../.lute/dependencies/verify/src/lute"

local Roblox = require "../src/roblox"
local Test = require "./harness"
local field = require("../src/roblox/wire").field

local describe, it, expect = Test.describe, Test.it, Test.expect

local Delivery = Roblox.delivery

local function sha256(bytes: string): string
	local digest = crypto.digest(crypto.hash.sha256, bytes)
	local pieces: { string } = {}
	for index = 0, buffer.len(digest) - 1 do
		table.insert(pieces, string.format("%02x", buffer.readu8(digest, index)))
	end
	return table.concat(pieces)
end

local SECRET = "fixture-secret-value"
local BYTES = "\137PNG\r\n\26\n\0original bytes\255"
local DIGEST = sha256(BYTES)
local GROUP: Roblox.DeliveryCreator = { kind = "group", id = "1234567" }

type Scripted = { throws: string?, status: number?, body: string?, failure: "unknown" | "unsent"?, detail: string? }
type Script = { Scripted }

type Rig = {
	config: Roblox.DeliveryConfig,
	requests: { Roblox.DeliveryRequest },
	records: { [string]: Roblox.DeliveryRecord },
	posts: () -> number,
	waits: { number },
	push: (reply: Scripted) -> (),
}

local function approvedAsset(creator: { groupId: string?, userId: string? }?, state: string?): Scripted
	return {
		status = 200,
		body = Lute.encode {
			assetId = "12345",
			revisionId = "7",
			assetType = "Image",
			creationContext = { creator = creator or { groupId = "1234567" } },
			moderationResult = { moderationState = state or "Approved" },
		},
	}
end

local function operationDone(): Scripted
	return { status = 200, body = Lute.encode { done = true, response = { assetId = "12345" } } }
end

local function created(): Scripted
	return { status = 200, body = Lute.encode { path = "operations/1234-abcd" } }
end

local function rig(options: { creator: Roblox.DeliveryCreator?, polls: number? }?): Rig
	local opts: { creator: Roblox.DeliveryCreator?, polls: number? } = options or {}
	local requests: { Roblox.DeliveryRequest } = {}
	local records: { [string]: Roblox.DeliveryRecord } = {}
	local replies: Script = {}
	local waits: { number } = {}
	local clock = 0
	local value: Rig = {
		requests = requests,
		records = records,
		waits = waits,
		push = function(reply: Scripted)
			table.insert(replies, reply)
		end,
		posts = function()
			local count = 0
			for _, request in requests do
				if request.method == "POST" then
					count += 1
				end
			end
			return count
		end,
		config = {
			creator = opts.creator or GROUP,
			polls = opts.polls or 1,
			interval = 30,
			sha256 = sha256,
			json = {
				encode = function(value: unknown): string
					return Lute.encode(value)
				end,
				decode = json.deserialize,
			},
			now = function()
				return clock
			end,
			wait = function(seconds: number)
				table.insert(waits, seconds)
				clock += seconds
			end,
			headers = function()
				return { ["x-api-key"] = SECRET }
			end,
			store = {
				read = function(key)
					return records[key]
				end,
				create = function(key, record)
					if records[key] then
						return false
					end
					records[key] = record
					return true
				end,
				write = function(key, record)
					records[key] = record
				end,
			},
			send = function(request)
				table.insert(requests, request)
				expect(request.headers["x-api-key"]):toBe(SECRET)
				local reply = table.remove(replies, 1)
				if reply == nil then
					error("no scripted reply for " .. request.method .. " " .. request.url)
				end
				if reply.throws then
					error(reply.throws)
				end
				if reply.failure ~= nil then
					return { failure = reply.failure, detail = assert(reply.detail) }
				end
				return { status = assert(reply.status), body = assert(reply.body) }
			end,
		},
	}
	return value
end

local function review(): Roblox.DeliveryReview
	return { by = "reviewer", verdict = "complies", shows = "a plain fixture square", sha256 = DIGEST }
end

local function request(): Roblox.DeliveryUpload
	return { label = "icons/fixture.png", bytes = BYTES, name = "fixture", format = "png", review = review() }
end

describe("file upload", function()
	local modelFormats: { [string]: string } =
		{ fbx = "model/fbx", gltf = "model/gltf+json", glb = "model/gltf-binary" }
	for format, contentType in modelFormats do
		it("delivers reviewed " .. format .. " model bytes and resumes the same operation", function()
			local r = rig()
			local model = request()
			model.label = "models/fixture." .. format
			model.format = format
			r.push(created())
			r.push { status = 200, body = Lute.encode { done = false } }
			expect(Delivery.upload(r.config, model).reason):toBe "pending"
			local body = assert(r.requests[1].body)
			expect(string.find(body, 'filename="asset.' .. format .. '"', 1, true) ~= nil):toBe(true)
			expect(string.find(body, "Content-Type: " .. contentType .. "\r\n", 1, true) ~= nil):toBe(true)
			expect(string.find(body, BYTES, 1, true) ~= nil):toBe(true)
			local envelope = json.deserialize(assert(string.match(body, "application/json\r\n\r\n(.-)\r\n%-%-")))
			expect(field(envelope, "assetType")):toBe "Model"
			r.push(operationDone())
			r.push {
				status = 200,
				body = Lute.encode {
					assetId = "12345",
					revisionId = "7",
					assetType = "Model",
					creationContext = { creator = { groupId = "1234567" } },
					moderationResult = { moderationState = "Approved" },
				},
			}
			local settled = Delivery.upload(r.config, model)
			expect(settled.verdict):toBe "approved"
			expect(settled.assetId):toBe "12345"
			expect(settled.version):toBe "7"
			expect(r.posts()):toBe(1)
		end)
	end

	local function instanceRequest(assetType: string?): Roblox.DeliveryUpload
		local value = request()
		value.label = "models/fixture.rbxm"
		value.format = "rbxm"
		value.assetType = assetType
		return value
	end

	local function readback(assetType: string): Scripted
		return {
			status = 200,
			body = Lute.encode {
				assetId = "12345",
				revisionId = "7",
				assetType = assetType,
				creationContext = { creator = { groupId = "1234567" } },
				moderationResult = { moderationState = "Approved" },
			},
		}
	end

	local function envelopeOf(body: string): unknown
		return json.deserialize(assert(string.match(body, "application/json\r\n\r\n(.-)\r\n%-%-")))
	end

	it("sends rbxm as an Animation under the bare digest key when no asset type is given", function()
		local r = rig()
		r.push(created())
		r.push { status = 200, body = Lute.encode { done = false } }
		expect(Delivery.upload(r.config, instanceRequest(nil)).reason):toBe "pending"
		local body = assert(r.requests[1].body)
		expect(field(envelopeOf(body), "assetType")):toBe "Animation"
		expect(string.find(body, "Content-Type: model/x-rbxm\r\n", 1, true) ~= nil):toBe(true)
		expect(assert(r.records[DIGEST]).assetType):toBe "Animation"
		expect(Delivery.key("rbxm", DIGEST, nil)):toBe(DIGEST)
		expect(Delivery.key("rbxm", DIGEST, "Animation")):toBe(DIGEST)
		expect(Delivery.key("rbxmx", DIGEST, "Model")):toBe(DIGEST .. "_Model")
		expect(Delivery.key("rbxm", DIGEST, "Mesh")):toBeNil()
		expect(Delivery.key("png", DIGEST, nil)):toBe(DIGEST)
	end)

	for _, format in { "rbxm", "rbxmx" } do
		it("sends " .. format .. " as a Model under its own key", function()
			local r = rig()
			local model = instanceRequest "Model"
			model.format = format
			r.push(created())
			r.push { status = 200, body = Lute.encode { done = false } }
			expect(Delivery.upload(r.config, model).reason):toBe "pending"
			local body = assert(r.requests[1].body)
			expect(string.find(body, '"assetType":"Model"', 1, true) ~= nil):toBe(true)
			expect(string.find(body, "Content-Type: model/x-rbxm\r\n", 1, true) ~= nil):toBe(true)
			expect(r.records[DIGEST]):toBeNil()
			expect(assert(r.records[DIGEST .. "_Model"]).assetType):toBe "Model"
			r.push(operationDone())
			r.push(readback "Model")
			local settled = Delivery.upload(r.config, model)
			expect(settled.verdict):toBe "approved"
			expect(r.posts()):toBe(1)
		end)
	end

	it("delivers bytes already recorded as an Animation as a Model without touching that record", function()
		local r = rig()
		r.push(created())
		r.push(operationDone())
		r.push(readback "Animation")
		expect(Delivery.upload(r.config, instanceRequest(nil)).verdict):toBe "approved"
		local animation = assert(r.records[DIGEST])
		local before = Lute.encode(animation)
		r.push(created())
		r.push(operationDone())
		r.push(readback "Model")
		local model = Delivery.upload(r.config, instanceRequest "Model")
		expect(model.verdict):toBe "approved"
		expect(r.posts()):toBe(2)
		expect(Lute.encode(r.records[DIGEST])):toBe(before)
		expect(assert(r.records[DIGEST .. "_Model"]).assetType):toBe "Model"
		r.push(readback "Animation")
		expect(Delivery.upload(r.config, instanceRequest(nil)).verdict):toBe "approved"
		expect(r.posts()):toBe(2)
	end)

	it("stops a Model readback that reports a different type", function()
		local r = rig()
		r.push(created())
		r.push(operationDone())
		r.push(readback "Animation")
		local outcome = Delivery.upload(r.config, instanceRequest "Model")
		expect(outcome.reason):toBe "identity"
	end)

	it("resolves an ambiguous Model upload through the derived key", function()
		local r = rig()
		r.push { throws = "connection reset" }
		expect(Delivery.upload(r.config, instanceRequest "Model").reason):toBe "ambiguous"
		local derived = assert(Delivery.key("rbxm", DIGEST, "Model"))
		r.push(operationDone())
		r.push(readback "Model")
		local resolved = Delivery.attach(r.config, derived, { operation = "operations/aaaa-0001" })
		expect(resolved.verdict):toBe "approved"
		expect(r.posts()):toBe(1)
	end)

	it("refuses an unsupported asset type before any send", function()
		local cases: { { format: string, assetType: string } } = {
			{ format = "png", assetType = "Model" },
			{ format = "rbxm", assetType = "Mesh" },
			{ format = "rbxmx", assetType = "Image" },
			{ format = "fbx", assetType = "Animation" },
		}
		for _, case in cases do
			local r = rig()
			local value = instanceRequest(case.assetType)
			value.format = case.format
			local outcome = Delivery.upload(r.config, value)
			expect(outcome.verdict):toBe "stop"
			expect(outcome.reason):toBe "invalid"
			expect(#r.requests):toBe(0)
		end
	end)

	it("accepts the single type of another format when it is named", function()
		local r = rig()
		local value = request()
		value.assetType = "Image"
		r.push(created())
		r.push(operationDone())
		r.push(approvedAsset())
		expect(Delivery.upload(r.config, value).verdict):toBe "approved"
		expect(r.records[DIGEST] ~= nil):toBe(true)
	end)

	it("holds malformed readback field shapes without approving delivery", function()
		local cases: { { field: string, value: unknown } } = {
			{ field = "creationContext", value = "context" },
			{ field = "creationContext", value = { creator = false } },
			{ field = "creationContext", value = { creator = { groupId = false } } },
			{ field = "assetType", value = 12 },
			{ field = "moderationResult", value = "Approved" },
			{ field = "moderationResult", value = { moderationState = false } },
		}
		for _, case in cases do
			local r = rig()
			local body: { [string]: unknown } = {
				assetId = "12345",
				assetType = "Image",
				creationContext = { creator = { groupId = "1234567" } },
				moderationResult = { moderationState = "Approved" },
			}
			body[case.field] = case.value
			r.push(created())
			r.push(operationDone())
			r.push { status = 200, body = Lute.encode(body) }
			local outcome = Delivery.upload(r.config, request())
			expect(outcome.verdict):toBe "hold"
			expect(outcome.reason):toBe "malformed"
			expect(r.posts()):toBe(1)
		end
	end)

	it("sends once, polls the operation and returns the approved asset with provenance", function()
		local r = rig()
		r.push(created())
		r.push(operationDone())
		r.push(approvedAsset())
		local outcome = Delivery.upload(r.config, request())
		expect(outcome.verdict):toBe "approved"
		expect(outcome.assetId):toBe "12345"
		expect(outcome.version):toBe "7"
		expect(r.posts()):toBe(1)
		local post = r.requests[1]
		expect(post.url):toBe "https://apis.roblox.com/assets/v1/assets"
		local envelope = json.deserialize(assert(string.match(post.body or "", "application/json\r\n\r\n(.-)\r\n%-%-")))
		expect(field(field(field(envelope, "creationContext"), "creator"), "groupId")):toBe "1234567"
		expect(field(field(field(envelope, "creationContext"), "creator"), "userId")):toBeNil()
		expect(field(field(envelope, "creationContext"), "assetPrivacy")):toBe "restricted"
		expect(string.find(post.body or "", BYTES, 1, true) ~= nil):toBe(true)
		local record = r.records[DIGEST]
		expect(record.sha256):toBe(DIGEST)
		expect(record.source):toBe "icons/fixture.png"
		expect(assert(record.review).by):toBe "reviewer"
		expect(record.operation):toBe "operations/1234-abcd"
		expect(record.assetId):toBe "12345"
		expect(record.version):toBe "7"
		expect((string.find(Lute.encode(record), SECRET, 1, true))):toBeNil()
	end)

	it("addresses a user creator only when the consumer names one and never falls back", function()
		local r = rig { creator = { kind = "user", id = "42" } }
		r.push(created())
		r.push(operationDone())
		r.push(approvedAsset { userId = "42" })
		expect(Delivery.upload(r.config, request()).verdict):toBe "approved"
		local envelope =
			json.deserialize(assert(string.match(r.requests[1].body or "", "application/json\r\n\r\n(.-)\r\n%-%-")))
		expect(field(field(field(envelope, "creationContext"), "creator"), "userId")):toBe "42"
		expect(field(field(field(envelope, "creationContext"), "creator"), "groupId")):toBeNil()
		local missing = rig { creator = { kind = "group", id = "" } }
		local outcome = Delivery.upload(missing.config, request())
		expect(outcome.reason):toBe "invalid"
		expect(#missing.requests):toBe(0)
	end)

	it("stops on a moderation rejection", function()
		local r = rig()
		r.push(created())
		r.push(operationDone())
		r.push(approvedAsset(nil, "Rejected"))
		local outcome = Delivery.upload(r.config, request())
		expect(outcome.verdict):toBe "stop"
		expect(outcome.reason):toBe "rejected"
		expect(outcome.retry):toBe "never"
	end)

	it("stops on a moderated-account 403 and never sends these bytes again", function()
		local r = rig()
		r.push { status = 403, body = '{"message":"User is moderated"}' }
		local outcome = Delivery.upload(r.config, request())
		expect(outcome.verdict):toBe "stop"
		expect(outcome.reason):toBe "refused"
		expect(r.records[DIGEST].attempt):toBe "refused"
		local again = Delivery.upload(r.config, request())
		expect(again.reason):toBe "refused"
		expect(r.posts()):toBe(1)
	end)

	it("treats a failure before send as safe to retry", function()
		local r = rig()
		r.push { failure = "unsent", detail = "no route to host" }
		local first = Delivery.upload(r.config, request())
		expect(first.verdict):toBe "hold"
		expect(first.reason):toBe "remote_unreachable"
		expect(first.retry):toBe "safe"
		r.push(created())
		r.push(operationDone())
		r.push(approvedAsset())
		expect(Delivery.upload(r.config, request()).verdict):toBe "approved"
		expect(r.posts()):toBe(2)
	end)

	it("treats a rate limit as safe to retry", function()
		local r = rig()
		r.push { status = 429, body = "" }
		local outcome = Delivery.upload(r.config, request())
		expect(outcome.reason):toBe "rate_limited"
		expect(outcome.retry):toBe "safe"
	end)

	it("holds a failure after send as ambiguous, redacts the secret and resolves only by status", function()
		local r = rig()
		r.push { throws = "connection reset while sending " .. SECRET }
		local first = Delivery.upload(r.config, request())
		expect(first.verdict):toBe "stop"
		expect(first.reason):toBe "ambiguous"
		expect((string.find(first.detail or "", SECRET, 1, true))):toBeNil()
		local second = Delivery.upload(r.config, request())
		expect(second.reason):toBe "ambiguous"
		expect(r.posts()):toBe(1)
		r.push(operationDone())
		r.push(approvedAsset())
		local resolved = Delivery.attach(r.config, DIGEST, { operation = "operations/aaaa-0001" })
		expect(resolved.verdict):toBe "approved"
		expect(r.posts()):toBe(1)
		expect(r.records[DIGEST].attempt):toBe "resolved"
	end)

	it("redacts credentials from a failure reply built by the transport", function()
		local r = rig()
		r.push { failure = "unknown", detail = "reset: " .. SECRET }
		local outcome = Delivery.upload(r.config, request())
		expect(outcome.reason):toBe "ambiguous"
		expect((string.find(outcome.detail or "", SECRET, 1, true))):toBeNil()
	end)

	it("treats a server error as ambiguous", function()
		local r = rig()
		r.push { status = 502, body = "" }
		local outcome = Delivery.upload(r.config, request())
		expect(outcome.reason):toBe "ambiguous"
		expect(Delivery.upload(r.config, request()).reason):toBe "ambiguous"
		expect(r.posts()):toBe(1)
	end)

	it("resumes an interrupted upload from its operation without a second create", function()
		local r = rig { polls = 3 }
		r.push(created())
		r.push { status = 200, body = Lute.encode { done = false } }
		r.push { status = 200, body = Lute.encode { done = false } }
		r.push { status = 200, body = Lute.encode { done = false } }
		local first = Delivery.upload(r.config, request())
		expect(first.verdict):toBe "hold"
		expect(first.reason):toBe "pending"
		expect(first.retry):toBe "poll"
		expect(r.waits):toEqual { 30, 30 }
		r.push(operationDone())
		r.push(approvedAsset())
		local second = Delivery.upload(r.config, request())
		expect(second.verdict):toBe "approved"
		expect(r.posts()):toBe(1)
	end)

	it("holds while moderation is pending and stops on a foreign creator", function()
		local pending = rig()
		pending.push(created())
		pending.push(operationDone())
		pending.push(approvedAsset(nil, "Reviewing"))
		expect(Delivery.upload(pending.config, request()).reason):toBe "pending"
		local foreign = rig()
		foreign.push(created())
		foreign.push(operationDone())
		foreign.push(approvedAsset { userId = "9" })
		expect(Delivery.upload(foreign.config, request()).reason):toBe "identity"
	end)

	it("refuses unreviewed, mismatched and unsupported input before any request", function()
		local r = rig()
		local mismatched = request()
		mismatched.review.sha256 = string.rep("0", 64)
		expect(Delivery.upload(r.config, mismatched).reason):toBe "unreviewed"
		local denied = request()
		denied.review.verdict = "unsure"
		expect(Delivery.upload(r.config, denied).reason):toBe "unreviewed"
		local gif = request()
		gif.format = "gif"
		expect(Delivery.upload(r.config, gif).reason):toBe "invalid"
		r.config.authorize = function()
			return nil, "not the recorded operator"
		end
		expect(Delivery.upload(r.config, request()).reason):toBe "not_authorized"
		expect(#r.requests):toBe(0)
		expect(r.records[DIGEST]):toBeNil()
	end)

	it("records consumer authority evidence in the write-ahead record", function()
		local r = rig()
		r.config.authorize = function(key)
			local evidence: Roblox.DeliveryAuthority = { operatorId = 7, key = key }
			return evidence, nil
		end
		r.push(created())
		r.push(operationDone())
		r.push(approvedAsset())
		Delivery.upload(r.config, request())
		expect(assert(r.records[DIGEST].authority).operatorId):toBe(7)
	end)

	it("isolates durable records from caller and result mutations", function()
		local r = rig()
		local nested = { decision = "authorized" }
		r.config.authorize = function(): (Roblox.DeliveryAuthority?, string?)
			return { nested = nested }, nil
		end
		r.push(created())
		r.push(operationDone())
		r.push(approvedAsset())
		local outcome = Delivery.upload(r.config, request())
		local saved = r.records[DIGEST]
		local returned = assert(outcome.record)
		nested.decision = "caller mutation"
		assert(returned.creator).id = "1"
		assert(returned.review).by = "result mutation"
		expect(field(returned.authority, "nested") == field(saved.authority, "nested")):toBe(false)
		assert(returned.authority).nested = "result mutation"
		expect(field(field(saved.authority, "nested"), "decision")):toBe "authorized"
		expect(assert(saved.creator).id):toBe(GROUP.id)
		expect(assert(saved.review).by):toBe "reviewer"
	end)
end)

describe("status", function()
	it("reads an operation or asset id and checks the creator", function()
		local r = rig()
		r.push(operationDone())
		r.push(approvedAsset())
		expect(Delivery.status(r.config, "operations/1234-abcd", "Image").verdict):toBe "approved"
		r.push(approvedAsset { groupId = "1" })
		expect(Delivery.status(r.config, "12345", "Image").reason):toBe "identity"
		expect(Delivery.status(r.config, "not-an-id").reason):toBe "invalid"
		r.push { failure = "unknown", detail = "timeout" }
		expect(Delivery.status(r.config, "12345").reason):toBe "remote_unreachable"
	end)
end)

describe("queue", function()
	local function item(name: string, bytes: string, log: { string }): Roblox.DeliveryItem
		return {
			name = name,
			prepare = function()
				table.insert(log, name)
				local value = request()
				value.bytes = bytes
				value.name = name
				value.review.sha256 = sha256(bytes)
				return value, nil, nil
			end,
		}
	end

	it("advances only on approval, spaces fresh sends and logs each row", function()
		local r = rig()
		local prepared: { string } = {}
		for _ = 1, 2 do
			r.push(created())
			r.push(operationDone())
			r.push(approvedAsset())
		end
		local rows: { Roblox.DeliveryRow } = {}
		local outcome = Delivery.queue(r.config, { item("a", "one", prepared), item("b", "two", prepared) }, {
			spacing = 75,
			log = function(row)
				table.insert(rows, row)
			end,
		})
		expect(outcome.verdict):toBe "approved"
		expect(r.waits):toEqual { 75 }
		expect(#rows):toBe(2)
		expect(rows[1].assetId):toBe "12345"
		expect(rows[1].state):toBe "Approved"
	end)

	it("stops at the first moderation refusal and never prepares or sends the next item", function()
		local r = rig()
		local prepared: { string } = {}
		r.push { status = 403, body = "User is moderated" }
		local outcome = Delivery.queue(r.config, { item("a", "one", prepared), item("b", "two", prepared) })
		expect(outcome.verdict):toBe "stop"
		expect(outcome.name):toBe "a"
		expect(prepared):toEqual { "a" }
		expect(r.posts()):toBe(1)
	end)

	it("holds on a pending item without sending the next", function()
		local r = rig()
		local prepared: { string } = {}
		r.push(created())
		r.push(operationDone())
		r.push(approvedAsset(nil, "Reviewing"))
		local outcome = Delivery.queue(r.config, { item("a", "one", prepared), item("b", "two", prepared) })
		expect(outcome.verdict):toBe "hold"
		expect(prepared):toEqual { "a" }
	end)

	it("stops on an item the consumer refuses to prepare", function()
		local r = rig()
		local outcome = Delivery.queue(r.config, {
			{
				name = "held",
				prepare = function()
					return nil, "quarantined", "bytes match a held-back file"
				end,
			},
		})
		expect(outcome.verdict):toBe "stop"
		expect(outcome.reason):toBe "quarantined"
		expect(#r.requests):toBe(0)
	end)
end)

describe("native save", function()
	type Host = Roblox.DeliveryNativeHost

	type NativeOptions = {
		result: string?,
		warnings: { string }?,
		throws: boolean?,
		moderation: string?,
		creator: Roblox.DeliveryCreator?,
		inspect: boolean?,
	}

	local function native(options: NativeOptions?)
		local opts: NativeOptions = options or {}
		local calls = { create = 0, readback = 0 }
		local host: Host = {
			inspect = if opts.inspect == false
				then function()
					return false, "contains a script"
				end
				else nil,
			create = function(_, _, parameters)
				calls.create += 1
				expect(parameters.creator):toEqual(GROUP)
				if opts.throws then
					error "service timeout"
				end
				return { result = opts.result or "Success", assetId = 555, warnings = opts.warnings }
			end,
			readback = function(assetId)
				calls.readback += 1
				return {
					assetId = assetId,
					creator = opts.creator or GROUP,
					assetType = "Model",
					version = "9",
					moderation = opts.moderation,
				}
			end,
		}
		return host, calls
	end

	local function nativeRequest(): Roblox.DeliveryNativeRequest
		return {
			key = "model-1",
			object = {},
			kind = "Model",
			name = "fixture_model",
			review = review(),
			identity = { source = "workshop/fixture" },
		}
	end

	it("saves once and returns the asset and version after approved readback", function()
		local r = rig()
		local host, calls = native { moderation = "Approved" }
		local outcome = Delivery.native.save(r.config, host, nativeRequest())
		expect(outcome.verdict):toBe "approved"
		expect(outcome.assetId):toBe "555"
		expect(outcome.version):toBe "9"
		expect(calls.create):toBe(1)
		expect(assert(r.records["model-1"].identity).source):toBe "workshop/fixture"
		expect(assert(r.records["model-1"].review).by):toBe "reviewer"
	end)

	it("resumes a saved id by readback without creating again", function()
		local r = rig()
		local pendingHost, pendingCalls = native {}
		local first = Delivery.native.save(r.config, pendingHost, nativeRequest())
		expect(first.verdict):toBe "hold"
		expect(first.reason):toBe "pending"
		local approvedHost, approvedCalls = native { moderation = "Approved" }
		local second = Delivery.native.save(r.config, approvedHost, nativeRequest())
		expect(second.verdict):toBe "approved"
		expect(pendingCalls.create + approvedCalls.create):toBe(1)
	end)

	it("stops on rejection, a foreign creator and a failed readback hold", function()
		local rejected = rig()
		local host = native { moderation = "Rejected" }
		expect(Delivery.native.save(rejected.config, host, nativeRequest()).reason):toBe "rejected"
		local foreign = rig()
		local foreignHost = native { moderation = "Approved", creator = { kind = "user", id = "1" } }
		expect(Delivery.native.save(foreign.config, foreignHost, nativeRequest()).reason):toBe "identity"
	end)

	it("holds a warning, a failure result and a throw without retrying", function()
		local warned = rig()
		local warnHost, warnCalls = native { warnings = { "texture downscaled" } }
		local warning = Delivery.native.save(warned.config, warnHost, nativeRequest())
		expect(warning.reason):toBe "warning"
		expect(warning.assetId):toBe "555"
		expect(Delivery.native.save(warned.config, warnHost, nativeRequest()).verdict):toBe "hold"
		expect(warnCalls.create):toBe(1)

		local failed = rig()
		local failHost, failCalls = native { result = "ModerationFailed" }
		expect(Delivery.native.save(failed.config, failHost, nativeRequest()).reason):toBe "failed"
		expect(Delivery.native.save(failed.config, failHost, nativeRequest()).reason):toBe "pending"
		expect(failCalls.create):toBe(1)

		local thrown = rig()
		local throwHost, throwCalls = native { throws = true }
		expect(Delivery.native.save(thrown.config, throwHost, nativeRequest()).reason):toBe "ambiguous"
		expect(Delivery.native.save(thrown.config, throwHost, nativeRequest()).reason):toBe "ambiguous"
		expect(throwCalls.create):toBe(1)
		local resolved = Delivery.native.attach(thrown.config, "model-1", "555")
		expect(resolved.reason):toBe "pending"
		local approvedHost, approvedCalls = native { moderation = "Approved" }
		expect(Delivery.native.save(thrown.config, approvedHost, nativeRequest()).verdict):toBe "approved"
		expect(approvedCalls.create):toBe(0)
	end)

	it("keeps its record on an instance attribute so a Studio session can resume", function()
		local attributes: { [string]: unknown } = {}
		local instance: Roblox.DeliveryAttributeInstance = {
			GetAttribute = function(_self: Roblox.DeliveryAttributeInstance, key: string): unknown
				return attributes[key]
			end,
			SetAttribute = function(_self: Roblox.DeliveryAttributeInstance, key: string, value: string)
				attributes[key] = value
			end,
		}
		local http: Roblox.DeliveryAttributeJson = {
			JSONEncode = function(_self: Roblox.DeliveryAttributeJson, value: Roblox.DeliveryRecord): string
				return Lute.encode(value)
			end,
			JSONDecode = function(_self: Roblox.DeliveryAttributeJson, text: string): Roblox.DeliveryRecord
				local decoded = json.deserialize(text)
				local attempt, assetId = field(decoded, "attempt"), field(decoded, "assetId")
				assert(type(attempt) == "string")
				assert(assetId == nil or type(assetId) == "string")
				return { attempt = attempt, assetId = assetId }
			end,
		}
		local store = Delivery.native.attributeStore(instance, http)
		expect(store.read "Model"):toBeNil()
		expect(store.create("Model", { attempt = "started" })):toBe(true)
		expect(store.create("Model", { attempt = "again" })):toBe(false)
		store.write("Model", { attempt = "saved", assetId = "5" })
		expect(assert(store.read "Model").assetId):toBe "5"
		expect(type(attributes.ModelRecord)):toBe "string"
	end)

	it("refuses an uninspected object or missing review before any save", function()
		local r = rig()
		local host, calls = native { inspect = false }
		expect(Delivery.native.save(r.config, host, nativeRequest()).reason):toBe "inspection"
		local unreviewed = nativeRequest()
		unreviewed.review.verdict = "unsure"
		expect(Delivery.native.save(r.config, host, unreviewed).reason):toBe "unreviewed"
		expect(calls.create):toBe(0)
		expect(r.records["model-1"]):toBeNil()
	end)
end)

return nil
