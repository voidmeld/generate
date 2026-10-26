--!strict

local Bdd = require "../.lute/dependencies/verify/src/bdd"

local surface = Bdd.surface {
	executor = "lute",
	environment = { runtime = "lute" },
	capabilities = { "filesystem", "local-luau", "process" },
	ambientSource = "tests",
}

return {
	describe = surface.describe,
	it = surface.it,
	itSkip = surface.itSkip,
	beforeEach = surface.beforeEach,
	afterEach = surface.afterEach,
	expect = surface.expect,
	spy = surface.spy,
	skip = surface.skip,
	useHarness = surface.useHarness,
}
