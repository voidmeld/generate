--!strict

local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local Generate = require "../src/core"
local Host = require "../src/host"
local Publication = require "../src/roblox/publication-record"
local Units = require "../src/roblox/units"

local DIGEST = string.rep("a", 64)
local STATE_DIGEST = string.rep("b", 64)

local AUTHORITY: Generate.Authority = {
	capabilities = { "generate", "publish" },
	destinations = { "roblox" },
	mutationBudget = 1,
}

local REMOVE: unknown = {}

local function lawful(overrides: { [string]: unknown }): Publication.DestinationDraft
	local draft: { [string]: unknown } = {
		creator = { type = "group", id = "123456" },
		assetType = "Image",
		credentialName = "FIXTURE_PUBLISH_KEY",
	}
	for key, value in overrides do
		draft[key] = value
	end
	return (draft :: unknown) :: Publication.DestinationDraft
end

local function briefWith(destination: Generate.Destination?, hostVerification: boolean?): Generate.Brief
	return Generate.brief {
		id = "fixture.icon.v1",
		kind = "image",
		intent = { role = "fixture icon" },
		review = { rubric = "icon", rubricFingerprint = "rubric-icon-v1", views = { "canonical" } },
		delivery = {
			semanticId = "fixture.icon",
			target = "roblox",
			destination = destination,
			hostVerification = hostVerification,
		},
	}
end

local function receiptOf(status: Generate.ReceiptStatus?): Generate.Receipt
	local value = briefWith(nil, nil)
	local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
	local receipt = Generate.execute(value, plan, Host.fake.create(), AUTHORITY)
	if status == nil then
		return receipt
	end
	local forced = table.clone(receipt)
	forced.status = status
	forced.fingerprint = Generate.receiptFingerprint(forced)
	return forced
end

local function record(overrides: { [string]: unknown }): Generate.PublicationRecord
	local base: { [string]: unknown } = {
		schemaVersion = 1,
		disposition = "minted-ungranted",
		state = "stopped",
		detail = "not every declared universe was granted",
		dryRun = false,
		quarantined = true,
		placeholder = false,
		credential = { name = "FIXTURE_PUBLISH_KEY", exposed = false },
		attemptsAuthorised = 1,
		attemptsMade = 1,
		attempts = {},
		compensations = {},
		stages = { { id = "grant-universes", status = "refused", detail = "0/1 granted" } },
		facts = Publication.facts {
			universeGrants = {
				{ universeId = 111, status = "refused", refusal = "the platform refused the permission grant (403)" },
			},
			dependencyGrants = {},
		},
	}
	for key, value in overrides do
		base[key] = if value == REMOVE then nil else value
	end
	return (base :: unknown) :: Generate.PublicationRecord
end

local function factsWith(overrides: { [string]: unknown }): { [string]: unknown }
	local base: { [string]: unknown } = { universeGrants = {}, dependencyGrants = {} }
	for key, value in overrides do
		base[key] = if value == REMOVE then nil else value
	end
	return base
end

