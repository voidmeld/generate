--!strict

local Generate = require "../src/core"

local brief = Generate.brief {
	id = "example.crate.v1",
	kind = "modular-mesh",
	intent = { role = "A wooden storage crate", style = "weathered planks" },
	constraints = { triangleBudget = 2000, maxSize = { x = 4, y = 4, z = 4, unit = "m" } },
	review = {
		rubric = "prop",
		rubricFingerprint = "rubric-prop-v1-a71b30",
		rubricVersion = "1",
		views = { "front" },
		blindness = "required",
		independence = "required",
	},
	provenance = { requireParentLineage = true, requiredRightsFacts = { "source" } :: { Generate.RightsFactName } },
	delivery = { semanticId = "example.crate", target = "example-host" },
}

local plan = Generate.plan(brief, {
	{ id = "candidate", operation = "generate", requires = { "image-to-mesh" } },
	{ id = "review", operation = "review", dependsOn = { "candidate" }, requires = {} },
})

print(plan.id)
print(plan.fingerprint)
