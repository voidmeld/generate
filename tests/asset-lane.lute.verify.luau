--!strict

local json = require "@std/json"
local Lute = require "../.lute/dependencies/verify/src/lute"

local Roblox = require "../src/roblox"
local RbxmInternal = require "../src/roblox/rbxm"
local PermissionTypes = require "../src/roblox/permission-grant"
local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local Readback = Roblox.assetReadback
local Permission = Roblox.permissionGrant
local Audit = Roblox.assetAudit
local Rbxm = RbxmInternal

local OWNER: Roblox.AssetReadbackOwner = { creatorType = "Group", creatorId = "4242" }

local function decode(body: string): unknown
	return json.deserialize(body)
end

local function encode(value: unknown): string
	return Lute.encode(value)
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
				local id = assert(string.match(request.url, "(%d+)$"))
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

	local function authority(answers: { [string]: unknown }): Roblox.PermissionAuthorityOptions
		return {
			decode = decode,
			send = function(request: Roblox.CloudRequest): Roblox.CloudResponse
				for fragment, value in answers do
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
			local original: unknown = credential { "write" }
			assert(type(original) == "table")
			for key, field in original do
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

	it("refuses a public universe unless the caller allows public visibility", function()
		local routes = {
			["/universes/10"] = { path = "universes/10", group = "groups/4242", visibility = "PUBLIC" },
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
		local refused, refusedReason =
			Permission.subjectAuthority(authority(routes), credential { "read", "write" }, "10", "4242")
		expect(refused):toBe(nil)
		expect(refusedReason):toBe "universe ownership is not the required group"
		local options = authority(routes)
		options.allowedVisibilities = { "PRIVATE", "PUBLIC" }
		local receipt, reason = Permission.subjectAuthority(options, credential { "read", "write" }, "10", "4242")
		expect(reason):toBe "bound"
		expect(assert(receipt).decision):toBe(Permission.DECISIONS.bound)
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

describe("Roblox.assetAudit", function()
	local CONFIG: Roblox.AssetAuditConfig = {
		referenceSection = "references",
		modelSection = "models",
		terminalDisposition = "accepted",
		ownedProvenance = "owned",
		eligibilityFields = { "eligible_primary", "eligible_secondary" },
	}

	local function files(tree: { [string]: string }): Roblox.AssetAuditFiles
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

	local function reference(overrides: { [string]: unknown }): Roblox.AssetAuditReference
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
		for key, value in overrides do
			row[key] = value
		end
		return row
	end

	local function model(overrides: { [string]: unknown }): Roblox.AssetAuditModel
		local row: Roblox.AssetAuditModel = {
			reference_sha256 = digest "image",
			reference_image_asset_id = 77,
			model_prompt_sha256 = digest "model",
			comparison_verdict_receipt = "ops/ab.json",
			model_uuid = "uuid-1",
		}
		for key, value in overrides do
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

	it("refuses an input that carries no file reader", function()
		local ok = Test.protectedCall(
			Audit.referenceViolations,
			{ config = CONFIG, digest = digest, references = {}, models = {} }
		)
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