describe("Roblox publication destination", function()
	it("normalizes a destination into the opaque descriptor of the Roblox adapter", function()
		local declared = Publication.destination(lawful {})
		expect(declared.adapter):toEqual "roblox"
		expect(declared.descriptor):toEqual {
			creator = { type = "group", id = "123456" },
			assetType = "Image",
			visibility = "private",
			credentialName = "FIXTURE_PUBLISH_KEY",
			verifyDependencies = false,
		}
		local plain = briefWith(nil, nil)
		local branded = briefWith(declared, nil)
		expect(Generate.briefFingerprint(branded)).never:toEqual(Generate.briefFingerprint(plain))
		expect(Publication.readDestination(branded.delivery.destination :: Generate.Destination).visibility):toEqual "private"
		local named = Publication.destination(lawful { displayName = "Fixture Icon", description = "A fixture icon" })
		expect(Publication.readDestination(named).displayName):toEqual "Fixture Icon"
		expect(Publication.readDestination(named).description):toEqual "A fixture icon"
		local update =
			Publication.readDestination(Publication.destination(lawful { visibility = "restricted", assetId = "555" }))
		expect(update.assetId):toEqual "555"
		expect(update.visibility):toEqual "restricted"
		local granting = Publication.destination(lawful { grantUniverses = { 111, 222 } })
		expect(Publication.readDestination(granting).grantUniverses):toEqual { 111, 222 }
		local verifying = Publication.destination(lawful { grantUniverses = { 111 }, verifyDependencies = true })
		expect(Publication.readDestination(verifying).verifyDependencies):toEqual(true)
		expect(function()
			Publication.destination(lawful { verifyDependencies = true })
		end):toThrow "requires grantUniverses"
		expect(function()
			Publication.destination(lawful { grantUniverses = { 111 }, verifyDependencies = "yes" })
		end):toThrow "must be a boolean"
	end)

	it("reads back only the normalized roblox descriptor", function()
		expect(function()
			Publication.readDestination { adapter = "other", descriptor = {} }
		end):toThrow "roblox adapter"
		expect(function()
			Publication.readDestination { adapter = "roblox", descriptor = { creator = { type = "group", id = "1" } } }
		end):toThrow "assetType"
		expect(function()
			Publication.readDestination {
				adapter = "roblox",
				descriptor = {
					creator = { type = "group", id = "123456" },
					assetType = "Image",
					credentialName = "FIXTURE_PUBLISH_KEY",
				},
			}
		end):toThrow "normalized descriptor"
	end)

	it("refuses a malformed grantUniverses", function()
		expect(function()
			Publication.destination(lawful { grantUniverses = {} })
		end):toThrow "non-empty"
		expect(function()
			Publication.destination(lawful { grantUniverses = { 0 } })
		end):toThrow "grantUniverses"
		expect(function()
			Publication.destination(lawful { grantUniverses = { -1 } })
		end):toThrow "grantUniverses"
		expect(function()
			Publication.destination(lawful { grantUniverses = { 1.5 } })
		end):toThrow "grantUniverses"
		expect(function()
			Publication.destination(lawful { grantUniverses = { "111" } })
		end):toThrow "grantUniverses"
		expect(function()
			Publication.destination(lawful { grantUniverses = { 111, 111 } })
		end):toThrow "repeat"
		expect(function()
			Publication.destination(lawful { grantUniverses = "111" })
		end):toThrow "grantUniverses"
	end)

	it("refuses a credential value, public visibility, an unowned creator, and unknown fields", function()
		expect(function()
			Publication.destination(lawful { credentialName = "sk-live-0123456789abcdef" })
		end):toThrow "environment variable"
		expect(function()
			Publication.destination(lawful { credentialName = "lowercase_name" })
		end):toThrow "environment variable"
		expect(function()
			Publication.destination(lawful { visibility = "public" })
		end):toThrow "private or restricted"
		expect(function()
			Publication.destination(lawful { creator = { type = "studio", id = "1" } })
		end):toThrow "creator"
		expect(function()
			Publication.destination(lawful { creator = { type = "group", id = "" } })
		end):toThrow "creator"
		expect(function()
			Publication.destination(lawful { assetType = "" })
		end):toThrow "assetType"
		expect(function()
			Publication.destination(lawful { assetId = "" })
		end):toThrow "assetId"
		expect(function()
			Publication.destination(lawful { displayName = "Fixture Icon" })
		end):toThrow "displayName and description"
		expect(function()
			Publication.destination(lawful { displayName = "", description = "Fixture description" })
		end):toThrow "displayName and description"
		expect(function()
			Publication.destination(lawful { apiKey = "smuggled" })
		end):toThrow "unknown field"
		expect(function()
			Publication.destination(lawful { creator = { type = "group", id = "1", token = "smuggled" } })
		end):toThrow "unknown field"
	end)
end)

