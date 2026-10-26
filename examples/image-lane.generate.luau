--!strict

local Generate = require "../src/core"
local Image = require "../src/image"

local SCHEMA = "example.image-run.v2"

local brief = Generate.brief {
	id = "example.wall-surface.v1",
	kind = "image",
	intent = { role = "One tiling wall surface", style = "plain", description = "one example surface" },
	constraints = { opacity = "opaque" },
	review = {
		rubric = "example-surface",
		rubricFingerprint = "example-surface-rubric-v1",
		views = { "artifact" },
		blindness = "required",
		independence = "required",
	},
	provenance = { requireParentLineage = false, requiredRightsFacts = { "source" :: Generate.RightsFactName } },
	delivery = { semanticId = "example.wall.surface", target = "image" },
}

local plan = Generate.plan(brief, {
	{ id = "candidate", operation = "generate", requires = { "reference-image" } },
	{ id = "review", operation = "review", dependsOn = { "candidate" } },
})

local imageRun = {
	artifacts = {
		{
			id = "example.wall.surface.original.v1",
			slug = "wall-surface",
			role = "terrain-material",
			tiles = true,
			transparentBackground = false,
			singleSubject = true,
		},
	},
	bindings = {
		candidate = {
			kind = "provider",
			attempt = 1,
			delivery = true,
			request = {
				group = "example",
				slug = "wall-surface",
				subject = "wall",
				family = "surface",
				variant = "original",
				version = "v1",
				sourceDirectory = "art",
				prompt = "one tiling wall surface",
			},
		},
		review = {
			kind = "review",
			request = {
				packetId = "example.wall-surface.v1/review",
				candidateId = "example.wall.surface",
				revision = 1,
				producer = "example-author",
				candidateArtifactId = "example.wall.surface.original.v1",
				evidence = { { artifactId = "example.wall.surface.original.v1", view = "artifact", role = "capture" } },
				rubric = { id = "example-surface", fingerprint = "example-surface-rubric-v1" },
				requestedViews = { "artifact" },
				captureEnvironment = { host = "example-image" },
			},
		},
	},
}

local config: Image.RequestConfig = {
	schema = SCHEMA,
	indent = "  ",
	serialize = function(value: unknown): string
		if type(value) == "string" then
			return '"' .. value .. '"'
		end
		return tostring(value)
	end,
}

local derived = Image.request.fromBrief(config, { brief = brief, imageRun = imageRun }, "example.generate.luau")
assert(derived.ok, "the example recipe declares one image run")
local document = derived.document

local bound = Image.request.bindings(document, plan)
assert(bound.ok, "every declared plan stage carries one binding")

local unbound = Image.request.bindings({
	schema = document.schema,
	briefId = document.briefId,
	artifacts = document.artifacts,
	matte = false,
	bindings = { candidate = document.bindings.candidate },
}, plan)
assert(not unbound.ok, "a plan stage with no binding holds the whole request")

local thresholds: Image.QaThresholds = {
	opaqueAlpha = 250,
	transparentAlpha = 5,
	keyResidueSaturation = 60,
	gutterLumaRange = 14,
	brightMaximaLuma = 150,
	chromaSaturationFloor = 0.15,
	maxWrapSeamRatio = 1.1,
	maxInteriorSeamRatio = 1.5,
	maxFractionalSeamRatio = 1.3,
	maxUnlitVignetteRatio = 1.1,
	maxUnlitLightingGradient = 8,
	maxBrightMaximaFraction = 0.005,
	minEdgeBlurRatio = 0.8,
	maxHfScreenPatternPeakRatio = 50,
	maxEdgeMirrorCorrelation = 0.8,
	minMedianLuma = 45,
	minPairedLuminanceRatio = 0.95,
	maxPairedLuminanceRatio = 1.05,
	minPairedRegistrationCorrelation = 0.7,
	minSemiTransparentFraction = 0.005,
	maxKeyResidueFraction = 0.002,
	maxHaloRatio = 1.25,
	maxPanels = 1,
	minGutterBand = 4,
	warnVignetteRatio = 1.12,
	warnLightingGradient = 12,
	warnLumaSpread = 48,
}

local codec: Image.Codec = {
	decode = function(): Image.Decoded
		return { ok = false, reason = "the example supplies no PNG codec" }
	end,
	encodeRgba = function(): string
		return ""
	end,
}
local qa: Image.QaConfig = { schema = SCHEMA, codec = codec, thresholds = thresholds }
local undecoded = Image.qa.assess(qa, "", {
	id = "example.wall.surface.original.v1",
	role = "wall-surface",
	tiles = true,
	transparentBackground = false,
	singleSubject = false,
}, "art/wall.png")
assert(undecoded.refusals[1].fact == "decode", "an assessment refuses bytes that the consumer codec cannot decode")

local incomplete = { schema = SCHEMA, codec = codec, thresholds = {} } :: unknown
assert(not pcall(Image.qa.gate, incomplete :: Image.QaConfig, {
	exists = function(): boolean
		return false
	end,
	read = function(): string
		return ""
	end,
}, {}, {}), "a consumer declares every threshold")

local measure: Image.MeasureConfig = {
	digest = function(bytes: string): string
		return string.format("%08x", #bytes)
	end,
	bounds = { minShortSide = 896, maxLongSide = 2048 },
}

local header = "\137PNG\r\n\26\n"
	.. string.pack(">I4", 13)
	.. "IHDR"
	.. string.pack(">I4", 1024)
	.. string.pack(">I4", 1024)
	.. "example"
local measured = Image.measure.measure(measure, header)
assert(measured.ok, "a 1024 square PNG sits inside the declared envelope")
local artifact =
	Image.measure.artifact(measure, "example.wall.surface.original.v1", "art/wall.png", measured.measurement)
assert(artifact.metadata.minShortSide == "896", "the artifact records the envelope it was judged against")

local packet = Image.review.stage(Image.review.DEFAULT_CONFIG, {
	packetId = "example.wall-surface.v1/review",
	candidateId = "example.wall.surface",
	revision = 1,
	producer = "example-author",
	candidateArtifactId = artifact.id,
	evidence = { { artifactId = artifact.id, view = "artifact", role = "capture" } },
	rubric = { id = "example-surface", fingerprint = "example-surface-rubric-v1" },
	requestedViews = { "artifact" },
	captureEnvironment = { host = "example-image" },
}, { artifact })
assert(packet.ok, "the packet binds one candidate and the evidence staged beside it")

local unblinded = Image.review.stage(Image.review.DEFAULT_CONFIG, {
	packetId = "example.wall-surface.v1/review",
	candidateId = "example.wall.surface",
	revision = 1,
	producer = "example-author",
	candidateArtifactId = artifact.id,
	evidence = { { artifactId = artifact.id, view = "artifact", role = "capture" } },
	rubric = { id = "example-surface", fingerprint = "example-surface-rubric-v1" },
	requestedViews = { "artifact" },
	captureEnvironment = { host = "example-image", producer = "example-author" },
}, { artifact })
assert(not unblinded.ok, "a capture environment naming the producer unblinds the reviewer")

print("image-lane example: bound " .. tostring(#document.artifacts) .. " artifact(s) for " .. document.briefId)
