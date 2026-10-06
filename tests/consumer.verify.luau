--!strict

local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local Consumer = require "../src/consumer"

local function codes(source: string, rulesets: { Consumer.Ruleset }?): { string }
	local result: { string } = {}
	for _, finding in Consumer.scanSource("fixture.generate.luau", source, rulesets) do
		table.insert(result, finding.code)
	end
	table.sort(result)
	return result
end

local ROBLOX: { Consumer.Ruleset } = { "roblox" }

local COMPLETE = [[
return Generate.brief {
    id = "wall",
    intent = { role = "wall" },
    review = {
        rubric = "wall",
        rubricFingerprint = "rubric-wall-v1",
        views = { "front" },
    },
    provenance = { requireParentLineage = true, requiredRightsFacts = { "source" } },
    delivery = { semanticId = "world.wall", target = "fixture-host" },
}
]]

describe("Generate consumer lints", function()
	it("accepts a semantic brief without execution authority", function()
		expect(codes(COMPLETE)):toEqual {}
	end)

	it("requires spatial briefs to bound their dimensions with an explicit unit", function()
		expect(codes [[
return Generate.brief {
    id = "wall",
    kind = "modular-mesh",
    intent = { role = "wall" },
    constraints = {},
    review = {
        rubric = "wall",
        rubricFingerprint = "rubric-wall-v1",
        views = { "front" },
    },
    provenance = { requireParentLineage = true },
    delivery = { semanticId = "world.wall", target = "fixture-host" },
}
]]):toEqual { "GEN013" }
	end)

	it("keeps the default ruleset free of Roblox spellings and selects the Roblox ruleset explicitly", function()
		local source = [[
return Generate.brief {
    id = "wall",
    intent = { role = "wall", reference = "rbxassetid://1" },
    review = {
        rubric = "wall",
        rubricFingerprint = "rubric-wall-v1",
        views = { "front" },
    },
    provenance = { requireParentLineage = true },
    delivery = { semanticId = "world.wall", target = "fixture-host" },
    studio_id = "stale",
    operation = "list_roblox_studios",
    maxSizeStuds = { x = 1, y = 1, z = 1 },
    sink = GenerationService:Run(),
}
]]
		expect(codes(source)):toEqual {}
		expect(codes(source, ROBLOX)):toEqual { "RBX008", "RBX010", "RBX011", "RBX012", "RBX013" }
		expect(Consumer.RULESETS):toEqual { "roblox" }
		local unknown: unknown = "unknown"
		expect(function()
			codes(source, { unknown :: Consumer.Ruleset })
		end):toThrow "does not know ruleset"
	end)

	it("accepts a metre bound with an explicit unit on a spatial brief", function()
		expect(codes [[
return Generate.brief {
    id = "wall",
    kind = "modular-mesh",
    intent = { role = "wall" },
    constraints = { maxSize = { x = 4, y = 3, z = 1, unit = "m" } },
    review = {
        rubric = "wall",
        rubricFingerprint = "rubric-wall-v1",
        views = { "front" },
    },
    provenance = { requireParentLineage = true },
    delivery = { semanticId = "world.wall", target = "fixture-host" },
}
]]):toEqual {}
	end)

	it("rejects raw asset ids and Studio discovery in authored production", function()
		expect(codes(
			[[
return Generate.brief {
    id = "wall",
    intent = { role = "wall", reference = "rbxassetid://1" },
    review = {
        rubric = "wall",
        rubricFingerprint = "rubric-wall-v1",
        views = { "front" },
    },
    provenance = { requireParentLineage = true },
    delivery = { semanticId = "world.wall", target = "fixture-host" },
    studio_id = "stale",
    operation = "list_roblox_studios",
}
]],
			ROBLOX
		)):toEqual { "RBX010", "RBX011", "RBX012" }
	end)

	it("refuses the retired approval-counting model and an unpinned rubric", function()
		expect(codes [[
return Generate.brief {
    id = "wall",
    intent = { role = "wall" },
    review = { rubric = "wall", views = { "front" }, requiredApprovals = 2 },
    provenance = { requireParentLineage = true },
    delivery = { semanticId = "world.wall", target = "fixture-host" },
}
]]):toEqual { "GEN014", "GEN015" }
	end)

	it("requires an explicit provenance contract on every production brief", function()
		expect(codes [[
return Generate.brief {
    id = "wall",
    intent = { role = "wall" },
    review = {
        rubric = "wall",
        rubricFingerprint = "rubric-wall-v1",
        views = { "front" },
    },
    delivery = { semanticId = "world.wall", target = "fixture-host" },
}
]]):toEqual { "GEN017" }
	end)

	it("refuses a rights decision and an invented rights fact inside a brief", function()
		expect(codes(COMPLETE .. [[
local rights = {
    rightsPolicy = "cleared",
    source = { state = "known" },
}
]])):toEqual { "GEN018", "GEN019" }
	end)
end)

return nil
