--!strict
local Fixture = require "./fixtures/image-codec"
local Generate = require "../src/core"
local Image = require "../src/image"
local Measure = require "../src/image/measure"
local Review = require "../src/image/review"
local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local OUTPUT_ROOT = "art/reference"
local BOUNDS: Image.MeasureBounds = { minShortSide = 896, maxLongSide = 2048 }
local MEASURE: Image.MeasureConfig = { digest = Fixture.digest, bounds = BOUNDS }
local function png(width: number, height: number, fill: string): string
	return table.concat {
		"\137PNG\r\n\26\n",
		string.pack(">I4", 13),
		"IHDR",
		string.pack(">I4", width),
		string.pack(">I4", height),
		fill,
	}
end

describe("Image.measure", function()
	local RAW = OUTPUT_ROOT .. "/fixture/raw-atlas.png"
	local SILHOUETTE = OUTPUT_ROOT .. "/fixture/silhouette.png"

	local function harness(files: { [string]: string }): { exists: (string) -> boolean, read: (string) -> string }
		return {
			exists = function(path: string): boolean
				return files[path] ~= nil
			end,
			read = function(path: string): string
				return files[path] or error("spec harness read a path that does not exist: " .. path)
			end,
		}
	end

	it("reads the saved PNG dimensions from the IHDR chunk", function()
		local width, height, malformed = Measure.pngDimensions(png(1254, 1080, "x"))
		expect(width):toBe(1254)
		expect(height):toBe(1080)
		expect(malformed):toBe ""
	end)

	it("names bytes without a PNG signature or an IHDR chunk rather than measuring them", function()
		local _, _, noSignature = Measure.pngDimensions(string.rep("q", 64))
		expect(noSignature):toContain "PNG signature"
		local wrongChunk = "\137PNG\r\n\26\n" .. string.pack(">I4", 13) .. "IDAT" .. string.rep("\0", 8)
		local _, _, noHeader = Measure.pngDimensions(wrongChunk)
		expect(noHeader):toContain "IHDR"
	end)

	it("holds a PNG outside the consumer's declared band on either side", function()
		expect(Measure.measure(MEASURE, png(895, 1254, "x")).ok):toBe(false)
		expect(Measure.measure(MEASURE, png(1254, 2049, "x")).ok):toBe(false)
		expect(Measure.measure(MEASURE, png(896, 2048, "x")).ok):toBe(true)
		local wide: Image.MeasureConfig =
			{ digest = Fixture.digest, bounds = { minShortSide = 64, maxLongSide = 4096 } }
		expect(Measure.measure(wide, png(895, 1254, "x")).ok):toBe(true)
	end)

	it("carries every measured number and the declared envelope onto the artifact it emits", function()
		local outcome = Measure.measure(MEASURE, png(1024, 1536, "fill"))
		expect(outcome.ok):toBe(true)
		assert(outcome.ok == true)
		local measurement = outcome.measurement
		local artifact = Measure.artifact(MEASURE, "raw-atlas", RAW, measurement)
		expect(artifact.digest):toBe(measurement.digest)
		expect(artifact.digestAlgorithm):toBe "sha256"
		expect(artifact.mediaType):toBe(Measure.MEDIA_TYPE)
		expect(artifact.locator):toBe(RAW)
		expect(artifact.metadata.width):toBe "1024"
		expect(artifact.metadata.height):toBe "1536"
		expect(artifact.metadata.minShortSide):toBe "896"
		expect(artifact.metadata.maxLongSide):toBe "2048"
	end)

	it("emits one evidence artifact per declared surface", function()
		local deps = harness { [RAW] = png(1254, 1254, "raw"), [SILHOUETTE] = png(1254, 1254, "sil") }
		local outcome = Measure.runStage(MEASURE, deps, {
			{ id = "raw-atlas", view = "raw-atlas", role = "capture", path = RAW },
			{ id = "silhouette", view = "silhouette", role = "capture", path = SILHOUETTE },
		})
		expect(outcome.status):toBe "returned"
		assert(outcome.status == "returned")
		local artifacts = assert(outcome.output.artifacts)
		expect(#artifacts):toBe(2)
		expect(artifacts[1].id):toBe "raw-atlas"
		expect(artifacts[1].digest == artifacts[2].digest):toBe(false)
	end)

	it("rejects a missing or unmeasurable surface rather than thinning the evidence set", function()
		local missing = Measure.runStage(
			MEASURE,
			harness {},
			{ { id = "raw-atlas", view = "raw-atlas", role = "capture", path = RAW } }
		)
		expect(missing.status):toBe "rejected"
		assert(missing.status == "rejected")
		expect(missing.detail):toContain "does not exist"

		local undersized = Measure.runStage(
			MEASURE,
			harness { [RAW] = png(320, 320, "tiny") },
			{ { id = "raw-atlas", view = "raw-atlas", role = "capture", path = RAW } }
		)
		expect(undersized.status):toBe "rejected"
		assert(undersized.status == "rejected")
		expect(undersized.detail):toContain "short side must be at least 896"

		local empty = Measure.runStage(MEASURE, harness {}, {})
		expect(empty.status):toBe "rejected"
		assert(empty.status == "rejected")
		expect(empty.detail):toContain "no evidence surface"
	end)
end)

describe("Image.review", function()
	local function artifact(id: string, digest: string): Generate.Artifact
		return { id = id, digest = digest, digestAlgorithm = "sha256", mediaType = "image/png", metadata = {} }
	end

	local CANDIDATE = artifact("candidate", string.rep("0e6b72cf", 8))
	local RAW = artifact("raw-atlas", string.rep("2b8d1a60", 8))
	local SILHOUETTE = artifact("silhouette", string.rep("91cc37de", 8))
	local ARTIFACTS = { CANDIDATE, RAW, SILHOUETTE }

	local function staging(overrides: {
		candidateArtifactId: string?,
		evidence: { { artifactId: string, view: string, role: string } }?,
		rubric: Generate.RubricIdentity?,
		requestedViews: { string }?,
		captureEnvironment: { [string]: string }?,
	}): Image.ReviewRequest
		local built: Image.ReviewRequest = {
			packetId = "spec.surface.v1/packet",
			candidateId = "spec.surface.reference",
			revision = 18,
			producer = "producer-worker",
			candidateArtifactId = CANDIDATE.id,
			evidence = {
				{ artifactId = RAW.id, view = "raw-atlas", role = "capture" },
				{ artifactId = SILHOUETTE.id, view = "silhouette", role = "capture" },
			},
			rubric = { id = "docs/review.md", fingerprint = string.rep("d6ee7295", 8) },
			requestedViews = { "raw-atlas", "silhouette" },
			captureEnvironment = { host = "spec-image", runtime = "lute" },
		}
		built.candidateArtifactId = overrides.candidateArtifactId or built.candidateArtifactId
		built.evidence = overrides.evidence or built.evidence
		built.rubric = overrides.rubric or built.rubric
		built.requestedViews = overrides.requestedViews or built.requestedViews
		built.captureEnvironment = overrides.captureEnvironment or built.captureEnvironment
		return built
	end

	it("stages a packet binding the exact candidate revision and its evidence", function()
		local outcome = Review.stage(Review.DEFAULT_CONFIG, staging {}, ARTIFACTS)
		expect(outcome.ok):toBe(true)
		assert(outcome.ok == true)
		local draft = outcome.draft
		expect(draft.candidate.revision):toBe(18)
		expect(draft.candidate.producer):toBe "producer-worker"
		expect(#draft.candidate.artifacts):toBe(1)
		expect(draft.candidate.artifacts[1].digest):toBe(CANDIDATE.digest)
		expect(#draft.evidence):toBe(2)
		expect(draft.evidence[1].digest):toBe(RAW.digest)
		expect(draft.captureEnvironment.adapter):toBe(Review.DEFAULT_ADAPTER)
	end)

	it("refuses a capture environment that names the producer, the prompt, or a prior verdict", function()
		for _, key in { "producer", "prompt", "briefId", "verdict", "reviewer" } do
			local environment: { [string]: string } = { host = "spec-image" }
			environment[key] = "leaked"
			local outcome = Review.stage(Review.DEFAULT_CONFIG, staging { captureEnvironment = environment }, ARTIFACTS)
			expect(outcome.ok):toBe(false)
			assert(outcome.ok == false)
			expect(outcome.diagnostic):toContain "unblinds the reviewer"
		end
	end)

	it("refuses a requested view with no evidence and evidence for a view never requested", function()
		local unbound = Review.stage(
			Review.DEFAULT_CONFIG,
			staging { requestedViews = { "raw-atlas", "silhouette", "coverage" } },
			ARTIFACTS
		)
		assert(not unbound.ok)
		expect(unbound.diagnostic):toContain "with no evidence bound to it"
		local extra = Review.stage(Review.DEFAULT_CONFIG, staging { requestedViews = { "raw-atlas" } }, ARTIFACTS)
		assert(not extra.ok)
		expect(extra.diagnostic):toContain "never requested"
	end)

	it("refuses a packet with no candidate, no evidence, no view, or no rubric fingerprint", function()
		expect(Review.stage(Review.DEFAULT_CONFIG, staging { candidateArtifactId = "missing" }, ARTIFACTS).ok):toBe(
			false
		)
		expect(
			Review.stage(Review.DEFAULT_CONFIG, staging { evidence = {}, requestedViews = { "raw-atlas" } }, ARTIFACTS).ok
		):toBe(false)
		expect(Review.stage(Review.DEFAULT_CONFIG, staging { requestedViews = {} }, ARTIFACTS).ok):toBe(false)
		expect(
			Review.stage(
				Review.DEFAULT_CONFIG,
				staging { rubric = { id = "docs/review.md", fingerprint = "" } },
				ARTIFACTS
			).ok
		):toBe(false)
	end)

	it("stages zero decisions so review continuation owns the later reviewer act", function()
		local outcome = Review.runStage(Review.DEFAULT_CONFIG, staging {}, ARTIFACTS)
		expect(outcome.status):toBe "returned"
		assert(outcome.status == "returned")
		expect(#assert(outcome.output.decisions)):toBe(0)
		expect(Review.runStage(Review.DEFAULT_CONFIG, staging { evidence = {} }, ARTIFACTS).status):toBe "rejected"
	end)
end)

return nil
