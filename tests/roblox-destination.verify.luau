--!strict

local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local Generate = require "../src/core"
local Destination = require "../src/roblox/destination"

local function lawful(overrides: { [string]: unknown }): { [string]: unknown }
	local draft: { [string]: unknown } = {
		creator = { type = "group", id = "123456" },
		assetType = "Image",
		credentialName = "FIXTURE_PUBLISH_KEY",
	}
	for key, value in overrides do
		draft[key] = value
	end
	return draft
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

describe("Roblox publication destination", function()
	it("normalizes a destination into the opaque descriptor of the Roblox adapter", function()
		local declared = Destination.create(lawful {})
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
		expect(Destination.read(assert(branded.delivery.destination)).visibility):toEqual "private"
		local named = Destination.create(lawful { displayName = "Fixture Icon", description = "A fixture icon" })
		expect(Destination.read(named).displayName):toEqual "Fixture Icon"
		expect(Destination.read(named).description):toEqual "A fixture icon"
		local update = Destination.read(Destination.create(lawful { visibility = "restricted", assetId = "555" }))
		expect(update.assetId):toEqual "555"
		expect(update.visibility):toEqual "restricted"
		local granting = Destination.create(lawful { grantUniverses = { 111, 222 } })
		expect(Destination.read(granting).grantUniverses):toEqual { 111, 222 }
		local verifying = Destination.create(lawful { grantUniverses = { 111 }, verifyDependencies = true })
		expect(Destination.read(verifying).verifyDependencies):toEqual(true)
		expect(function()
			Destination.create(lawful { verifyDependencies = true })
		end):toThrow "requires grantUniverses"
		expect(function()
			Destination.create(lawful { grantUniverses = { 111 }, verifyDependencies = "yes" })
		end):toThrow "must be a boolean"
	end)

	it("reads back only the normalized roblox descriptor", function()
		expect(function()
			Destination.read { adapter = "other", descriptor = {} }
		end):toThrow "roblox adapter"
		expect(function()
			Destination.read { adapter = "roblox", descriptor = { creator = { type = "group", id = "1" } } }
		end):toThrow "assetType"
		expect(function()
			Destination.read {
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
			Destination.create(lawful { grantUniverses = {} })
		end):toThrow "non-empty"
		expect(function()
			Destination.create(lawful { grantUniverses = { 0 } })
		end):toThrow "grantUniverses"
		expect(function()
			Destination.create(lawful { grantUniverses = { -1 } })
		end):toThrow "grantUniverses"
		expect(function()
			Destination.create(lawful { grantUniverses = { 1.5 } })
		end):toThrow "grantUniverses"
		expect(function()
			Destination.create(lawful { grantUniverses = { "111" } })
		end):toThrow "grantUniverses"
		expect(function()
			Destination.create(lawful { grantUniverses = { 111, 111 } })
		end):toThrow "repeat"
		expect(function()
			Destination.create(lawful { grantUniverses = "111" })
		end):toThrow "grantUniverses"
	end)

	it("refuses a credential value, public visibility, an unowned creator, and unknown fields", function()
		expect(function()
			Destination.create(lawful { credentialName = "sk-live-0123456789abcdef" })
		end):toThrow "environment variable"
		expect(function()
			Destination.create(lawful { credentialName = "lowercase_name" })
		end):toThrow "environment variable"
		expect(function()
			Destination.create(lawful { visibility = "public" })
		end):toThrow "private or restricted"
		expect(function()
			Destination.create(lawful { creator = { type = "studio", id = "1" } })
		end):toThrow "creator"
		expect(function()
			Destination.create(lawful { creator = { type = "group", id = "" } })
		end):toThrow "creator"
		expect(function()
			Destination.create(lawful { assetType = "" })
		end):toThrow "assetType"
		expect(function()
			Destination.create(lawful { assetId = "" })
		end):toThrow "assetId"
		expect(function()
			Destination.create(lawful { displayName = "Fixture Icon" })
		end):toThrow "displayName and description"
		expect(function()
			Destination.create(lawful { displayName = "", description = "Fixture description" })
		end):toThrow "displayName and description"
		expect(function()
			Destination.create(lawful { apiKey = "smuggled" })
		end):toThrow "unknown field"
		expect(function()
			Destination.create(lawful { creator = { type = "group", id = "1", token = "smuggled" } })
		end):toThrow "unknown field"
	end)
end)

return nil
