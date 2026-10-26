--!strict

local Generate = require "../src/core"

local brief = Generate.brief {
	id = "example.quota.wall.v1",
	kind = "modular-mesh",
	intent = {
		role = "A reusable defensive wall module",
		style = "weathered fieldstone",
	},
	constraints = {
		triangleBudget = 6000,
		textureBudget = 2,
		partBudget = 4,
		collision = "box",
		maxSize = { x = 10, y = 6, z = 2, unit = "m" },
	},
	review = {
		rubric = "environment-module",
		rubricFingerprint = "rubric-environment-module-v1-a71b30",
		rubricVersion = "1",
		views = { "front", "corner" },
		blindness = "required",
		independence = "required",
	},
	provenance = {
		requireParentLineage = true,
		requiredRightsFacts = { "source", "owner" } :: { Generate.RightsFactName },
	},
	delivery = {
		semanticId = "example.quota.wall",
		target = "example-host",
	},
}

local function report(triangles: number, collisionKind: string): Generate.QuotaReport
	return Generate.evaluateQuota {
		subject = brief.delivery.semanticId,
		quotas = {
			{ name = "triangles", value = triangles, quota = 6000 },
			{ name = "textures", value = 1, quota = 2 },
			{ name = "parts", value = 1, quota = 4 },
		},
		kind = { name = "collision", kind = collisionKind, allowedKinds = { "box", "hull" } },
	}
end

local within = report(4200, "box")
local over = report(9400, "precise-decomposition")

print(brief.id)
print(within.status)
print(over.status)
print(table.concat(over.overruns, ","))

return {
	brief = brief,
	within = within,
	over = over,
}
