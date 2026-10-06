--!strict

local Generate = require "../src/core"

local brief = Generate.brief {
	id = "example.bracket.review-capture.v1",
	kind = "modular-mesh",
	intent = {
		role = "A reusable defensive wall module offered to a blind review",
		style = "weathered fieldstone",
	},
	constraints = {
		captureBracket = "front, quarter, side",
		maxSize = { x = 10, y = 6, z = 2, unit = "m" },
	},
	review = {
		rubric = "environment-module",
		rubricFingerprint = "rubric-environment-module-v1-a71b30",
		rubricVersion = "1",
		views = { "front", "quarter", "side" },
		blindness = "required",
		independence = "required",
	},
	provenance = {
		requireParentLineage = true,
		requiredRightsFacts = { "source", "owner" } :: { Generate.RightsFactName },
	},
	delivery = {
		semanticId = "example.bracket.wall",
		target = "example-host",
	},
}

local bracket = Generate.evidenceBracket {
	id = brief.id,
	poses = {
		{
			id = "front",
			evidenceId = "01-front.png",
			parameters = { azimuth = 0, elevation = 10 } :: { [string]: unknown },
		},
		{
			id = "quarter",
			evidenceId = "02-quarter.png",
			parameters = { azimuth = 45, elevation = 15 } :: { [string]: unknown },
		},
		{
			id = "side",
			evidenceId = "03-side.png",
			parameters = { azimuth = 90, elevation = 10 } :: { [string]: unknown },
		},
	},
}

local complete: { Generate.EvidenceCapture } = {
	{ pose = "01-front.png", digest = "3f1c", bytes = 40311 },
	{ pose = "02-quarter.png", digest = "a80b", bytes = 41022 },
	{ pose = "03-side.png", digest = "cc57", bytes = 39987 },
}

local bound = Generate.bindEvidence(bracket, complete)
local manifest = Generate.evidenceManifest(bound)

local short = Generate.bindEvidence(bracket, { complete[1], complete[2] })

local held = Generate.bindEvidence(bracket, {
	complete[1],
	{ pose = "02-quarter.png", digest = "a80b", posed = false },
	complete[3],
})

print(brief.id)
print(bracket.id)
print(bound.status)
print(table.concat(bound.ordered, ","))
print(manifest[1].evidenceId)
print(short.status, short.faults[1].reason)
print(held.status, held.faults[1].reason)

return {
	brief = brief,
	bracket = bracket,
	bound = bound,
	manifest = manifest,
	short = short,
	held = held,
}
