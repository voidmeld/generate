--!strict

local json = require "@std/json"

local Roblox = require "../src/roblox"
local ReferenceInternal = require "../src/roblox/reference-provenance"
local RbxmInternal = require "../src/roblox/rbxm"
local PermissionTypes = require "../src/roblox/permission-grant"
local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local Readback = Roblox.assetReadback
local Permission = Roblox.permissionGrant
local Reference = Roblox.referenceProvenance
local Audit = Roblox.assetAudit
local Rbxm = RbxmInternal

local OWNER: Roblox.AssetReadbackOwner = { creatorType = "Group", creatorId = "4242" }

local function decode(body: string): unknown
	return json.deserialize(body)
end

local function encode(value: unknown): string
	return json.serialize(value :: json.Value)
end

local function digest(bytes: string): string
	local sum = 0
	for index = 1, #bytes do
		sum = (sum * 31 + string.byte(bytes, index)) % 4294967296
	end
	return string.format("%08x", sum)
end

local function record(body: unknown, status: number): Roblox.CloudResponse
	return { ok = status == 200, status = status, body = encode(body) }
end

describe("Roblox.assetReadback", function()
	it("reads the declared creator out of the asset record", function()
		local options: Roblox.AssetReadbackOptions = {
			decode = decode,
			owner = OWNER,
			send = function(): Roblox.CloudResponse
				return record({
					assetId = "77",
					assetType = "Model",
					displayName = "marker",
					state = "Active",
					revisionId = "1",
					moderationResult = { moderationState = "Approved" },
					creationContext = { creator = { groupId = "4242" } },
				}, 200)
			end,
		}
		local answer = Readback.readback(options, "77")
		expect(answer.assetId):toBe "77"
		expect(answer.ownedByDeclaredCreator):toBe(true)
		expect(answer.foreignOwnershipPossible):toBe(false)
		expect(answer.privacy):toBe(Readback.UNOBSERVABLE.privacy)
		expect(answer.source):toBe(Readback.SOURCES.record)
	end)

	it("falls back to the public details read when the record refuses with 403", function()
		local urls: { string } = {}
		local options: Roblox.AssetReadbackOptions = {
			decode = decode,
			owner = OWNER,
			send = function(request: Roblox.CloudRequest): Roblox.CloudResponse
				table.insert(urls, request.url)
				return { ok = false, status = 403, body = "" }
			end,
			sendPublic = function(request: Roblox.CloudRequest): Roblox.CloudResponse
				table.insert(urls, request.url)
				return record({
					AssetId = 77,
					Name = "marker",
					AssetTypeId = 40,
					Creator = { CreatorType = "Group", CreatorTargetId = 4242 },
				}, 200)
			end,
		}
		local answer = Readback.readback(options, "77")
		expect(answer.source):toBe(Readback.SOURCES.details)
		expect(answer.assetType):toBe "MeshPart"
		expect(answer.ownedByDeclaredCreator):toBe(true)
		expect(answer.moderationState):toBe(Readback.UNOBSERVABLE.moderation)
		expect(#urls):toBe(2)
	end)

	it("paces consecutive reads through the injected clock and sleep", function()
		local slept: { number } = {}
		local ticks = { 0, 0, 0 }
		local index = 0
		local options: Roblox.AssetReadbackOptions = {
			decode = decode,
			owner = OWNER,
			paced = true,
			clock = function(): number
				index += 1
				return ticks[index] or 0
			end,
			sleep = function(seconds: number)
				table.insert(slept, seconds)
			end,
			send = function(): Roblox.CloudResponse
				return { ok = false, status = 404, body = "" }
			end,
		}
		Readback.readback(options, "77")
		Readback.readback(options, "78")
		expect(#slept):toBe(1)
		expect(slept[1] > 0):toBe(true)
	end)

	it("never defaults an unparsed record to a passing value", function()
		local options: Roblox.AssetReadbackOptions = {
			decode = decode,
			owner = OWNER,
			send = function(): Roblox.CloudResponse
				return { ok = true, status = 200, body = "not-a-table" }
			end,
		}
		local answer = Readback.readback(options, "77")
		expect(answer.moderationState):toBe "unknown"
		expect(answer.ownedByDeclaredCreator):toBe(false)
		expect(answer.diagnostic ~= ""):toBe(true)
	end)

	it("censuses exactly the ids it was handed", function()
		local seen: { string } = {}
		local options: Roblox.AssetReadbackOptions = {
			decode = decode,
			owner = OWNER,
			send = function(request: Roblox.CloudRequest): Roblox.CloudResponse
				local id = string.match(request.url, "(%d+)$") :: string
				table.insert(seen, id)
				return record({
					assetId = id,
					assetType = "Model",
					state = "Active",
					moderationResult = { moderationState = "Approved" },
					creationContext = { creator = { groupId = if id == "9" then "1" else "4242" } },
				}, 200)
			end,
		}
		local census = Readback.census(options, "7", { "8", "8", "9" })
		expect(census.dependencyCount):toBe(2)
		expect(census.closed):toBe(false)
		expect(#census.foreignOwned):toBe(1)
		expect(#seen):toBe(3)
	end)
end)

describe("Roblox.permissionGrant subject authority", function()
	local function credential(operations: { string }): PermissionTypes.Credential
		return {
			decision = Permission.CREDENTIAL_DECISION,
			operation = "grant",
			nonce = "n",
			freezeCommit = "c",
			authorizedUserId = 5,
			permissionOperations = operations,
		}
	end

	local function authority(answers: unknown): Roblox.PermissionAuthorityOptions
		return {
			decode = decode,
			send = function(request: Roblox.CloudRequest): Roblox.CloudResponse
				for fragment, value in answers :: { [string]: unknown } do
					if string.find(request.url, fragment, 1, true) ~= nil then
						return record(value, 200)
					end
				end
				return { ok = false, status = 404, body = "" }
			end,
		}
	end

	it("refuses malformed credential identity fields before reading authority", function()
		for _, name in { "decision", "operation", "nonce", "freezeCommit" } do
			local value: { [string]: unknown } = {}
			for key, field in credential { "write" } do
				assert(type(key) == "string")
				value[key] = field
			end
			value[name] = false
			local reads = 0
			local options: Roblox.PermissionAuthorityOptions = {
				decode = decode,
				send = function(): Roblox.CloudResponse
					reads += 1
					return { ok = false, status = 500, body = "" }
				end,
			}
			local receipt, reason = Permission.subjectAuthority(options, value, "10", "4242")
			expect(receipt):toBe(nil)
			expect(reason):toBe "subject authority input is malformed"
			expect(reads):toBe(0)
		end
	end)

	it("refuses before any read when the credential scopes do not cover the write", function()
		local reads = 0
		local options: Roblox.PermissionAuthorityOptions = {
			decode = decode,
			send = function(): Roblox.CloudResponse
				reads += 1
				return { ok = false, status = 500, body = "" }
			end,
		}
		local receipt, reason = Permission.subjectAuthority(options, credential { "read" }, "10", "4242")
		expect(reads):toBe(0)
		expect(reason):toBe(Permission.REASONS.scopesUncovered)
		expect(assert(receipt).decision):toBe(Permission.DECISIONS.refused)
	end)

	it("binds a current membership to the authoritative role collection", function()
		local options = authority {
			["/universes/10"] = { path = "universes/10", group = "groups/4242", visibility = "PRIVATE" },
			["/memberships"] = {
				groupMemberships = {
					{
						path = "groups/4242/memberships/m1",
						user = "users/5",
						roles = { "groups/4242/roles/r1" },
					},
				},
			},
			["/roles"] = {
				groupRoles = {
					{ path = "groups/4242/roles/r1", id = "r1", displayName = "Builder", rank = 10 },
				},
			},
		}
		local receipt, reason = Permission.subjectAuthority(options, credential { "read", "write" }, "10", "4242")
		expect(reason):toBe "bound"
		expect(assert(receipt).decision):toBe(Permission.DECISIONS.bound)
		expect(assert(receipt).membership):toBe "CURRENT"
		expect(assert(receipt).assignedRoles[1].name):toBe "Builder"
	end)

	it("refuses a universe that is not owned by the required group", function()
		local options = authority {
			["/universes/10"] = { path = "universes/10", group = "groups/1", visibility = "PRIVATE" },
		}
		local receipt, reason = Permission.subjectAuthority(options, credential { "write" }, "10", "4242")
		expect(receipt):toBe(nil)
		expect(reason):toBe "universe ownership is not the required group"
	end)

	it("reports an absent membership as a refusal receipt rather than a fault", function()
		local options = authority {
			["/universes/10"] = { path = "universes/10", group = "groups/4242", visibility = "PRIVATE" },
			["/memberships"] = { groupMemberships = {} },
		}
		local receipt, reason = Permission.subjectAuthority(options, credential { "write" }, "10", "4242")
		expect(reason):toBe(Permission.REASONS.membershipAbsent)
		expect(assert(receipt).membership):toBe "ABSENT"
	end)
end)

describe("Roblox.permissionGrant census", function()
	local function row(assetId: string, creatorType: string, creatorId: string, state: string): Roblox.AssetRecord
		return {
			assetId = assetId,
			path = "",
			assetType = "unknown",
			displayName = "",
			ownedByDeclaredCreator = false,
			foreignOwnershipPossible = true,
			privacy = "unknown",
			revisionId = "",
			creatorType = creatorType,
			creatorId = creatorId,
			moderationState = state,
			state = "Active",
			status = 200,
			diagnostic = "",
			source = Readback.SOURCES.record,
		}
	end

	it("partitions owned, external, and foreign-group rows", function()
		local partition = Permission.census({
			row("1", "Group", "4242", "Approved"),
			row("2", "User", "9", "Active"),
			row("3", "Group", "77", "Approved"),
		}, OWNER)
		expect(partition.grantAssetIds[1]):toBe "1"
		expect(partition.externalAssetIds[1]):toBe "2"
		expect(#partition.foreignOwned):toBe(1)
		expect(partition.closed):toBe(false)
	end)

	it("holds a row whose moderation state is not approved", function()
		local partition = Permission.census({ row("1", "Group", "4242", "Reviewing") }, OWNER)
		expect(#partition.unresolved):toBe(1)
		expect(partition.closed):toBe(false)
	end)

	it("closes on a wholly owned and approved set", function()
		local partition = Permission.census({ row("1", "Group", "4242", "Approved") }, OWNER)
		expect(partition.closed):toBe(true)
	end)
end)

describe("Roblox.permissionGrant transaction", function()
	local function store(): (Roblox.PermissionReceiptStore, { [string]: string })
		local files: { [string]: string } = {}
		return {
			read = function(path: string): string?
				return files[path]
			end,
			write = function(path: string, bytes: string)
				files[path] = bytes
			end,
			list = function(root: string): { string }
				local paths: { string } = {}
				for path in files do
					if string.sub(path, 1, #root) == root then
						table.insert(paths, path)
					end
				end
				table.sort(paths)
				return paths
			end,
			ensure = function() end,
		},
			files
	end

	local function transaction(
		receipts: Roblox.PermissionReceiptStore,
		assetIds: { string },
		attempt: (prepared: Roblox.PermissionPrepared) -> PermissionTypes.AttemptResult
	): Roblox.PermissionTransaction
		return {
			store = receipts,
			encode = encode,
			decode = decode,
			digest = digest,
			contract = "example.permissions.v1",
			outputRoot = "receipts",
			universeId = "10",
			owner = OWNER,
			sourceCommit = string.rep("a", 40),
			closureSha256 = "closure",
			grantAssetIds = assetIds,
			chunkSize = 2,
			context = { channel = "example" },
			destination = {
				endpoint = "https://example.invalid/permissions",
				method = "PATCH",
				headerNames = { "Accept", "Content-Type", "x-api-key" },
			},
			terminal = {
				status = "PATCH_COMPLETE_AWAITING_PROOF",
				reason = "delivery proof pending",
				message = "patch complete; delivery proof pending",
			},
			prepare = function(_universeId: string, ids: { string }): Roblox.PermissionPrepared
				return {
					endpoint = "https://example.invalid/permissions",
					method = "PATCH",
					body = "body:" .. table.concat(ids, ","),
					headerNames = { "Accept", "Content-Type", "x-api-key" },
					requestedAssetIds = ids,
				}
			end,
			attempt = attempt,
		}
	end

	it("writes a write-ahead before every attempted chunk and a terminal after it", function()
		local receipts, files = store()
		local calls = 0
		local receipt, reason =
			Permission.grant(transaction(receipts, { "1", "2", "3" }, function(): PermissionTypes.AttemptResult
				calls += 1
				return { status = 200, successAssetIds = {}, complete = true, diagnostic = "", responseBody = "" }
			end))
		expect(calls):toBe(2)
		expect(reason):toBe "patch complete; delivery proof pending"
		expect(assert(receipt).status):toBe "PATCH_COMPLETE_AWAITING_PROOF"
		expect(assert(receipt).reason):toBe "delivery proof pending"
		expect(assert(assert(receipt).outboundDestination).endpoint):toBe "https://example.invalid/permissions"
		local writeAheads = 0
		for path in files do
			if string.find(path, "write-ahead", 1, true) ~= nil then
				writeAheads += 1
			end
		end
		expect(writeAheads):toBe(2)
	end)

	it("holds at the failing chunk instead of continuing", function()
		local receipts = store()
		local calls = 0
		local receipt, reason =
			Permission.grant(transaction(receipts, { "1", "2", "3" }, function(): PermissionTypes.AttemptResult
				calls += 1
				if calls == 1 then
					return { status = 200, successAssetIds = {}, complete = true, diagnostic = "", responseBody = "" }
				end
				return {
					status = 500,
					successAssetIds = {},
					complete = false,
					diagnostic = "refused",
					responseBody = "",
				}
			end))
		expect(calls):toBe(2)
		expect(assert(receipt).status):toBe "HOLD"
		expect(string.find(reason, "resume at chunk 2", 1, true) ~= nil):toBe(true)
	end)

	it("resumes valid persisted chunks without repeating a granted chunk", function()
		local receipts = store()
		local calls = 0
		local plan = transaction(receipts, { "1", "2", "3" }, function(): PermissionTypes.AttemptResult
			calls += 1
			return {
				status = if calls == 2 then 500 else 200,
				successAssetIds = {},
				complete = calls ~= 2,
				diagnostic = "",
				responseBody = "",
			}
		end)
		local first = assert(Permission.grant(plan))
		expect(first.status):toBe "HOLD"
		local resumed = assert(Permission.grant(plan))
		expect(resumed.status):toBe "PATCH_COMPLETE_AWAITING_PROOF"
		expect(calls):toBe(3)
		expect(#assert(resumed.chunkOutcomes)):toBe(2)
	end)

	it("refuses malformed persisted chunk field shapes before another attempt", function()
		local mutations: { (value: { [string]: unknown }) -> () } = {
			function(value)
				value.sourceCommit = 12
			end,
			function(value)
				(value.chunk :: { [string]: unknown }).attempt = "first"
			end,
			function(value)
				(value.patch :: { [string]: unknown }).status = "retry"
			end,
			function(value)
				(value.patch :: { [string]: unknown }).successAssetIds = { false }
			end,
			function(value)
				local outcome = value.chunkOutcome :: { [string]: unknown }
				(outcome.patch :: { [string]: unknown }).responseBody = false
			end,
		}
		for _, mutate in mutations do
			local receipts, files = store()
			local calls = 0
			local plan = transaction(receipts, { "1" }, function(): PermissionTypes.AttemptResult
				calls += 1
				return { status = 500, successAssetIds = {}, complete = false, diagnostic = "retry", responseBody = "" }
			end)
			local first = assert(Permission.grant(plan))
			local path = assert(first.terminalPath)
			local value = decode(files[path]) :: { [string]: unknown }
			mutate(value)
			files[path] = encode(value)
			local receipt, reason = Permission.grant(plan)
			expect(receipt):toBe(nil)
			expect(string.find(reason, "chunk receipt is malformed", 1, true) ~= nil):toBe(true)
			expect(calls):toBe(1)
		end
	end)

	it("refuses a retry once the transaction has a durable terminal receipt", function()
		local receipts = store()
		local function run(): (PermissionTypes.Receipt?, string)
			return Permission.grant(transaction(receipts, { "1" }, function(): PermissionTypes.AttemptResult
				return { status = 200, successAssetIds = {}, complete = true, diagnostic = "", responseBody = "" }
			end))
		end
		run()
		local receipt, reason = run()
		expect(receipt):toBe(nil)
		expect(reason):toBe "transaction already has durable state; retry refused"
	end)

	it("refuses an outbound request that does not bind the ordered chunk", function()
		local receipts = store()
		local plan = transaction(receipts, { "1" }, function(): PermissionTypes.AttemptResult
			return { status = 200, successAssetIds = {}, complete = true, diagnostic = "", responseBody = "" }
		end)
		plan.prepare = function(): Roblox.PermissionPrepared
			return {
				endpoint = "https://example.invalid/permissions",
				method = "PATCH",
				body = "body",
				headerNames = { "Accept" },
				requestedAssetIds = { "9" },
			}
		end
		local receipt, reason = Permission.grant(plan)
		expect(receipt):toBe(nil)
		expect(string.find(reason, "outbound request preparation refused", 1, true) ~= nil):toBe(true)
	end)

	it("refuses an outbound request whose header names differ from the destination contract", function()
		local receipts = store()
		local plan = transaction(receipts, { "1" }, function(): PermissionTypes.AttemptResult
			return { status = 200, successAssetIds = {}, complete = true, diagnostic = "", responseBody = "" }
		end)
		plan.prepare = function(_universeId: string, ids: { string }): Roblox.PermissionPrepared
			return {
				endpoint = "https://example.invalid/permissions",
				method = "PATCH",
				body = "body",
				headerNames = { "Accept", "Content-Type", "Authorization" },
				requestedAssetIds = ids,
			}
		end
		local receipt, reason = Permission.grant(plan)
		expect(receipt):toBe(nil)
		expect(string.find(reason, "outbound request preparation refused", 1, true) ~= nil):toBe(true)
	end)

	it("refuses an outbound request whose endpoint differs from the destination contract", function()
		local receipts = store()
		local plan = transaction(receipts, { "1" }, function(): PermissionTypes.AttemptResult
			return { status = 200, successAssetIds = {}, complete = true, diagnostic = "", responseBody = "" }
		end)
		plan.prepare = function(_universeId: string, ids: { string }): Roblox.PermissionPrepared
			return {
				endpoint = "https://elsewhere.invalid/permissions",
				method = "PATCH",
				body = "body",
				headerNames = { "Accept", "Content-Type", "x-api-key" },
				requestedAssetIds = ids,
			}
		end
		local receipt, reason = Permission.grant(plan)
		expect(receipt):toBe(nil)
		expect(string.find(reason, "outbound request preparation refused", 1, true) ~= nil):toBe(true)
	end)

	it("refuses a transaction that carries no destination contract", function()
		local receipts = store()
		local plan = transaction(receipts, { "1" }, function(): PermissionTypes.AttemptResult
			return { status = 200, successAssetIds = {}, complete = true, diagnostic = "", responseBody = "" }
		end)
		plan.destination = (nil :: unknown) :: Roblox.PermissionDestination
		local receipt, reason = Permission.grant(plan)
		expect(receipt):toBe(nil)
		expect(reason):toBe "destination contract is malformed"
	end)

	it("refuses a transaction that carries no terminal contract", function()
		local receipts = store()
		local plan = transaction(receipts, { "1" }, function(): PermissionTypes.AttemptResult
			return { status = 200, successAssetIds = {}, complete = true, diagnostic = "", responseBody = "" }
		end)
		plan.terminal = (nil :: unknown) :: Roblox.PermissionTerminal
		local receipt, reason = Permission.grant(plan)
		expect(receipt):toBe(nil)
		expect(reason):toBe "terminal contract is malformed"
	end)

	it("chunks the grant set in declared order", function()
		local planned = Permission.chunks({ "1", "2", "3", "4", "5" }, 2)
		expect(#planned):toBe(3)
		expect(planned[3][1]):toBe "5"
	end)
end)

describe("Roblox.referenceProvenance", function()
	local MANIFEST = table.concat({
		"{",
		'  "reference_images": {},',
		'  "assets": {}',
		"}",
	}, "\n")

	local function config(): Roblox.ReferenceConfig
		return {
			owner = OWNER,
			sections = { "reference_images", "assets" },
			referenceSection = "reference_images",
			manifestPath = "manifest.json",
			renderedPath = "baked.luau",
			lineagePath = "lineage.luau",
			referenceRoot = "refart/",
			render = function(): string
				return "baked"
			end,
		}
	end

	local function codecs(): Roblox.ReferenceCodecs
		return { decode = decode, encode = encode, digest = digest }
	end

	local function files(
		text: string,
		overrides: { [string]: string }?,
		list: ((string) -> { string })?
	): Roblox.ReferenceFiles
		local present: { [string]: string } = {
			["manifest.json"] = text,
			["baked.luau"] = "baked",
			["lineage.luau"] = 'source_path = "refart/image.png", tool = "t", model = "m", date = "d", sha256 = "0001b229"',
			["refart/image.png"] = "png",
			["prompts/image.txt"] = "prompt text",
			["receipts/verdict.json"] = "verdict",
		}
		if overrides ~= nil then
			for path, value in overrides do
				present[path] = value
			end
		end
		return {
			read = function(path: string): string
				return present[path] or error("absent " .. path)
			end,
			write = function(path: string, bytes: string)
				present[path] = bytes
			end,
			exists = function(path: string): boolean
				return present[path] ~= nil
			end,
			list = list,
		}
	end

	local function draft(): Roblox.ReferenceDraft
		return {
			key = "image",
			committedPath = "refart/image.png",
			promptPath = "prompts/image.txt",
			reviewerVerdictIds = { "reviewer-a" },
			reviewerVerdictReceipt = "receipts/verdict.json",
			reviewerVerdictAnchor = "anchor",
			disposition = "reference_only",
			imageAssetId = 77,
			sourceAssetId = 78,
			readbackReceipt = "receipts/verdict.json",
			readback = {
				assetId = "77",
				creatorType = "Group",
				creatorId = "4242",
				moderationState = "Approved",
				closed = true,
			},
		}
	end

	it("records a reference row with one reviewer receipt", function()
		local outcome = Reference.record(config(), codecs(), files(MANIFEST), draft())
		expect(outcome.diagnostic):toBe ""
		expect(assert(outcome.row).image_asset_id):toBe(77)
		expect(assert(outcome.row).source_sha256):toBe "0001b229"
		expect(assert(outcome.row).generation_tool):toBe "t"
		expect(outcome.rowCount):toBe(1)
	end)

	it("refuses missing, extra and duplicate reviewer verdicts", function()
		for _, ids in { {}, { "reviewer-a", "reviewer-b" }, { "reviewer-a", "reviewer-a" } } do
			local candidate = draft()
			candidate.reviewerVerdictIds = ids
			local outcome = Reference.record(config(), codecs(), files(MANIFEST), candidate)
			expect(outcome.diagnostic):toContain "exactly one independent reviewer verdict id"
			expect(outcome.row):toBe(nil)
		end
	end)

	it("refuses an empty reviewer identity", function()
		local unnamed = draft()
		unnamed.reviewerVerdictIds = { "" }
		expect(Reference.record(config(), codecs(), files(MANIFEST), unnamed).diagnostic):toContain "non-empty string"
	end)

	it("refuses a readback that does not prove the declared creator", function()
		local foreign = draft()
		foreign.readback.creatorId = "1"
		local outcome = Reference.record(config(), codecs(), files(MANIFEST), foreign)
		expect(outcome.diagnostic):toBe "the readback does not prove the declared creator"
	end)

	it("refuses a receipt path that no fresh checkout carries", function()
		local ignored = draft()
		ignored.readbackReceipt = ".local/verdict.json"
		local outcome = Reference.record(config(), codecs(), files(MANIFEST), ignored)
		expect(string.find(outcome.diagnostic, "is not a committed path", 1, true) ~= nil):toBe(true)
	end)

	it("refuses a reference image outside the declared reference root", function()
		local outside = draft()
		outside.committedPath = "elsewhere/image.png"
		local outcome = Reference.record(config(), codecs(), files(MANIFEST), outside)
		expect(string.find(outcome.diagnostic, "absent", 1, true) ~= nil):toBe(true)
	end)

	it("never overwrites an existing key", function()
		local occupied = table.concat({
			"{",
			'  "reference_images": {',
			'    "image": { "id": "image" }',
			"  },",
			'  "assets": {}',
			"}",
		}, "\n")
		local outcome = Reference.record(config(), codecs(), files(occupied), draft())
		expect(string.find(outcome.diagnostic, "never overwritten", 1, true) ~= nil):toBe(true)
	end)

	it("holds the whole act when the renderer no longer reproduces the tracked table", function()
		local drifting = config()
		drifting.render = function(): string
			return "drifted"
		end
		local outcome = Reference.record(drifting, codecs(), files(MANIFEST), draft())
		expect(string.find(outcome.diagnostic, "no longer reproduces", 1, true) ~= nil):toBe(true)
	end)

	it("refuses a reference image that claims the terminal disposition before its model exists", function()
		local terminal = draft()
		terminal.disposition = "accepted"
		local outcome = Reference.record(config(), codecs(), files(MANIFEST), terminal)
		expect(string.find(outcome.diagnostic, "terminal disposition", 1, true) ~= nil):toBe(true)
	end)

	it("refuses a reference image whose committed bytes do not match the lineage row's sha256", function()
		local outcome = Reference.record(
			config(),
			codecs(),
			files(MANIFEST, {
				["lineage.luau"] = 'source_path = "refart/image.png", tool = "t", model = "m", date = "d", sha256 = "deadbeef"',
			}),
			draft()
		)
		expect(string.find(outcome.diagnostic, "do not match the lineage row's sha256", 1, true) ~= nil):toBe(true)
	end)

	it("resolves the reference image's row across a declared list of lineage files", function()
		local multi = config()
		multi.lineagePath = { "lineage-a.luau", "lineage-b.luau" }
		local outcome = Reference.record(
			multi,
			codecs(),
			files(MANIFEST, {
				["lineage-a.luau"] = 'source_path = "refart/other.png", tool = "t", model = "m", date = "d", sha256 = "0"',
				["lineage-b.luau"] = 'source_path = "refart/image.png", tool = "t", model = "m", date = "d", sha256 = "0001b229"',
			}),
			draft()
		)
		expect(outcome.diagnostic):toBe ""
		expect(assert(outcome.row).lineage_path):toBe "lineage-b.luau"
	end)

	it("refuses with the searched list when no lineage file names the reference image", function()
		local multi = config()
		multi.lineagePath = { "lineage-a.luau", "lineage-b.luau" }
		local outcome = Reference.record(
			multi,
			codecs(),
			files(MANIFEST, {
				["lineage-a.luau"] = 'source_path = "refart/other.png", tool = "t", model = "m", date = "d", sha256 = "0"',
				["lineage-b.luau"] = 'source_path = "refart/another.png", tool = "t", model = "m", date = "d", sha256 = "0"',
			}),
			draft()
		)
		expect(string.find(outcome.diagnostic, "no lineage file names a row", 1, true) ~= nil):toBe(true)
		expect(string.find(outcome.diagnostic, "lineage-a.luau", 1, true) ~= nil):toBe(true)
		expect(string.find(outcome.diagnostic, "lineage-b.luau", 1, true) ~= nil):toBe(true)
	end)

	it("refuses when two lineage files name the same plate", function()
		local multi = config()
		multi.lineagePath = { "lineage-a.luau", "lineage-b.luau" }
		local row = 'source_path = "refart/image.png", tool = "t", model = "m", date = "d", sha256 = "0001b229"'
		local outcome = Reference.record(
			multi,
			codecs(),
			files(MANIFEST, { ["lineage-a.luau"] = row, ["lineage-b.luau"] = row }),
			draft()
		)
		expect(string.find(outcome.diagnostic, "more than one lineage file names a row", 1, true) ~= nil):toBe(true)
		expect(string.find(outcome.diagnostic, "lineage-a.luau", 1, true) ~= nil):toBe(true)
		expect(string.find(outcome.diagnostic, "lineage-b.luau", 1, true) ~= nil):toBe(true)
	end)

	it("resolves the reference image's row across a lineage directory via files.list", function()
		local dirConfig = config()
		dirConfig.lineagePath = "lineage-dir"
		local outcome = Reference.record(
			dirConfig,
			codecs(),
			files(MANIFEST, {
				["lineage-dir/a.luau"] = 'source_path = "refart/other.png", tool = "t", model = "m", date = "d", sha256 = "0"',
				["lineage-dir/b.luau"] = 'source_path = "refart/image.png", tool = "t", model = "m", date = "d", sha256 = "0001b229"',
			}, function(root: string): { string }
				expect(root):toBe "lineage-dir"
				return { "lineage-dir/a.luau", "lineage-dir/b.luau" }
			end),
			draft()
		)
		expect(outcome.diagnostic):toBe ""
		expect(assert(outcome.row).lineage_path):toBe "lineage-dir/b.luau"
	end)

	it("banks a lineage row's inline prompt as the prompt of record", function()
		local inline = draft()
		inline.promptPath = nil
		local outcome = Reference.record(
			config(),
			codecs(),
			files(MANIFEST, {
				["lineage.luau"] = 'source_path = "refart/image.png", tool = "t", model = "m", prompt = "inline prompt text", date = "d", sha256 = "0001b229"',
			}),
			inline
		)
		expect(outcome.diagnostic):toBe ""
		expect(assert(outcome.row).prompt):toBe "inline prompt text"
		expect(assert(outcome.row).prompt_path):toBe(nil)
		expect(assert(outcome.row).prompt_sha256):toBe(digest "inline prompt text")
	end)

	it("reads an inline lineage prompt written as a long-bracket string", function()
		local inline = draft()
		inline.promptPath = nil
		local outcome = Reference.record(
			config(),
			codecs(),
			files(MANIFEST, {
				["lineage.luau"] = 'source_path = "refart/image.png", tool = "t", model = "m", prompt = [[line one\nline "two"]], date = "d", sha256 = "0001b229"',
			}),
			inline
		)
		expect(outcome.diagnostic):toBe ""
		expect(assert(outcome.row).prompt):toBe 'line one\nline "two"'
		expect(assert(outcome.row).prompt_sha256):toBe(digest 'line one\nline "two"')
	end)

	it("reads an inline lineage prompt written with a `[=[` long-bracket level", function()
		local inline = draft()
		inline.promptPath = nil
		local outcome = Reference.record(
			config(),
			codecs(),
			files(MANIFEST, {
				["lineage.luau"] = 'source_path = "refart/image.png", tool = "t", model = "m", prompt = [=[a "quoted" [[nested]] prompt]=], date = "d", sha256 = "0001b229"',
			}),
			inline
		)
		expect(outcome.diagnostic):toBe ""
		expect(assert(outcome.row).prompt):toBe 'a "quoted" [[nested]] prompt'
	end)

	it("refuses a draft with neither a prompt path nor an inline lineage prompt", function()
		local neither = draft()
		neither.promptPath = nil
		local outcome = Reference.record(config(), codecs(), files(MANIFEST), neither)
		expect(string.find(outcome.diagnostic, "committed prompt path or an inline lineage prompt", 1, true) ~= nil):toBe(
			true
		)
	end)
end)

describe("Roblox.assetAudit", function()
	local CONFIG: Roblox.AssetAuditConfig = {
		referenceSection = "references",
		modelSection = "models",
		terminalDisposition = "accepted",
		ownedProvenance = "owned",
		eligibilityFields = { "eligible_primary", "eligible_secondary" },
	}

	local function files(tree: { [string]: string }): Roblox.ReferenceFiles
		return {
			read = function(path: string): string
				return tree[path] or error("absent: " .. path)
			end,
			write = function() end,
			exists = function(path: string): boolean
				return tree[path] ~= nil
			end,
		}
	end

	local function reference(overrides: unknown): Roblox.AssetAuditReference
		local row: Roblox.AssetAuditReference = {
			committed_source_path = "assets/image.png",
			source_sha256 = digest "image",
			prompt_path = "assets/plate.txt",
			prompt_sha256 = digest "prompt",
			lineage_path = "ops/generation.json",
			reviewer_verdict_ids = { "verdict-1" },
			reviewer_verdict_receipt = "ops/safety.json",
			reviewer_verdict_anchor = "anchor",
			image_readback_receipt = "ops/readback.json",
			image_asset_id = 77,
			subject = "subject",
			family = "family",
			group = "group",
			rights_basis = "owned",
			disposition = "accepted",
		}
		for key, value in overrides :: { [string]: unknown } do
			row[key] = value
		end
		return row
	end

	local function model(overrides: unknown): Roblox.AssetAuditModel
		local row: Roblox.AssetAuditModel = {
			reference_sha256 = digest "image",
			reference_image_asset_id = 77,
			model_prompt_sha256 = digest "model",
			comparison_verdict_receipt = "ops/ab.json",
			model_uuid = "uuid-1",
		}
		for key, value in overrides :: { [string]: unknown } do
			row[key] = value
		end
		return row
	end

	local function tree(): { [string]: string }
		return {
			["assets/image.png"] = "image",
			["assets/plate.txt"] = "prompt",
			["ops/generation.json"] = "{}",
			["ops/safety.json"] = "{}",
			["ops/readback.json"] = "{}",
			["ops/ab.json"] = "{}",
		}
	end

	local function violations(
		references: { [string]: Roblox.AssetAuditReference },
		models: { [string]: Roblox.AssetAuditModel },
		paths: { [string]: string }?
	): { string }
		return Audit.referenceViolations {
			config = CONFIG,
			files = files(paths or tree()),
			digest = digest,
			references = references,
			models = models,
		}
	end

	it("closes a reference and its conditioned model without a violation", function()
		expect(#violations({ first_row = reference {} }, { second_row = model {} })):toBe(0)
	end)

	it("closes a reference whose prompt of record is inline with a matching sha256", function()
		local found = violations({
			first_row = reference { prompt_path = "", prompt = "prompt", prompt_sha256 = digest "prompt" },
		}, { second_row = model {} })
		expect(#found):toBe(0)
	end)

	it("refuses an inline prompt of record whose sha256 does not match", function()
		local found = violations({
			first_row = reference { prompt_path = "", prompt = "prompt", prompt_sha256 = digest "wrong" },
		}, { second_row = model {} })
		expect(#found):toBe(1)
		expect(found[1]):toBe 'references["first_row"] inline prompt hash drift'
	end)

	it("refuses a reference that carries neither prompt_path nor an inline prompt", function()
		local found = violations({
			first_row = reference { prompt_path = "" },
		}, { second_row = model {} })
		expect(#found):toBe(1)
		expect(found[1]):toBe 'references["first_row"] missing prompt_path or prompt'
	end)

	it("names a gitignored receipt path under the section label the consumer declared", function()
		local paths = tree()
		paths[".ops/safety.json"] = "{}"
		local found = violations({ first_row = reference { reviewer_verdict_receipt = ".ops/safety.json" } }, {
			second_row = model {},
		}, paths)
		expect(#found):toBe(1)
		expect(found[1]):toBe 'references["first_row"] reviewer_verdict_receipt is a hidden path at .ops/safety.json'
	end)

	it("refuses a tracked original whose bytes no longer digest to the recorded hash", function()
		local paths = tree()
		paths["assets/image.png"] = "drifted"
		local found = violations({ first_row = reference {} }, { second_row = model {} }, paths)
		expect(#found):toBe(1)
		expect(found[1]):toBe 'references["first_row"] original hash drift'
	end)

	it("refuses an accepted reference that no conditioned model links back to", function()
		local found = violations({ first_row = reference {} }, {})
		expect(#found):toBe(2)
		expect(found[1]):toBe 'references["first_row"] missing conditioned-model reverse link by Image asset ID'
	end)

	it("refuses a model whose reference pair resolves to no single reference", function()
		local found = violations({ first_row = reference {} }, {
			second_row = model {},
			other_model = model { reference_image_asset_id = 78, model_uuid = "uuid-2" },
		})
		expect(#found):toBe(2)
		expect(found[1]):toBe 'models["other_model"] reference SHA/Image ID pair does not resolve to one reference image'
	end)

	it("refuses eligibility granted without accepted owned provenance", function()
		local found = violations({
			first_row = reference { eligible_primary = true, rights_basis = "licensed" },
		}, { second_row = model {} })
		expect(#found):toBe(1)
		expect(found[1]):toBe 'references["first_row"] grants eligibility without the terminal disposition and owned rights'
	end)

	it("reports a gitignored path and a baker that no longer reproduces the tracked table", function()
		expect(ReferenceInternal.hiddenPath ".ops/receipt.json"):toBe(true)
		expect(ReferenceInternal.hiddenPath "ops/receipt.json"):toBe(false)
		local config = {
			render = function(): string
				return "baked"
			end,
		}
		expect(ReferenceInternal.rendererParity(config, { decode = decode }, "{}", "baked")):toBe(nil)
		expect(ReferenceInternal.rendererParity(config, { decode = decode }, "{}", "stale") ~= nil):toBe(true)
	end)

	it("refuses an input that carries no file reader", function()
		local ok = pcall(function()
			local input: unknown = { config = CONFIG, digest = digest, references = {}, models = {} }
			Audit.referenceViolations(input :: Roblox.AssetAuditInput)
		end)
		expect(ok):toBe(false)
	end)
end)

describe("Roblox.rbxm", function()
	local function u32(value: number): string
		return string.pack("<I4", value)
	end

	local function i32(value: number): string
		return string.pack("<i4", value)
	end

	local function lengthPrefixed(value: string): string
		return u32(#value) .. value
	end

	local function interleaved(values: { number }): string
		local bytes: { string } = {}
		for shift = 24, 0, -8 do
			for _, value in values do
				table.insert(bytes, string.char(bit32.band(bit32.rshift(value, shift), 255)))
			end
		end
		return table.concat(bytes)
	end

	local function chunk(name: string, payload: string): string
		return name .. u32(0) .. u32(#payload) .. string.rep("\0", 4) .. payload
	end

	local function header(classCount: number, instanceCount: number): string
		return Rbxm.MAGIC .. string.pack("<I2", 0) .. u32(classCount) .. u32(instanceCount) .. string.rep("\0", 8)
	end

	local function fixture(): string
		local instClass = i32(0) .. lengthPrefixed "SurfaceAppearance" .. "\0" .. i32(2) .. interleaved { 0, 2 }
		local instFolder = i32(1) .. lengthPrefixed "Folder" .. "\0" .. i32(1) .. interleaved { 4 }
		local names = i32(0)
			.. lengthPrefixed "Name"
			.. "\1"
			.. lengthPrefixed "SurfaceAppearance"
			.. lengthPrefixed "SurfaceAppearance"
		local textures = i32(0)
			.. lengthPrefixed "TexturePack"
			.. "\1"
			.. lengthPrefixed "rbxassetid://909"
			.. lengthPrefixed ""
		local colorMaps = i32(0)
			.. lengthPrefixed "ColorMapContent"
			.. "\34"
			.. interleaved { 2, 0 }
			.. u32(1)
			.. lengthPrefixed "rbxassetid://4242"
			.. u32(0)
			.. u32(0)
		local shared = i32(0) .. lengthPrefixed "HSRData" .. "\28" .. interleaved { 0, 0 }
		local strength = i32(0) .. lengthPrefixed "EmissiveStrength" .. "\4" .. string.rep("\0", 8)
		local folderMesh = i32(1) .. lengthPrefixed "MeshId" .. "\1" .. lengthPrefixed "55501"
		local sstr = u32(0) .. u32(1) .. string.rep("\0", 16) .. lengthPrefixed "rbxassetid://777"
		return table.concat {
			header(2, 3),
			chunk("SSTR", sstr),
			chunk("INST", instClass),
			chunk("INST", instFolder),
			chunk("PROP", names),
			chunk("PROP", textures),
			chunk("PROP", colorMaps),
			chunk("PROP", shared),
			chunk("PROP", strength),
			chunk("PROP", folderMesh),
			chunk("END\0", "</roblox>"),
		}
	end

	it("decompresses lz4 literals, matches, and length extensions", function()
		local block = "\53" .. "abc" .. string.pack("<I2", 3) .. "\16" .. "X"
		local decoded = Rbxm.decompressLz4(buffer.fromstring(block), 13)
		expect(buffer.tostring(decoded)):toBe "abcabcabcabcX"

		local literals = string.rep("z", 20)
		local extended = "\240\5" .. literals
		local long = Rbxm.decompressLz4(buffer.fromstring(extended), 20)
		expect(buffer.tostring(long)):toBe(literals)
	end)

	it("refuses bytes without the binary signature", function()
		expect(Rbxm.isBinary '<roblox version="4"><Item/></roblox>'):toBe(false)
		local document = Rbxm.read '<roblox version="4"><Item/></roblox>'
		expect(document.ok):toBe(false)
		assert(document.ok == false)
		expect(document.assetIds):toEqual {}
		expect(document.diagnostics):toEqual { "rbxm: missing binary signature" }
		local tree = Rbxm.instances '<roblox version="4"><Item/></roblox>'
		expect(tree.ok):toBe(false)
		assert(tree.ok == false)
		expect(#tree.instances):toBe(0)
	end)

	it("collects string, Content, and SharedString ids from a hand-built container", function()
		local bytes = fixture()
		expect(Rbxm.isBinary(bytes)):toBe(true)
		local document = Rbxm.read(bytes)
		expect(document.ok):toBe(true)
		assert(document.ok == true)
		expect(document.assetIds):toEqual { 777, 909, 4242, 55501 }
		expect(#document.classes):toBe(2)
		expect(document.classes[1].className):toBe "Folder"
		expect(document.classes[2].className):toBe "SurfaceAppearance"
		local byId: { [number]: Roblox.RbxmReference } = {}
		for _, reference in document.references do
			byId[reference.assetId] = reference
		end
		expect(byId[4242].property):toBe "ColorMapContent"
		expect(byId[4242].kind):toBe "content"
		expect(byId[4242].className):toBe "SurfaceAppearance"
		expect(byId[909].kind):toBe "string"
		expect(byId[777].property):toBe "HSRData"
		expect(byId[777].kind):toBe "shared"
		expect(byId[55501].className):toBe "Folder"
		expect(byId[55501].uri):toBe "55501"
	end)

	it("reads named instances with their content slots, empty slots kept as empty strings", function()
		local tree = Rbxm.instances(fixture())
		expect(tree.ok):toBe(true)
		assert(tree.ok == true)
		expect(#tree.instances):toBe(3)
		local first = tree.instances[1]
		expect(first.className):toBe "SurfaceAppearance"
		expect(first.name):toBe "SurfaceAppearance"
		expect(first.parent):toBe(-1)
		expect(first.content.ColorMapContent):toBe "rbxassetid://4242"
		expect(first.content.TexturePack):toBe "rbxassetid://909"
		local second = tree.instances[2]
		expect(second.content.ColorMapContent):toBe ""
		expect(second.content.TexturePack):toBe ""
		expect(tree.instances[3].content.MeshId):toBe "55501"
		expect(Rbxm.instancePath(tree, 0)):toBe "SurfaceAppearance"
	end)

	it("names the content-shaped property set both readers share", function()
		expect(Rbxm.CONTENT_PROPERTY_NAMES.MeshContent):toBe(true)
		expect(Rbxm.CONTENT_PROPERTY_NAMES.CageMeshContent):toBe(true)
		expect(Rbxm.CONTENT_PROPERTY_NAMES.EmissiveStrength):toBe(nil)
	end)

	it("names a truncated chunk instead of raising", function()
		local truncated = string.sub(fixture(), 1, 48)
		local document = Rbxm.read(truncated)
		expect(document.ok):toBe(false)
		assert(document.ok == false)
		expect(#document.diagnostics):toBe(1)
		expect(string.match(document.diagnostics[1], "truncated chunk") ~= nil):toBe(true)
	end)
end)

return nil
