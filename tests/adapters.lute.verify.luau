--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local fs = require "@std/fs"
local Generate = require "../src/core"
local Host = require "../src/host"
local Lute = require "../src/lute"
local Verify = require "../.lute/dependencies/verify/src/core"

local function brief(kind: Generate.AssetKind): Generate.Brief
	return Generate.brief {
		id = "fixture." .. kind,
		kind = kind,
		intent = { role = "fixture", description = "a production fixture" },
		review = { rubric = "fixture", rubricFingerprint = "rubric-fixture-v1", views = { "canonical" } },
		delivery = { semanticId = "fixture.semantic", target = "fixture" },
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

return nil