describe("Roblox publication facts", function()
	it("refuses a record whose universe grants are malformed", function()
		local receipt = receiptOf()
		local base = record {}
		expect(Publication.attach(receipt, base).publication):toEqual(base)
		expect(Publication.recordFault(base)):toEqual(nil)

		expect(function()
			Publication.attach(receipt, record { facts = factsWith { universeGrants = REMOVE } })
		end):toThrow "universe grants"
		expect(function()
			Publication.attach(
				receipt,
				record { facts = factsWith { universeGrants = { { universeId = 111, status = "granted" } } } }
			)
		end):toThrow "grantedAtUnix"
		expect(function()
			Publication.attach(
				receipt,
				record {
					facts = factsWith {
						universeGrants = {
							{ universeId = 111, status = "refused", refusal = "denied", grantedAtUnix = 1717000000 },
						},
					},
				}
			)
		end):toThrow "refusal and no grantedAtUnix"
		expect(function()
			Publication.attach(
				receipt,
				record {
					facts = factsWith { universeGrants = { { universeId = 0, status = "refused", refusal = "denied" } } },
				}
			)
		end):toThrow "positive universe id"
		expect(function()
			Publication.attach(receipt, record { facts = factsWith { dependencyGrants = REMOVE } })
		end):toThrow "dependency grants"
		expect(function()
			Publication.facts((factsWith { dependencyGrants = REMOVE } :: unknown) :: Publication.Facts)
		end):toThrow "dependency grants"

		local loadable = {
			assetId = "987654",
			universeId = 111,
			status = "granted",
			grantedAtUnix = 1717000000,
			readable = true,
			moderationState = "Approved",
		}
		local granted = Publication.attach(receipt, record { facts = factsWith { dependencyGrants = { loadable } } })
		expect(Publication.readFacts(granted.publication :: Generate.PublicationRecord).dependencyGrants[1].assetId):toEqual "987654"

		expect(function()
			Publication.attach(
				receipt,
				record {
					facts = factsWith {
						dependencyGrants = {
							{
								assetId = "987654",
								universeId = 111,
								status = "granted",
								grantedAtUnix = 1717000000,
								readable = false,
							},
						},
					},
				}
			)
		end):toThrow "refusal when not granted and loadable"
		expect(function()
			Publication.attach(
				receipt,
				record {
					facts = factsWith {
						dependencyGrants = {
							{ assetId = "987654", universeId = 111, status = "granted", readable = true },
						},
					},
				}
			)
		end):toThrow "grantedAtUnix when granted"
		expect(function()
			Publication.attach(
				receipt,
				record {
					facts = factsWith {
						dependencyGrants = {
							{
								assetId = "rbxassetid://9",
								universeId = 111,
								status = "refused",
								readable = false,
								refusal = "no",
							},
						},
					},
				}
			)
		end):toThrow "positive numeric asset id"
		expect(function()
			Publication.attach(
				receipt,
				record {
					facts = factsWith {
						accessClosure = { sourceReceiptFingerprint = "x", intentPath = "p", intentDigest = "bad" },
					},
				}
			)
		end):toThrow "accessClosure"
	end)
end)

