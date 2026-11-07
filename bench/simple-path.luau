--!strict

local Benchmark = require "../.lute/dependencies/verify/src/benchmark"

local Generate = require "../src/core"

local brief = Generate.brief {
	id = "benchmark.simple",
	kind = "image",
	intent = { role = "benchmark fixture" },
	review = { rubric = "benchmark", rubricFingerprint = "rubric-benchmark-v1", views = { "canonical" } },
	delivery = { semanticId = "benchmark.simple", target = "local" },
}
local plan = Generate.plan(brief, { { id = "produce", operation = "generate" } })
local spec: Benchmark.Spec = {
	name = "simple-path",
	unit = "microseconds",
	warmup = 3,
	samples = 15,
	iterations = 1000,
	workload = function()
		Generate.briefFingerprint(brief)
		Generate.canonical(plan)
	end,
	environment = { observed = "local" },
}

return spec
