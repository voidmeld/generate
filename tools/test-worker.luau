--!strict

local Lute = require "../.lute/dependencies/verify/src/lute"
local Test = require "../tests/harness"

Lute.selfRegisteringWorker({
	load = function(locator, harness)
		Test.useHarness(harness, function()
			local resolved, thrown: unknown = pcall(require, "../" .. string.sub(locator, 1, #locator - 5))
			if not resolved then
				error(thrown, 0)
			end
		end)
	end,
}, { capabilities = { "filesystem", "local-luau", "process", "worker" } })