describe("Roblox host verification mapping", function()
	local function draft(source: Generate.Receipt, buildId: string): Publication.RequestDraft
		return {
			receiptId = source.id,
			sourceReceiptFingerprint = source.fingerprint,
			briefFingerprint = source.briefFingerprint,
			artifactId = "candidate",
			artifactDigest = DIGEST,
			assetId = "999000111",
			version = "1",
			grantId = "grant-1",
			grantFingerprint = "grant-fp",
			writeAheadDigest = STATE_DIGEST,
			creator = { type = "group", id = "123456" },
			universeIds = { 111 },
			dependencyAssetIds = { "987654" },
			accessFingerprint = "access-1",
			studioMcpVersion = "1.2.3",
			windowSeconds = 5,
			universeId = 111,
			placeId = 222,
			consumerId = "fixture-consumer",
			buildId = buildId,
		}
	end

	local function verification(refusalReason: string?): Generate.HostVerification
		return {
			schemaVersion = 1,
			requested = true,
			disposition = if refusalReason == nil then "verified" else "refused",
			refusalReason = refusalReason,
			detail = nil,
			contentId = "999000111",
			hostBuild = "build-1",
			windowSeconds = 5,
			measurements = {
				meshLoaded = true,
				triangleCount = 240,
				boundingBoxStuds = { x = 4, y = 4, z = 4 },
			},
			diagnostics = {},
			captureRef = "frame://999000111",
			observationFingerprint = if refusalReason == nil then string.rep("f", 32) else nil,
		}
	end

	local function published(overrides: { [string]: unknown }): Generate.PublicationRecord
		local base: { [string]: unknown } = {
			disposition = "published",
			state = "confirmed",
			detail = REMOVE,
			contentId = "999000111",
			stages = { { id = "host-verification", status = "not-run", detail = "the brief does not request it" } },
			facts = factsWith {},
		}
		for key, value in overrides do
			base[key] = value
		end
		return record(base)
	end

	it("maps Roblox facts onto the generic verification request", function()
		local receipt = receiptOf "accepted"
		local mapped = Publication.request(draft(receipt, "build-1"))
		expect(mapped.contentId):toEqual "999000111"
		expect(mapped.host):toEqual "1.2.3"
		expect(mapped.hostBuild):toEqual "build-1"
		expect(mapped.stateFingerprint):toEqual "access-1"
		expect(mapped.binding):toEqual {
			creator = { type = "group", id = "123456" },
			universeIds = { 111 },
			dependencyAssetIds = { "987654" },
			universeId = 111,
			placeId = 222,
			consumerId = "fixture-consumer",
		}
		expect(Publication.request(draft(receipt, "build-2")).fingerprint).never:toEqual(mapped.fingerprint)
		local unplaced = draft(receipt, "build-1")
		unplaced.placeId = 0
		expect(function()
			Publication.request(unplaced)
		end):toThrow "universe, place and consumer"
		local unversioned = draft(receipt, "build-1")
		unversioned.studioMcpVersion = ""
		expect(function()
			Publication.request(unversioned)
		end):toThrow "Studio version"
	end)

	it("reports host verification only for an exact verified record", function()
		local receipt = receiptOf "accepted"
		local verified = published { verification = verification(nil) }
		local attached = Publication.attach(receipt, verified)
		expect(Publication.hostVerified(attached)):toEqual(true)
		expect(Publication.hostVerified(Publication.attach(receipt, published {}))):toEqual(false)
		expect(Publication.hostVerified(Publication.attach(receiptOf "produced", verified))):toEqual(false)
		local refused = Publication.attach(receipt, published { verification = verification "mesh_not_loaded" })
		expect(Publication.hostVerified(refused)):toEqual(false)
		for _, reason in { "mesh_not_loaded", "bounds_violation", "collision_mismatch", "asset_error_line" } do
			expect(Publication.REFUSAL_REASONS[reason]):toEqual(true)
		end
		expect(function()
			Publication.attach(receipt, published { verification = verification "unknown_reason" })
		end):toThrow "declared refusal reason"
		local mismatched =
			Generate.attachPublication(receipt, published { verification = verification "unknown_reason" })
		expect(Publication.hostVerified(mismatched)):toEqual(false)
	end)

	it("requires a bound access closure and preserved stages to confirm a closure-pending record", function()
		local receipt = receiptOf()
		local closure = {
			sourceReceiptFingerprint = receipt.fingerprint,
			intentPath = "intent/access.json",
			intentDigest = DIGEST,
		}
		local pending = Publication.attach(
			receipt,
			record {
				disposition = "access-closure-pending",
				state = "pending",
				contentId = "999000111",
				facts = factsWith {},
			}
		)
		local function confirmed(source: string): Generate.PublicationRecord
			return record {
				disposition = "published",
				state = "confirmed",
				contentId = "999000111",
				facts = factsWith {
					accessClosure = {
						sourceReceiptFingerprint = source,
						intentPath = closure.intentPath,
						intentDigest = closure.intentDigest,
					},
				},
			}
		end
		local settled = Publication.confirm(pending, confirmed(pending.fingerprint))
		expect(Publication.readFacts(settled.publication :: Generate.PublicationRecord).accessClosure).never:toEqual(
			nil
		)
		expect(function()
			Publication.confirm(pending, confirmed "other")
		end):toThrow "bound access closure"
		expect(function()
			Publication.confirm(
				pending,
				record { disposition = "published", state = "confirmed", contentId = "999000111", facts = factsWith {} }
			)
		end):toThrow "bound access closure"
		expect(function()
			Publication.confirm(
				pending,
				record {
					disposition = "published",
					state = "confirmed",
					contentId = "999000112",
					stages = { { id = "other", status = "passed" } },
					facts = confirmed(pending.fingerprint).facts,
				}
			)
		end):toThrow "preserve the access closure source stages"
		expect(function()
			Publication.confirm(
				pending,
				record {
					disposition = "published",
					state = "confirmed",
					contentId = "999000112",
					facts = confirmed(pending.fingerprint).facts,
				}
			)
		end):toThrow "preserve the original upload"
	end)

	it("reconciles only a failed-compensation create with unattempted access", function()
		local receipt = receiptOf()
		local attempt: Generate.PublicationAttempt = {
			ordinal = 1,
			stageId = "spend",
			grantId = "grant-1",
			grantFingerprint = "grant-fp",
			action = "create",
			semanticId = "fixture.icon",
			state = "failed-readback",
		}
		local compensations: { Generate.PublicationCompensation } =
			{ { ordinal = 1, stageId = "spend", rollbackToken = "token-1", status = "failed", detail = "denied" } }
		local function stopped(disposition: string, facts: { [string]: unknown }): Generate.PublicationRecord
			return record {
				disposition = disposition,
				state = "stopped",
				attempts = { attempt },
				compensations = compensations,
				facts = facts,
			}
		end
		local attached = Publication.attach(receipt, stopped("failed-compensation", factsWith {}))
		local function reconciled(disposition: string): Generate.PublicationRecord
			return record {
				disposition = disposition,
				state = "reconciled",
				attempts = { attempt },
				compensations = compensations,
				version = "3",
				readback = { creator = "fixture" },
				facts = factsWith {},
				reconciliation = {
					sourceReceiptFingerprint = attached.fingerprint,
					evidencePath = "evidence/readback.json",
					evidenceDigest = string.rep("e", 64),
				},
			}
		end
		local settled = Publication.reconcile(attached, reconciled "access-closure-pending")
		expect((settled.publication :: Generate.PublicationRecord).state):toEqual "reconciled"
		expect(function()
			Publication.reconcile(attached, reconciled "other-disposition")
		end):toThrow "access-closure-pending record"
		local other = Publication.attach(receipt, stopped("refused", factsWith {}))
		expect(function()
			Publication.reconcile(other, reconciled "access-closure-pending")
		end):toThrow "failed-compensation receipt"
		local granted = Publication.attach(
			receipt,
			stopped(
				"failed-compensation",
				factsWith { universeGrants = { { universeId = 111, status = "refused", refusal = "denied" } } }
			)
		)
		expect(function()
			Publication.reconcile(granted, reconciled "access-closure-pending")
		end):toThrow "unattempted access"
	end)
end)

