--!strict

local Test = require "./harness"
local process = require "@std/process"

local describe, it, expect = Test.describe, Test.it, Test.expect

local function codes(source: string): { string }
	local result = process.run { "lute", "lint", "-c", "lint.config.luau", "-s", source }
	local found: { string } = {}
	for code in string.gmatch(result.stdout, "\n?%a+%[([%a_]+)%]:") do
		table.insert(found, code)
	end
	table.sort(found)
	return found
end

describe("Generate lint policy", function()
	it("rejects ambient global state", function()
		expect(codes "return _G\n"):toEqual { "global_table_usage" }
		expect(codes "return shared\n"):toEqual { "global_table_usage" }
	end)

	it("accepts explicitly passed state", function()
		expect(codes "local function use(host) return host end\nreturn use\n"):toEqual {}
	end)

	it("checks one exact authored brief", function()
		local result = process.run {
			"lute",
			"run",
			"tools/generate-check.luau",
			"examples/modular-wall.generate.luau",
		}
		expect(result.ok):toEqual(true)
		expect(result.stdout):toContain "generate-check: clean"
	end)

	it("refuses a missing consumer source instead of reporting it clean", function()
		local result = process.run {
			"lute",
			"run",
			"tools/generate-check.luau",
			"build/does-not-exist.generate.luau",
		}
		expect(result.ok):toEqual(false)
		expect(result.stdout):toContain "source path does not exist"
	end)

	it("refuses an exact file that is not an authored brief", function()
		local result = process.run { "lute", "run", "tools/generate-check.luau", "README.md" }
		expect(result.ok):toEqual(false)
		expect(result.stdout):toContain "source file must end in .generate.luau"
	end)
end)

return nil
