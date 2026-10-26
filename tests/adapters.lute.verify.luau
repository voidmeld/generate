--!strict

local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local fs = require "@std/fs"

local Agent = require "../src/agent"
local Content = require "../src/content"
local Generate = require "../src/core"
local Host = require "../src/host"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Verify = require "../.lute/dependencies/verify/src/core"

local function brief(kind: Generate.AssetKind): Generate.Brief
	return Generate.brief {
		id = "fixture." .. kind,
		kind = kind,
		intent = { role = "fixture", description = "a production fixture" },
		review = { rubric = "fixture", rubricFingerprint = "rubric-fixture-v1", views = { "canonical" } },
		delivery = { semanticId = "fixture.semantic", target = "roblox" },
	}
end

local function artifact(id: string): Generate.Artifact
	return {
		id = id,
		digest = string.rep("b", 64),
		digestAlgorithm = "sha256",
		mediaType = "application/octet-stream",
		metadata = {},
	}
end

local function publicationGrant(): Roblox.AssetPublicationGrant
	return {
		schemaVersion = 1,
		id = "grant-1",
		actor = "producer-7",
		policy = "private-quarantine-v1",
		briefFingerprint = Generate.briefFingerprint(brief "rigid-mesh"),
		idempotencyKey = "plan:publish",
		artifactDigest = string.rep("b", 64),
		semanticId = "fixture.semantic",
		displayName = "Fixture Asset",
		description = "A public-facing fixture asset",
		target = "roblox",
		assetType = "Model",
		creator = { type = "group", id = "123456" },
		action = "create",
		visibility = "restricted",
		permissionChanges = false,
		maxAttempts = 1,
	}
end

