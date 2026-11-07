--!strict

local Image = require "../src/image"

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

print "image tools example: measured one artifact and staged its blind review"
