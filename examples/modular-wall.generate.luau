--!strict

local Generate = require "../src/core"

local brief = Generate.brief {
	id = "example.wall.straight.v1",
	kind = "modular-mesh",
	intent = {
		role = "A reusable defensive wall module",
		style = "weathered fieldstone",
	},
	constraints = {
		triangleBudget = 6000,
		collision = "simple",
		tileAxis = "x",
		maxSize = { x = 10, y = 6, z = 2, unit = "m" },
	},
	review = {
		rubric = "environment-module",
		rubricFingerprint = "rubric-environment-module-v1-a71b30",
		rubricVersion = "1",
		views = { "front", "corner", "gameplay-distance" },
		blindness = "required",
		independence = "required",
	},
	provenance = {
		requireParentLineage = true,
		requiredRightsFacts = { "source", "owner" } :: { Generate.RightsFactName },
	},
	delivery = {
		semanticId = "example.wall.straight",
		target = "example-host",
	},
}

local plan = Generate.plan(brief, {
	{ id = "candidate", operation = "generate", requires = { "image-to-mesh" } },
	{ id = "canonical", operation = "transform", dependsOn = { "candidate" }, requires = {}, deterministic = true },
	{ id = "technical", operation = "verify", dependsOn = { "canonical" }, requires = {} },
	{ id = "review", operation = "review", dependsOn = { "technical" }, requires = {} },
	{
		id = "publish",
		operation = "publish",
		dependsOn = { "review" },
		requires = { "asset-write" },
		mutation = true,
		rollback = "required",
	},
})

print(plan.id)
print(plan.fingerprint)

return {
	brief = brief,
	plan = plan,
}