describe("Generate adapters", function()
	it("evaluates artifact checks through the pinned Verify harness", function()
		local value = brief "image"
		local plan = Generate.plan(value, { { id = "image", operation = "generate" } })
		local receipt = Generate.execute(value, plan, Host.fake.create(), {
			capabilities = {},
			destinations = {},
			mutationBudget = 0,
		})
		local harness = Verify.createHarness {
			now = function()
				return 0
			end,
		}
		harness:case("production completed", function(context)
			context:expect(receipt.status):toEqual "produced"
		end)
		local report = harness:run { executor = "lute", capabilities = {}, environment = { runtime = "lute" } }

		expect(report.passed):toEqual(1)
	end)

	it("compiles structured quest content without embedding consumer policy", function()
		local outcome = Content.compile({
			tool = "fixture quest compiler",
			version = "1",
			compile = function(kind, source, schema, semanticId)
				expect(kind):toEqual "quest"
				expect(source):toEqual "quest-source"
				expect(schema):toEqual "quest-v1"
				expect(semanticId):toEqual "fixture.semantic"
				return artifact "quest"
			end,
		}, brief "quest", "quest-source", "quest-v1")
		expect(outcome.status):toEqual "returned"
		assert(outcome.status == "returned")
	end)

	it("publishes one exact restricted asset under a fingerprinted grant", function()
		local source = artifact "model"
		local delivered = artifact "published-model"
		delivered.semanticId = "fixture.semantic"
		local outcome = Roblox.assetPublication.publish({
			toolVersion = "v2",
			publish = function(request)
				expect(request.grant.id):toEqual "grant-1"
				expect(request.grant.creator):toEqual { type = "group", id = "123456" }
				expect(request.artifact.digest):toEqual(source.digest)
				expect(request.idempotencyKey):toEqual "plan:publish"
				expect(request.grantFingerprint):toEqual(Generate.fingerprint(request.grant))
				return {
					status = "published",
					assetId = "1",
					version = "2",
					operationId = "op",
					rollbackToken = "archive:1",
				}
			end,
			readback = function(published, request)
				expect(published.assetId):toEqual "1"
				return {
					artifact = delivered,
					assetId = published.assetId,
					version = published.version,
					semanticId = request.grant.semanticId,
					displayName = request.grant.displayName,
					description = request.grant.description,
					target = request.grant.target,
					assetType = request.grant.assetType,
					creator = request.grant.creator,
					visibility = request.grant.visibility,
				}
			end,
		}, brief "rigid-mesh", { source }, publicationGrant(), "plan:publish")
		expect(outcome.status):toEqual "returned"
		assert(outcome.status == "returned")
		expect(assert(outcome.output.metadata).grantId):toEqual "grant-1"
		expect(assert(outcome.output.metadata).assetId):toEqual "1"
		expect(assert(outcome.output.metadata).visibility):toEqual "restricted"
	end)

	it("refuses public visibility, permission changes, and multi-attempt grants", function()
		for field, value in { visibility = "public", permissionChanges = true, maxAttempts = 2 } do
			local draft = publicationGrant()
			draft[field] = value
			expect(function()
				Roblox.assetPublication.grant(draft)
			end):toThrow()
		end
		local incompleteMetadata = publicationGrant()
		incompleteMetadata.description = nil
		expect(function()
			Roblox.assetPublication.grant(incompleteMetadata)
		end):toThrow "displayName and description"
	end)

	it("refuses credential-shaped fields and a stage outside the grant", function()
		local smuggled = publicationGrant()
		local extra = smuggled :: Roblox.AssetPublicationGrant & { apiKey: string? }
		extra.apiKey = "not-a-real-key"
		expect(function()
			Roblox.assetPublication.grant(smuggled)
		end):toThrow()

		local outcome = Roblox.assetPublication.publish({
			toolVersion = "v2",
			publish = function()
				error "unreachable"
			end,
			readback = function()
				error "unreachable"
			end,
		}, brief "rigid-mesh", { artifact "model" }, publicationGrant(), "another-plan:publish")
		expect(outcome.status):toEqual "rejected"
		assert(outcome.status == "rejected")
	end)

	it("refuses a source artifact outside the publication grant before dispatch", function()
		local invoked = false
		local draft = publicationGrant()
		draft.artifactDigest = string.rep("a", 64)
		local outcome = Roblox.assetPublication.publish({
			toolVersion = "v2",
			publish = function()
				invoked = true
				error "unreachable"
			end,
			readback = function()
				error "unreachable"
			end,
		}, brief "rigid-mesh", { artifact "model" }, draft, "plan:publish")
		expect(outcome.status):toEqual "rejected"
		assert(outcome.status == "rejected")
		expect(invoked):toEqual(false)
	end)

	it("requires a readback after Roblox publication", function()
		local outcome = Roblox.assetPublication.publish({
			toolVersion = "v2",
			publish = function()
				return {
					status = "published",
					assetId = "1",
					version = "2",
					operationId = "op",
					previousVersion = "1",
					rollbackToken = "restore-version:1",
				}
			end,
			readback = function()
				error "moderation readback unavailable"
			end,
		}, brief "rigid-mesh", { artifact "model" }, publicationGrant(), "plan:publish")
		expect(outcome.status):toEqual "faulted"
		assert(outcome.status == "faulted")
		expect(outcome.rollbackToken):toEqual "restore-version:1"
	end)

	it("returns a rollback token when durable readback disagrees with the grant", function()
		local delivered = artifact "published-model"
		delivered.semanticId = "fixture.semantic"
		local outcome = Roblox.assetPublication.publish({
			toolVersion = "v2",
			publish = function()
				return {
					status = "published",
					assetId = "1",
					version = "2",
					operationId = "op",
					rollbackToken = "archive:1",
				}
			end,
			readback = function()
				return {
					artifact = delivered,
					assetId = "1",
					version = "2",
					semanticId = "fixture.semantic",
					displayName = "Fixture Asset",
					description = "A public-facing fixture asset",
					target = "roblox",
					assetType = "Model",
					creator = { type = "user", id = "wrong" },
					visibility = "restricted",
				}
			end,
		}, brief "rigid-mesh", { artifact "model" }, publicationGrant(), "plan:publish")
		expect(outcome.status):toEqual "faulted"
		assert(outcome.status == "faulted")
		expect(outcome.detail):toContain "granted creator"
		expect(outcome.rollbackToken):toEqual "archive:1"
	end)

	it("carries a post-mutation publication fault to core compensation", function()
		local outcome = Roblox.assetPublication.publish({
			toolVersion = "v2",
			publish = function()
				return { status = "faulted", detail = "poll timed out after create", rollbackToken = "archive:1" }
			end,
			readback = function()
				error "unreachable"
			end,
		}, brief "rigid-mesh", { artifact "model" }, publicationGrant(), "plan:publish")
		expect(outcome.status):toEqual "faulted"
		assert(outcome.status == "faulted")
		expect(outcome.rollbackToken):toEqual "archive:1"
	end)

	it("runs and content-addresses a real external DCC process output", function()
		local root = ".lute/tmp/generate-dcc-spec"
		if not fs.exists(root) then
			fs.createDirectory(root, { makeParents = true })
		end
		local output = root .. "/artifact.bin"
		local outcome = Lute.process.run {
			command = { "lute", "run", "tests/fixtures/dcc-worker.luau", output },
			output = output,
			id = "dcc-output",
			mediaType = "application/octet-stream",
			tool = "fixture-dcc",
			toolVersion = "1",
			deterministic = true,
		}
		expect(outcome.status):toEqual "returned"
		assert(outcome.status == "returned")
		expect(#assert(outcome.output.artifacts)[1].digest):toEqual(64)
	end)
end)

describe("Generate Open Cloud operations", function()
	local json = require "@std/json"

	local function encode(value: unknown): string
		return json.serialize(value :: json.Value)
	end

	local function decode(body: string): unknown
		local ok, parsed = pcall(json.deserialize, body)
		return if ok then parsed else nil
	end

	local function document(defaults: { [string]: json.Value }, overrides: unknown): string
		local body = table.clone(defaults)
		for key, value in (overrides or {}) :: { [string]: json.Value } do
			body[key] = value
		end
		return json.serialize(body)
	end

	local function assetRecord(assetId: string, version: string, overrides: unknown): string
		return document({
			path = "assets/" .. assetId,
			assetId = assetId,
			revisionId = version,
			moderationResult = { moderationState = "Approved" },
			assetType = "ASSET_TYPE_MODEL",
			displayName = "Fixture Asset",
			description = "A public-facing fixture asset",
			creationContext = { creator = { groupId = "123456" } },
			state = "Active",
		}, overrides)
	end

	local function pathOnlyAssetRecord(assetId: string, version: string, overrides: unknown): string
		local body: { [string]: json.Value } = {
			path = "assets/" .. assetId,
			revisionId = version,
			moderationResult = { moderationState = "Approved" },
			assetType = "ASSET_TYPE_MODEL",
			displayName = "Fixture Asset",
			description = "A public-facing fixture asset",
			creationContext = { creator = { groupId = "123456" } },
			state = "Active",
		}
		for key, value in (overrides or {}) :: { [string]: json.Value } do
			body[key] = value
		end
		return encode(body)
	end

	local function versionRecord(assetId: string, version: string): string
		return encode {
			path = "assets/" .. assetId .. "/versions/" .. version,
			moderationResult = { moderationState = "Approved" },
			creationContext = { creator = { groupId = "123456" } },
		}
	end

	local function operation(path: string, done: boolean, response: { [string]: json.Value }?): string
		return encode { path = path, done = done, response = response }
	end

	local function completedAsset(assetId: string, version: string, overrides: unknown): { [string]: json.Value }
		local result: { [string]: json.Value } = {
			path = "assets/" .. assetId,
			assetId = assetId,
			revisionId = version,
			moderationResult = { moderationState = "Approved" },
			assetType = "ASSET_TYPE_MODEL",
			creationContext = { creator = { groupId = "123456" } },
		}
		for key, value in (overrides or {}) :: { [string]: json.Value } do
			result[key] = value
		end
		return result
	end

	local function archived(assetId: string): string
		return assetRecord(assetId, "1", { state = "Archived" })
	end

	type Scripted = { status: number?, ok: boolean?, body: string?, raise: string? }

	local function adapter(
		script: { Scripted },
		maxPolls: number?
	): (Roblox.AssetPublicationAdapter, { Roblox.CloudRequest }, { string })
		local seen: { Roblox.CloudRequest } = {}
		local waits: { string } = {}
		return Roblox.assetPublication.operations {
			toolVersion = "fixture-open-cloud-v1",
			encode = encode,
			decode = decode,
			baseUrl = "https://fixture.invalid/assets/v1",
			readArtifact = function()
				return "fixture-binary"
			end,
			maxPolls = maxPolls or 2,
			waitBeforePoll = function(ordinal, path)
				table.insert(waits, tostring(ordinal) .. ":" .. path)
			end,
			send = function(request)
				table.insert(seen, request)
				local queued = script[#seen]
				if queued == nil then
					return { ok = true, status = 200, body = "{}" }
				end
				if queued.raise ~= nil then
					error(queued.raise, 0)
				end
				local answer = {
					ok = assert(queued.ok ~= nil) and queued.ok,
					status = assert(queued.status),
					body = assert(queued.body),
				}
				return { ok = answer.ok, status = answer.status, body = answer.body }
			end,
		},
			seen,
			waits
	end

	local function stage(id: string, overrides: unknown): Roblox.AssetPublicationStage
		local draft = publicationGrant()
		local fields = draft :: Roblox.AssetPublicationGrant & { [string]: unknown }
		for key, value in (overrides or {}) :: { [string]: json.Value } do
			fields[key] = value
		end
		return {
			id = id,
			grant = Roblox.assetPublication.grant(draft),
			brief = brief "rigid-mesh",
			artifacts = { artifact "model" },
		}
	end

	local function transact(
		script: { Scripted },
		stages: { Roblox.AssetPublicationStage }?,
		maxPolls: number?
	): (Roblox.AssetPublicationTransaction, { Roblox.CloudRequest }, { string })
		local operations, seen, waits = adapter(script, maxPolls)
		return Roblox.assetPublication.transaction(operations, stages or { stage "root" }, Generate.fingerprint),
			seen,
			waits
	end

	local capturedMetadata = require "./fixtures/asset-metadata"

	local function metadataReader(forceSparse: boolean?): (Roblox.AssetPublicationAdapter, { string })
		local urls: { string } = {}
		local operations = Roblox.assetPublication.operations {
			toolVersion = "fixture-metadata-v1",
			encode = encode,
			decode = decode,
			readArtifact = function()
				error "metadata readback must not read or upload bytes"
			end,
			maxPolls = 1,
			baseUrl = "https://fixture.invalid/assets/v1",
			send = function(request)
				expect(request.method):toEqual "GET"
				table.insert(urls, request.url)
				local body = if string.find(request.url, "/versions/", 1, true) ~= nil
					then versionRecord("999000111", "1")
					elseif
						forceSparse or string.find(request.url, "?readMask=", 1, true) ~= nil
					then capturedMetadata.masked.body
					else capturedMetadata.unmasked.body
				return { ok = true, status = 200, body = body }
			end,
		}
		return operations, urls
	end

	local function readCaptured(operations: Roblox.AssetPublicationAdapter)
		local grant = Roblox.assetPublication.grant(publicationGrant())
		return operations.readback({
			status = "published",
			assetId = "999000111",
			version = "1",
			operationId = "operations/fixture",
			rollbackToken = "archive:999000111",
		}, {
			grant = grant,
			artifact = artifact "model",
			idempotencyKey = grant.idempotencyKey,
			grantFingerprint = Generate.fingerprint(grant),
		})
	end

	it("reads complete authority metadata instead of the captured sparse read-mask response", function()
		local operations, urls = metadataReader()
		local readback = readCaptured(operations)
		expect(readback.assetId):toEqual "999000111"
		expect(readback.version):toEqual "1"
		expect(readback.creator):toEqual { type = "group", id = "123456" }
		expect(urls):toEqual {
			"https://fixture.invalid/assets/v1/assets/999000111",
			"https://fixture.invalid/assets/v1/assets/999000111/versions/1",
		}
	end)

	it("still refuses a sparse response without creator authority", function()
		local operations = metadataReader(true)
		expect(function()
			readCaptured(operations)
		end):toThrow "no creator"
	end)

	it("uploads deterministic multipart content, polls, and reads asset plus version back", function()
		local transaction, seen, waits = transact {
			{ ok = true, status = 200, body = operation("operations/create-1", false, nil) },
			{
				ok = true,
				status = 200,
				body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "1", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "1") },
		}
		expect(transaction.disposition):toEqual "published"
		expect(transaction.terminal):toEqual(true)
		expect(transaction.retried):toEqual(false)
		expect(transaction.attemptsMade):toEqual(1)
		expect(#transaction.compensations):toEqual(0)
		expect(#seen):toEqual(4)
		expect(seen[1].method):toEqual "POST"
		expect(seen[1].url):toEqual "https://fixture.invalid/assets/v1/assets"
		expect(seen[1].headers["Content-Type"]):toContain "multipart/form-data; boundary=generate-"
		expect(seen[1].headers["Idempotency-Key"]):toEqual(nil)
		expect(seen[1].body):toContain 'name="request"'
		expect(seen[1].body):toContain 'name="fileContent"; filename="model"'
		expect(seen[1].body):toContain '"assetType":"Model"'
		expect(seen[1].body):toContain '{"assetType":"Model","displayName":"Fixture Asset","description":"A public-facing fixture asset","creationContext":{"creator":{"groupId":"123456"},"assetPrivacy":"restricted"}}'
		expect(seen[1].body):toContain '"groupId":"123456"'
		expect(seen[1].body):toContain '"assetPrivacy":"restricted"'
		expect(seen[1].body):toContain "fixture-binary"
		expect(seen[1].body).never:toContain "contentDigest"
		expect(seen[2].method):toEqual "GET"
		expect(seen[2].url):toEqual "https://fixture.invalid/assets/v1/operations/create-1"
		expect(seen[3].url):toEqual "https://fixture.invalid/assets/v1/assets/999000111"
		expect(seen[4].url):toEqual "https://fixture.invalid/assets/v1/assets/999000111/versions/1"
		expect(waits):toEqual { "1:operations/create-1" }
	end)

	it("names no credential anywhere: the transport authorizes, the adapter does not", function()
		local _, seen = transact {
			{
				ok = true,
				status = 200,
				body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "1", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "1") },
		}
		for _, request in seen do
			for header in request.headers do
				expect(string.lower(header) ~= "x-api-key"):toEqual(true)
				expect(string.lower(header) ~= "authorization"):toEqual(true)
			end
		end
	end)

	it("pre-reads an update rollback version, uploads once, then reads the new version", function()
		local _, seen = transact({
			{ ok = true, status = 200, body = assetRecord("999000111", "7", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "7") },
			{
				ok = true,
				status = 200,
				body = operation("operations/update-1", true, completedAsset("999000111", "8", nil)),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "8", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "8") },
		}, { stage("root", { action = "update", assetId = "999000111" }) })
		expect(seen[1].method):toEqual "GET"
		expect(seen[2].url):toEqual "https://fixture.invalid/assets/v1/assets/999000111/versions/7"
		expect(seen[3].method):toEqual "PATCH"
		expect(seen[3].url):toEqual "https://fixture.invalid/assets/v1/assets/999000111?updateMask=description%2CdisplayName"
		expect(seen[3].body):toContain '{"assetType":"Model","displayName":"Fixture Asset","description":"A public-facing fixture asset","assetId":"999000111","creationContext":{"creator":{"groupId":"123456"}}}'
	end)

	it("classifies a refusal, and spends no second attempt", function()
		local transaction, seen = transact { { ok = false, status = 403, body = "" } }
		expect(transaction.disposition):toEqual "refused"
		expect(#seen):toEqual(1)
	end)

	it("classifies a throttled attempt as a spent attempt, never as a wait", function()
		local transaction, seen = transact { { ok = false, status = 429, body = "" } }
		expect(transaction.disposition):toEqual "refused"
		expect(#seen):toEqual(1)
	end)

	it("classifies a request that never resolved as ambiguous", function()
		local transaction = transact { { raise = "connection reset" } }
		expect(transaction.disposition):toEqual "ambiguous"
	end)

	it("classifies an unreadable body as ambiguous", function()
		local transaction = transact { { ok = true, status = 200, body = "<html>maintenance</html>" } }
		expect(transaction.disposition):toEqual "ambiguous"
	end)

	it("classifies an unresolved operation poll as ambiguous without submitting again", function()
		local transaction, seen = transact {
			{ ok = true, status = 200, body = operation("operations/create-1", false, nil) },
			{ raise = "poll connection reset" },
		}
		expect(transaction.disposition):toEqual "ambiguous"
		expect(#seen):toEqual(2)
	end)

	it("classifies a still-pending operation as timed out at the exact poll budget", function()
		local transaction, seen = transact({
			{ ok = true, status = 200, body = operation("operations/create-1", false, nil) },
			{ ok = true, status = 200, body = operation("operations/create-1", false, nil) },
			{ ok = true, status = 200, body = operation("operations/create-1", false, nil) },
		}, nil, 2)
		expect(transaction.disposition):toEqual "timed-out"
		expect(#seen):toEqual(3)
	end)

	it("polls a reviewing asset until moderation approves it and publishes it", function()
		local transaction, seen = transact {
			{
				ok = true,
				status = 200,
				body = operation(
					"operations/create-1",
					true,
					completedAsset("999000111", "1", { moderationResult = { moderationState = "Reviewing" } })
				),
			},
			{
				ok = true,
				status = 200,
				body = assetRecord("999000111", "1", { moderationResult = { moderationState = "Reviewing" } }),
			},
			{
				ok = true,
				status = 200,
				body = assetRecord("999000111", "1", { moderationResult = { moderationState = "Approved" } }),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "1", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "1") },
		}
		expect(transaction.disposition):toEqual "published"
		expect(#transaction.compensations):toEqual(0)
		expect(#seen):toEqual(5)
	end)

	it("classifies a rejected asset as refused and never compensates it", function()
		local transaction = transact {
			{
				ok = true,
				status = 200,
				body = operation(
					"operations/create-1",
					true,
					completedAsset("999000111", "1", { moderationResult = { moderationState = "Rejected" } })
				),
			},
		}
		expect(transaction.disposition):toEqual "refused"
		expect(#transaction.compensations):toEqual(0)
	end)

	it(
		"classifies a still-reviewing asset as moderation-pending after the poll budget and never compensates it",
		function()
			local transaction, seen = transact {
				{
					ok = true,
					status = 200,
					body = operation(
						"operations/create-1",
						true,
						completedAsset("999000111", "1", { moderationResult = { moderationState = "Reviewing" } })
					),
				},
				{
					ok = true,
					status = 200,
					body = assetRecord("999000111", "1", { moderationResult = { moderationState = "Reviewing" } }),
				},
				{
					ok = true,
					status = 200,
					body = assetRecord("999000111", "1", { moderationResult = { moderationState = "Reviewing" } }),
				},
				{
					ok = true,
					status = 200,
					body = assetRecord("999000111", "1", { moderationResult = { moderationState = "Reviewing" } }),
				},
			}
			expect(transaction.disposition):toEqual "moderation-pending"
			expect(#transaction.compensations):toEqual(0)
			expect(#seen):toEqual(4)
		end
	)

	it("identifies a reviewing poll response by path alone and keeps polling", function()
		local transaction, seen = transact {
			{
				ok = true,
				status = 200,
				body = operation(
					"operations/create-1",
					true,
					completedAsset("999000111", "1", { moderationResult = { moderationState = "Reviewing" } })
				),
			},
			{
				ok = true,
				status = 200,
				body = pathOnlyAssetRecord("999000111", "1", { moderationResult = { moderationState = "Reviewing" } }),
			},
			{
				ok = true,
				status = 200,
				body = pathOnlyAssetRecord("999000111", "1", { moderationResult = { moderationState = "Approved" } }),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "1", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "1") },
		}
		expect(transaction.disposition):toEqual "published"
		expect(#transaction.compensations):toEqual(0)
		expect(#seen):toEqual(5)
	end)

	it("identifies an approved poll response by path alone and publishes it", function()
		local transaction = transact {
			{
				ok = true,
				status = 200,
				body = operation(
					"operations/create-1",
					true,
					completedAsset("999000111", "1", { moderationResult = { moderationState = "Reviewing" } })
				),
			},
			{
				ok = true,
				status = 200,
				body = pathOnlyAssetRecord("999000111", "1", { moderationResult = { moderationState = "Approved" } }),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "1", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "1") },
		}
		expect(transaction.disposition):toEqual "published"
		expect(#transaction.compensations):toEqual(0)
	end)

	it("identifies a rejected poll response by path alone and refuses it without compensation", function()
		local transaction = transact {
			{
				ok = true,
				status = 200,
				body = operation(
					"operations/create-1",
					true,
					completedAsset("999000111", "1", { moderationResult = { moderationState = "Reviewing" } })
				),
			},
			{
				ok = true,
				status = 200,
				body = pathOnlyAssetRecord("999000111", "1", { moderationResult = { moderationState = "Rejected" } }),
			},
		}
		expect(transaction.disposition):toEqual "refused"
		expect(#transaction.compensations):toEqual(0)
		expect(transaction.attempts[1].assetId):toEqual "999000111"
	end)

	it(
		"marks a moderation poll that names another asset moderation-pending, records the created id, and never compensates it",
		function()
			local transaction, seen = transact {
				{
					ok = true,
					status = 200,
					body = operation(
						"operations/create-1",
						true,
						completedAsset("999000111", "1", { moderationResult = { moderationState = "Reviewing" } })
					),
				},
				{ ok = true, status = 200, body = assetRecord("999000222", "1", nil) },
			}
			expect(transaction.disposition):toEqual "moderation-pending"
			expect(transaction.detail):toContain "moderation poll returned another asset"
			expect(#transaction.compensations):toEqual(0)
			expect(transaction.attempts[1].assetId):toEqual "999000111"
			expect(transaction.attempts[1].rollbackToken):toEqual(nil)
			expect(#seen):toEqual(2)
		end
	)

	it("classifies a gateway timeout as a timeout", function()
		expect(transact({ { ok = false, status = 504, body = "" } }).disposition):toEqual "timed-out"
	end)

	it("classifies an incomplete durable identity as partial", function()
		local transaction = transact {
			{ ok = true, status = 200, body = operation("operations/create-1", true, completedAsset("", "1", nil)) },
		}
		expect(transaction.disposition):toEqual "partial"
		expect(#transaction.compensations):toEqual(0)
	end)

	it("classifies a failed asset readback and archives the created asset", function()
		local transaction, seen = transact {
			{
				ok = true,
				status = 200,
				body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
			},
			{ ok = false, status = 404, body = "" },
			{ ok = true, status = 200, body = archived "999000111" },
		}
		expect(transaction.disposition):toEqual "failed-readback"
		expect(#transaction.compensations):toEqual(1)
		expect(transaction.compensations[1].status):toEqual "ok"
		expect(seen[3].url):toEqual "https://fixture.invalid/assets/v1/assets/999000111:archive"
	end)

	it("classifies a failed exact-version readback and archives the created asset", function()
		local transaction = transact {
			{
				ok = true,
				status = 200,
				body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "1", nil) },
			{ ok = false, status = 404, body = "" },
			{ ok = true, status = 200, body = archived "999000111" },
		}
		expect(transaction.disposition):toEqual "failed-readback"
		expect(transaction.compensations[1].status):toEqual "ok"
	end)

	it("forms byte-identical multipart requests for the same granted source", function()
		local script = {
			{
				ok = true,
				status = 200,
				body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "1", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "1") },
		}
		local _, first = transact(script)
		local _, second = transact(script)
		expect(first[1].headers["Content-Type"]):toEqual(second[1].headers["Content-Type"])
		expect(first[1].body):toEqual(second[1].body)
	end)

	it("refuses changed public metadata independently of semantic identity", function()
		for field, value in
			{
				displayName = "Changed fixture asset",
				description = "Changed fixture description",
			}
		do
			local transaction = transact {
				{
					ok = true,
					status = 200,
					body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
				},
				{ ok = true, status = 200, body = assetRecord("999000111", "1", { [field :: string] = value }) },
				{ ok = true, status = 200, body = versionRecord("999000111", "1") },
				{ ok = true, status = 200, body = archived "999000111" },
			}
			expect(transaction.disposition):toEqual "failed-readback"
		end
	end)

	it("preserves the legacy semantic-description publication contract", function()
		local legacy = stage "root"
		legacy.grant.displayName = nil
		legacy.grant.description = nil
		local transaction = transact({
			{
				ok = true,
				status = 200,
				body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "1", { description = "fixture.semantic" }) },
			{ ok = true, status = 200, body = versionRecord("999000111", "1") },
		}, { legacy })
		expect(transaction.disposition):toEqual "published"
	end)

	it("does not let matching metadata relax asset, version, or creator identity", function()
		local transaction = transact {
			{
				ok = true,
				status = 200,
				body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
			},
			{ ok = true, status = 200, body = assetRecord("999000111", "2", nil) },
			{ ok = true, status = 200, body = archived "999000111" },
		}
		expect(transaction.disposition):toEqual "failed-readback"
	end)

	it("reports an archive refusal as failed compensation, outranking the readback cause", function()
		local transaction = transact {
			{
				ok = true,
				status = 200,
				body = operation("operations/create-1", true, completedAsset("999000111", "1", nil)),
			},
			{ ok = false, status = 500, body = "" },
			{ ok = false, status = 500, body = "" },
		}
		expect(transaction.disposition):toEqual "failed-compensation"
		expect(transaction.compensations[1].status):toEqual "failed"
		expect(transaction.attempts[1].rollbackToken):toEqual "archive:999000111"
		expect(transaction.attempts[1].assetId):toEqual "999000111"
	end)

	it("rolls an update back through versions:rollback and authenticates the resulting version", function()
		local transaction, seen = transact({
			{ ok = true, status = 200, body = assetRecord("999000111", "7", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "7") },
			{
				ok = true,
				status = 200,
				body = operation("operations/update-1", true, completedAsset("999000111", "8", nil)),
			},
			{ ok = false, status = 500, body = "" },
			{ ok = true, status = 200, body = versionRecord("999000111", "9") },
			{ ok = true, status = 200, body = assetRecord("999000111", "9", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "9") },
		}, { stage("root", { action = "update", assetId = "999000111" }) })
		expect(transaction.disposition):toEqual "failed-readback"
		expect(transaction.compensations[1].status):toEqual "ok"
		expect(transaction.compensations[1].token):toEqual "rollback:999000111:7"
		expect(seen[5].url):toEqual "https://fixture.invalid/assets/v1/assets/999000111/versions:rollback"
		expect((decode(assert(seen[5].body)) :: { assetVersion: string }).assetVersion):toEqual "assets/999000111/versions/7"
	end)

	it("retains a failed update rollback readback", function()
		local transaction = transact({
			{ ok = true, status = 200, body = assetRecord("999000111", "7", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "7") },
			{
				ok = true,
				status = 200,
				body = operation("operations/update-1", true, completedAsset("999000111", "8", nil)),
			},
			{ ok = false, status = 500, body = "" },
			{ ok = true, status = 200, body = versionRecord("999000111", "9") },
			{ ok = false, status = 500, body = "" },
		}, { stage("root", { action = "update", assetId = "999000111" }) })
		expect(transaction.disposition):toEqual "failed-compensation"
		expect(transaction.compensations[1].status):toEqual "failed"
	end)

	it("retains a refused update rollback request", function()
		local transaction = transact({
			{ ok = true, status = 200, body = assetRecord("999000111", "7", nil) },
			{ ok = true, status = 200, body = versionRecord("999000111", "7") },
			{
				ok = true,
				status = 200,
				body = operation("operations/update-1", true, completedAsset("999000111", "8", nil)),
			},
			{ ok = false, status = 500, body = "" },
			{ ok = false, status = 403, body = "" },
		}, { stage("root", { action = "update", assetId = "999000111" }) })
		expect(transaction.disposition):toEqual "failed-compensation"
		expect(transaction.compensations[1].status):toEqual "failed"
	end)

	it("refuses an update whose previous version cannot be authenticated before mutation", function()
		local transaction, seen = transact({
			{ ok = true, status = 200, body = assetRecord("999000111", "7", nil) },
			{ ok = false, status = 404, body = "" },
		}, { stage("root", { action = "update", assetId = "999000111" }) })
		expect(transaction.disposition):toEqual "refused"
		expect(#seen):toEqual(2)
		for _, request in seen do
			expect(request.method).never:toEqual "PATCH"
		end
	end)

	it("compensates newest first across stages, and starts no stage after a failure", function()
		local stages = {
			stage("dependency", { id = "grant-dependency", idempotencyKey = "plan:publish" }),
			stage "root",
		}
		local transaction = transact({
			{
				ok = true,
				status = 200,
				body = operation("operations/create-111", true, completedAsset("111", "1", nil)),
			},
			{ ok = true, status = 200, body = assetRecord("111", "1", nil) },
			{ ok = true, status = 200, body = versionRecord("111", "1") },
			{
				ok = true,
				status = 200,
				body = operation("operations/create-222", true, completedAsset("222", "1", nil)),
			},
			{ ok = false, status = 404, body = "" },
			{ ok = true, status = 200, body = archived "222" },
			{ ok = true, status = 200, body = archived "111" },
		}, stages)
		expect(transaction.disposition):toEqual "failed-readback"
		expect(transaction.attemptsAuthorised):toEqual(2)
		expect(transaction.attemptsMade):toEqual(2)
		expect(#transaction.compensations):toEqual(2)
		expect(transaction.compensations[1].token):toEqual "archive:222"
		expect(transaction.compensations[2].token):toEqual "archive:111"

		local refused = transact({ { ok = false, status = 403, body = "" } }, stages)
		expect(refused.attemptsAuthorised):toEqual(2)
		expect(refused.attemptsMade):toEqual(1)
	end)

	it("names every terminal disposition it can reach", function()
		expect(#Roblox.assetPublication.DISPOSITIONS):toEqual(9)
		expect((Roblox.assetPublication.classify { status = "faulted", detail = "partial: something" })):toEqual "partial"
		expect((Roblox.assetPublication.classify { status = "faulted", detail = "not-a-disposition: something" })):toEqual "ambiguous"
		expect((Roblox.assetPublication.classify { status = "faulted", detail = "" })):toEqual "ambiguous"
	end)

	it("requires an exact adapter version", function()
		local ok = pcall(Roblox.assetPublication.operations, {
			toolVersion = "",
			encode = encode,
			decode = decode,
			readArtifact = function()
				return "bytes"
			end,
			maxPolls = 1,
			send = function()
				return { ok = true, status = 200, body = "{}" }
			end,
		})
		expect(ok):toEqual(false)
	end)

	it("requires a positive deterministic poll budget", function()
		local ok = pcall(Roblox.assetPublication.operations, {
			toolVersion = "fixture",
			encode = encode,
			decode = decode,
			readArtifact = function()
				return "bytes"
			end,
			maxPolls = 0,
			send = function()
				return { ok = true, status = 200, body = "{}" }
			end,
		})
		expect(ok):toEqual(false)
	end)
end)

describe("Generate reviewer CLI resolution", function()
	local function resolver(overrides: {
		executable: string?,
		arguments: { string }?,
		configuredPath: string?,
		environmentVariable: string?,
		readEnv: ((string) -> string?)?,
		exists: ((string) -> boolean)?,
	}): Agent.ReviewerCliRequest
		return {
			executable = if overrides.executable == nil then "reviewer" else overrides.executable,
			arguments = if overrides.arguments == nil then { "exec", "--json" } else overrides.arguments,
			configuredPath = overrides.configuredPath,
			environmentVariable = overrides.environmentVariable,
			readEnv = overrides.readEnv,
			exists = overrides.exists,
		}
	end

	local function present(paths: { [string]: boolean }): (path: string) -> boolean
		return function(path: string): boolean
			return paths[path] == true
		end
	end

	it("resolves a configured path ahead of the environment and builds the command", function()
		local resolution = Agent.reviewerCli.resolve(resolver {
			configuredPath = "/opt/reviewer/bin/reviewer",
			environmentVariable = "REVIEWER_CLI",
			readEnv = function(): string?
				return "/never/read"
			end,
			exists = present { ["/opt/reviewer/bin/reviewer"] = true },
		})
		expect(resolution.ok):toEqual(true)
		assert(resolution.ok == true)
		local resolved = resolution :: Agent.ReviewerCliResolved
		expect(resolved.source):toEqual "configured"
		expect(resolved.path):toEqual "/opt/reviewer/bin/reviewer"
		expect(resolved.command):toEqual { "/opt/reviewer/bin/reviewer", "exec", "--json" }
	end)

	it("resolves the named environment variable when no path is configured", function()
		local resolution = Agent.reviewerCli.resolve(resolver {
			environmentVariable = "REVIEWER_CLI",
			readEnv = function(name: string): string?
				return if name == "REVIEWER_CLI" then "/usr/local/bin/reviewer" else nil
			end,
			exists = present { ["/usr/local/bin/reviewer"] = true },
		})
		local resolved = resolution :: Agent.ReviewerCliResolved
		expect(resolved.ok):toEqual(true)
		assert(resolved.ok == true)
		expect(resolved.source):toEqual "environment"
		expect(resolved.origin):toEqual "environment variable REVIEWER_CLI"
		expect(resolved.command[1]):toEqual "/usr/local/bin/reviewer"
	end)

	it("refuses by name rather than falling back to a search path", function()
		local unset = Agent.reviewerCli.resolve(resolver {
			environmentVariable = "REVIEWER_CLI",
			readEnv = function(): string?
				return nil
			end,
		}) :: Agent.ReviewerCliRefused
		expect(unset.ok):toEqual(false)
		assert(unset.ok == false)
		expect(unset.refusal):toContain "reviewer"
		expect(unset.refusal):toContain "REVIEWER_CLI is unset or empty"
		expect(unset.refusal):toContain "never falls back to a search path"

		local missing = Agent.reviewerCli.resolve(resolver {
			configuredPath = "/opt/reviewer/bin/reviewer",
			environmentVariable = "REVIEWER_CLI",
			exists = present {},
		}) :: Agent.ReviewerCliRefused
		expect(missing.refusal):toContain "/opt/reviewer/bin/reviewer names no executable file"

		local wrong = Agent.reviewerCli.resolve(resolver {
			environmentVariable = "REVIEWER_CLI",
			readEnv = function(): string?
				return "/nowhere/reviewer"
			end,
			exists = present {},
		}) :: Agent.ReviewerCliRefused
		expect(wrong.refusal):toContain "REVIEWER_CLI names /nowhere/reviewer"

		local unnamed = Agent.reviewerCli.resolve(resolver {}) :: Agent.ReviewerCliRefused
		expect(unnamed.refusal):toContain "neither a configured path nor an environment variable"
		expect(unnamed.refusal):toContain "no configured path and no environment variable"

		local unreadable = Agent.reviewerCli.resolve(resolver {
			environmentVariable = "REVIEWER_CLI",
			readEnv = function(): string?
				error "the host environment is sealed"
			end,
		}) :: Agent.ReviewerCliRefused
		expect(unreadable.refusal):toContain "could not be read"

		local hostless =
			Agent.reviewerCli.resolve(resolver { environmentVariable = "REVIEWER_CLI" }) :: Agent.ReviewerCliRefused
		expect(hostless.refusal):toContain "without a host reader"

		expect(function()
			Agent.reviewerCli.resolve(resolver { executable = "" })
		end):toThrow "naming the executable"

		expect(function()
			Agent.reviewerCli.resolve(resolver { configuredPath = "/bin/reviewer", arguments = { "" } })
		end):toThrow "must be a non-empty string"
	end)
end)

describe("Generate reviewer stream adoption", function()
	local json = require "@std/json"

	local CONTRACT: Agent.ReviewerStreamContract = {
		threadEventType = "thread.started",
		threadIdField = "thread_id",
		answerEventType = "item.completed",
		answerItemType = "agent_message",
		actorPrefix = "reviewer:",
	}

	local PACKET: Agent.ReviewerPacketRef = {
		id = "fixture.packet",
		fingerprint = "gen-fp2-packet",
		candidateFingerprint = "gen-fp2-candidate",
		evidenceFingerprint = "gen-fp2-evidence",
		rubric = { id = "fixture", fingerprint = "rubric-fixture-v1" },
	}

	local function decode(text: string): unknown
		local ok, value = pcall(json.deserialize, text)
		return if ok then value else error("not json", 0)
	end

	local function stream(threadId: string, answer: unknown, ...: string): string
		local lines: { string } = {
			json.serialize { type = "thread.started", thread_id = threadId },
			json.serialize { type = "item.started", item = { type = "reasoning" } },
			json.serialize {
				type = "item.completed",
				item = { type = "agent_message", text = json.serialize(answer :: json.Value) },
			},
		}
		for _, extra in { ... } do
			table.insert(lines, extra)
		end
		return table.concat(lines, "\n") .. "\n"
	end

	local APPROVAL: { [string]: unknown } = { verdict = "approved", certainty = "high", reasons = { "clear" } }

	it("reads one thread and one terminal answer out of an interleaved stream", function()
		local answer, fault =
			Agent.reviewerStream.parse(decode, CONTRACT, stream("thread-a", APPROVAL, "not json at all"))
		expect(fault):toEqual(nil)
		local read = answer :: Agent.ReviewerStreamVerdict
		expect(read.actor):toEqual "reviewer:thread-a"
		expect(read.threadId):toEqual "thread-a"
		expect(read.verdict):toEqual "approved"
		expect(read.certainty):toEqual "high"
		expect(read.reasons):toEqual { "clear" }
	end)

	it("binds one stream and refuses extra or untrustworthy reviewers", function()
		local drafts, fault = Agent.reviewerStream.decisions {
			decode = decode,
			contract = CONTRACT,
			packet = PACKET,
			streams = {
				stream("thread-a", APPROVAL),
			},
			role = "reviewer",
			modelFamily = "fixture-family",
			providerFamily = "fixture-provider",
		}
		expect(fault):toEqual(nil)
		local reviewDrafts = drafts :: { Generate.ReviewDecisionDraft }
		expect(#reviewDrafts):toEqual(1)
		expect(reviewDrafts[1].actor):toEqual "reviewer:thread-a"
		expect(reviewDrafts[1].blind):toEqual(true)
		expect(reviewDrafts[1].context):toEqual "independent"

		local function refusal(options: Agent.ReviewerStreamOptions): string
			local answers, why = Agent.reviewerStream.decisions(options)
			expect(answers):toEqual(nil)
			return why :: string
		end

		expect(refusal {
			decode = decode,
			contract = CONTRACT,
			packet = PACKET,
			streams = { stream("thread-a", APPROVAL), stream("thread-a", APPROVAL) },
			role = "reviewer",
		}):toContain "exactly one review stream"

		expect(refusal {
			decode = decode,
			contract = CONTRACT,
			packet = PACKET,
			streams = { stream("thread-a", { verdict = "maybe", certainty = "high", reasons = { "x" } }) },
			role = "reviewer",
		}):toContain "invalid verdict"

		expect(refusal {
			decode = decode,
			contract = CONTRACT,
			packet = PACKET,
			streams = { stream("thread-a", { verdict = "rejected", certainty = "high", reasons = {} }) },
			role = "reviewer",
		}):toContain "invalid verdict"

		expect(refusal {
			decode = decode,
			contract = CONTRACT,
			packet = PACKET,
			streams = { json.serialize { type = "thread.started", thread_id = "thread-a" } },
			role = "reviewer",
		}):toContain "no thread and terminal answer"

		expect(refusal {
			decode = decode,
			contract = CONTRACT,
			packet = PACKET,
			streams = {
				stream("thread-a", APPROVAL)
					.. json.serialize { type = "thread.started", thread_id = "thread-z" }
					.. "\n",
			},
			role = "reviewer",
		}):toContain "more than one thread"

		expect(refusal {
			decode = decode,
			contract = CONTRACT,
			packet = {
				id = "",
				fingerprint = "",
				candidateFingerprint = "",
				evidenceFingerprint = "",
				rubric = ({} :: unknown) :: Generate.RubricIdentity,
			},
			streams = { stream("thread-a", APPROVAL) },
			role = "reviewer",
		}):toContain "no bound review packet"

		expect(function()
			Agent.reviewerStream.parse(decode, ({ actorPrefix = "" } :: unknown) :: Agent.ReviewerStreamContract, "")
		end):toThrow "must name"
	end)
end)

return nil