describe("Roblox size units", function()
	it("converts a size in metres, the default unit, to studs", function()
		local studs = Units.studs { x = 2.8, y = 0.56, z = 0.28 }
		expect(math.abs(studs.x - 10) < 1e-9):toEqual(true)
		expect(math.abs(studs.y - 2) < 1e-9):toEqual(true)
		expect(math.abs(studs.z - 1) < 1e-9):toEqual(true)
		expect(math.abs(Units.studs({ x = 280, y = 28, z = 28, unit = "cm" }).x - 10) < 1e-9):toEqual(true)
		expect(math.abs(Units.studs({ x = 280, y = 280, z = 280, unit = "mm" }).y - 1) < 1e-9):toEqual(true)
	end)

	it("refuses an unknown unit and a size that is not a positive finite number", function()
		local foot: unknown = "ft"
		expect(function()
			Units.studs { x = 1, y = 1, z = 1, unit = foot :: Units.Unit }
		end):toThrow "unit"
		expect(function()
			Units.studs { x = 0, y = 1, z = 1 }
		end):toThrow "size x"
		expect(function()
			Units.studs { x = 1, y = -1, z = 1 }
		end):toThrow "size y"
		expect(function()
			Units.studs { x = 1, y = 1, z = math.huge }
		end):toThrow "size z"
	end)
end)

return nil
