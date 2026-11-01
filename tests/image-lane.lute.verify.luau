--!strict

local Lute = require "../.lute/dependencies/verify/src/lute"
local crypto = require "@lute/crypto"

local Fixture = require "./fixtures/image-codec"
local Generate = require "../src/core"
local Image = require "../src/image"
local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local Measure = require "../src/image/measure"
local Postprocess = require "../src/image/postprocess"
local Provider = require "../src/image/provider"
local Request = require "../src/image/request"
local Review = require "../src/image/review"
local Host = Image.host

local BOUNDS: Image.MeasureBounds = { minShortSide = 896, maxLongSide = 2048 }
local MEASURE: Image.MeasureConfig = { digest = Fixture.digest, bounds = BOUNDS }

local REQUEST_CONFIG: Image.RequestConfig = {
	indent = "  ",
	serialize = function(value: unknown): string
		return Lute.encode(value)
	end,
}

describe("Image.request", function()
	it("encodes consumer documents with sorted keys, nested arrays and a final newline", function()
		expect(Request.encode(REQUEST_CONFIG, { b = 1, a = { "x", "y" } })):toBe '{\n  "a": [\n    "x",\n    "y"\n  ],\n  "b": 1\n}\n'
		expect(Request.encode(REQUEST_CONFIG, {})):toBe "{}\n"
	end)
end)

local OUTPUT_ROOT = "art/reference"
local SOURCE_ROOT = "art/source"
local BRAND_ROOT = "art/brand"
local OUTPUT = OUTPUT_ROOT .. "/fixture/test-lamp.png"
local PROMPT = SOURCE_ROOT .. "/fixture-props/test-lamp-reference-prompt.txt"

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

local function instruction(request: Image.ProviderRequest, paths: Image.ProviderPaths): string
	local trimmed = string.match(request.prompt, "^%s*(.-)%s*$") or ""
	return table.concat({
		trimmed,
		("save it as ./%s in this directory."):format(paths.imageFileName),
		"Reply with only the saved file path.",
	}, " ")
end

local function command(
	_request: Image.ProviderRequest,
	paths: Image.ProviderPaths,
	inputs: { string },
	prompt: string
): { string }
	local argv: { string } = { "spec-image-tool", "exec" }
	if #inputs > 0 then
		table.insert(argv, "-i")
		for _, path in inputs do
			table.insert(argv, path)
		end
	end
	for _, value in { "-m", "spec-model", "-C", paths.directory, prompt } do
		table.insert(argv, value)
	end
	return argv
end

local PROVIDER: Image.ProviderConfig = {
	tool = "spec-image-tool",
	toolVersion = "spec-model",
	provider = "spec-provider",
	model = "spec-model",
	capability = "reference-image",
	disposition = "active",
	rightsSource = "owned_generated",
	parentOrigin = "repository:",
	outputRoot = OUTPUT_ROOT,
	sourceRoot = SOURCE_ROOT,
	editBaseRoots = { OUTPUT_ROOT, BRAND_ROOT },
	operationRoot = ".spec/operations",
	operationLeaf = "generate",
	promptSuffix = "-reference-prompt.txt",
	environment = { adapter = "spec.image.provider.v1", provider = "spec-provider", model = "spec-model" },
	measure = MEASURE,
	instruction = instruction,
	command = command,
}

local PROVIDER_REQUEST: Image.ProviderRequest = {
	group = "fixture",
	slug = "test-lamp",
	subject = "wayside vigil lamp",
	family = "static-props",
	variant = "single_plane",
	version = "v1",
	sourceDirectory = SOURCE_ROOT .. "/fixture-props",
	prompt = "  A grounded stylized wayside vigil lamp, three-quarter view.  ",
}

local function altered(
	overrides: { group: string?, sourceDirectory: string?, operationId: string?, editOf: string? }
): Image.ProviderRequest
	local request = table.clone(PROVIDER_REQUEST)
	request.group = overrides.group or request.group
	request.sourceDirectory = overrides.sourceDirectory or request.sourceDirectory
	request.operationId = overrides.operationId or request.operationId
	request.editOf = overrides.editOf or request.editOf
	return request
end

local function brief(): Generate.Brief
	return Generate.brief {
		schemaVersion = 1,
		id = "spec.surface.v1",
		kind = "image",
		intent = { role = "a spec surface", style = "plain", description = "one spec subject" },
		constraints = { opacity = "opaque" },
		review = {
			rubric = "docs/review.md",
			rubricFingerprint = string.rep("d6ee7295", 8),
			views = { "artifact" },
			blindness = "required",
			independence = "required",
		},
		provenance = { requireParentLineage = false, requiredRightsFacts = { "source" } },
		delivery = { semanticId = "spec.surface", target = "image" },
	}
end

local BRIEF = brief()

local function stageDetail(value: Generate.StageOutcome): string
	assert(value.status ~= "returned")
	return value.detail
end

local function width(facts: unknown): unknown
	assert(type(facts) == "table")
	for key, value in facts do
		if key == "width" then
			return value
		end
	end
	error "missing width fact"
end

describe("Image.measure", function()
	local RAW = OUTPUT_ROOT .. "/fixture/raw-atlas.png"
	local SILHOUETTE = OUTPUT_ROOT .. "/fixture/silhouette.png"

	local function harness(files: { [string]: string }): Image.QaDeps
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

describe("Image.provider", function()
	type Recorded = { path: string, bytes: string }

	local function harness(
		overrides: { files: { [string]: string }?, stdout: string?, exitcode: number?, saved: string? }
	): (Image.ProviderDeps, { written: { Recorded }, invocations: { { string } } })
		local files: { [string]: string } = overrides.files or {}
		local log: { written: { Recorded }, invocations: { { string } } } = { written = {}, invocations = {} }
		local deps: Image.ProviderDeps = {
			exists = function(path: string): boolean
				return files[path] ~= nil
			end,
			read = function(path: string): string
				return files[path] or error("spec harness read a path that does not exist: " .. path)
			end,
			write = function(path: string, bytes: string)
				table.insert(log.written, { path = path, bytes = bytes })
				files[path] = bytes
			end,
			createDirectory = function(path: string)
				files[path] = ""
			end,
			run = function(args: { string }): Image.ProviderRunResult
				table.insert(log.invocations, args)
				if (overrides.exitcode or 0) == 0 then
					files[OUTPUT] = overrides.saved or png(1024, 1536, "\8\6\0\0\0")
				end
				return { stdout = overrides.stdout or OUTPUT, stderr = "", exitcode = overrides.exitcode or 0 }
			end,
		}
		return deps, log
	end

	it("derives the reference, prompt, and candidate paths from the consumer's roots", function()
		local resolved = Provider.paths(PROVIDER, PROVIDER_REQUEST)
		expect(resolved.imagePath):toBe(OUTPUT)
		expect(resolved.promptPath):toBe(PROMPT)
		expect(resolved.candidateId):toBe "fixture.test_lamp.single_plane.v1"
		expect(resolved.editOf):toBe ""
	end)

	it("confines a successor candidate and prompt to the consumer's operation root", function()
		local resolved = Provider.paths(PROVIDER, altered { operationId = "successor-1" })
		expect(resolved.imagePath):toBe ".spec/operations/successor-1/generate/test-lamp.png"
		expect(resolved.promptPath):toBe ".spec/operations/successor-1/generate/test-lamp-reference-prompt.txt"
		expect((pcall(Provider.paths, PROVIDER, altered { operationId = "../escape" }))):toBe(false)
		expect((pcall(Provider.paths, PROVIDER, altered { operationId = "/absolute" }))):toBe(false)
	end)

	it("refuses a group or source directory that escapes the declared roots", function()
		expect((pcall(Provider.paths, PROVIDER, altered { group = "../etc" }))):toBe(false)
		expect((pcall(Provider.paths, PROVIDER, altered { sourceDirectory = SOURCE_ROOT .. "/../../etc" }))):toBe(false)
		expect((pcall(Provider.paths, PROVIDER, altered { sourceDirectory = "/etc/passwd" }))):toBe(false)
		expect((pcall(Provider.paths, PROVIDER, altered { sourceDirectory = "elsewhere/shared" }))):toBe(false)
	end)

	it("refuses an edit base outside the declared roots, a non-PNG, or the output itself", function()
		expect((pcall(Provider.paths, PROVIDER, altered { editOf = SOURCE_ROOT .. "/fixture-props/base.png" }))):toBe(
			false
		)
		expect((pcall(Provider.paths, PROVIDER, altered { editOf = OUTPUT_ROOT .. "/fixture/base.jpg" }))):toBe(false)
		expect((pcall(Provider.paths, PROVIDER, altered { editOf = "../" .. OUTPUT_ROOT .. "/fixture/base.png" }))):toBe(
			false
		)
		expect((pcall(Provider.paths, PROVIDER, altered { editOf = OUTPUT }))):toBe(false)
	end)

	it("admits a second declared base root without copying it into the output root", function()
		local mark = BRAND_ROOT .. "/mark-2048.png"
		expect(Provider.withinEitherRoot(mark, PROVIDER.editBaseRoots)):toBe(true)
		expect(Provider.withinRoot(mark, PROVIDER.outputRoot)):toBe(false)
		expect(Provider.paths(PROVIDER, altered { editOf = mark }).editOf):toBe(mark)
		local deps, log = harness { files = { [mark] = png(1024, 1536, "mark") } }
		local outcome = Provider.runStage(PROVIDER, deps, altered { editOf = mark }, 1)
		expect(outcome.status):toBe "returned"
		assert(outcome.status == "returned")
		for _, entry in log.written do
			expect(entry.path == mark):toBe(false)
		end
		local parent = assert(assert(outcome.output.derivations)[1].parents)[1]
		expect(parent.artifactId):toBe(mark)
		expect(parent.jobId):toBe(PROVIDER.parentOrigin .. mark)
	end)

	it("binds typed invocation facts naming the provider and never claiming determinism", function()
		local resolved = Provider.paths(PROVIDER, PROVIDER_REQUEST)
		local argv = command(PROVIDER_REQUEST, resolved, {}, instruction(PROVIDER_REQUEST, resolved))
		local invocation = Provider.invocation(PROVIDER, argv)
		expect(invocation.provider):toBe(PROVIDER.provider)
		expect(invocation.model):toBe(PROVIDER.model)
		expect(invocation.tool):toBe(PROVIDER.tool)
		expect(invocation.deterministic):toBe(false)
		expect(invocation.parametersFingerprint):toBe(Generate.fingerprint(argv))
		expect(string.match(invocation.parametersFingerprint, "^gen%-fp2%-%x+$") ~= nil):toBe(true)
	end)

	it("writes the prompt file, runs one command, and emits one active candidate", function()
		local deps, log = harness {}
		local outcome = Provider.runStage(PROVIDER, deps, PROVIDER_REQUEST, 1)
		expect(outcome.status):toBe "returned"
		assert(outcome.status == "returned")
		expect(#log.written):toBe(1)
		expect(log.written[1].path):toBe(PROMPT)
		expect(#log.invocations):toBe(1)
		local output = outcome.output
		expect(assert(output.artifacts)[1].id):toBe "fixture.test_lamp.single_plane.v1"
		expect(assert(output.artifacts)[1].metadata.width):toBe "1024"
		expect(assert(output.artifacts)[1].semanticId):toBeNil()
		expect(assert(output.derivations)[1].origin):toBe "original"
		expect(assert(output.derivations)[1].disposition):toBe "active"
		expect(assert(assert(assert(output.derivations)[1].rights).source).state):toBe "known"
		expect(assert(assert(output.derivations)[1].environment).provider):toBe "spec-provider"
	end)

	it("never overwrites an existing accepted reference and holds on an absent edit base", function()
		local existing, existingLog = harness { files = { [OUTPUT] = png(1024, 1536, "already") } }
		local overwritten = Provider.runStage(PROVIDER, existing, PROVIDER_REQUEST, 1)
		expect(overwritten.status):toBe "rejected"
		assert(overwritten.status == "rejected")
		expect(stageDetail(overwritten)):toContain "never overwritten in place"
		expect(#existingLog.invocations):toBe(0)

		local deps, log = harness {}
		local absent = Provider.runStage(PROVIDER, deps, altered { editOf = OUTPUT_ROOT .. "/fixture/absent.png" }, 1)
		expect(absent.status):toBe "rejected"
		assert(absent.status == "rejected")
		expect(absent.detail):toContain "does not exist"
		expect(#log.invocations):toBe(0)
	end)

	it("produces a new versioned edit beside the base without touching the base", function()
		local base = OUTPUT_ROOT .. "/fixture/test-lamp-v1.png"
		local deps, log = harness { files = { [base] = png(1024, 1536, "base") } }
		local outcome = Provider.runStage(PROVIDER, deps, altered { editOf = base }, 2)
		expect(outcome.status):toBe "returned"
		assert(outcome.status == "returned")
		for _, entry in log.written do
			expect(entry.path == base):toBe(false)
		end
		local derivation = assert(outcome.output.derivations)[1]
		expect(derivation.origin):toBe "derived"
		expect(derivation.attempt):toBe(2)
		expect(#assert(derivation.parents)):toBe(1)
		expect(assert(derivation.parents)[1].artifactDigest):toBe(assert(derivation.referenceDigests)[1])
	end)

	it("holds on a non-zero exit, a mismatched reply, and a wrong-size PNG, spending one invocation", function()
		local failing, failingLog = harness { exitcode = 3 }
		local exited = Provider.runStage(PROVIDER, failing, PROVIDER_REQUEST, 1)
		expect(exited.status):toBe "rejected"
		assert(exited.status == "rejected")
		expect(exited.detail):toContain "exited 3"
		expect(#failingLog.invocations):toBe(1)

		local wrongReply = harness { stdout = OUTPUT_ROOT .. "/fixture/somewhere-else.png" }
		local mismatched = Provider.runStage(PROVIDER, wrongReply, PROVIDER_REQUEST, 1)
		expect(mismatched.status):toBe "rejected"
		assert(mismatched.status == "rejected")
		expect(mismatched.detail):toContain "rather than"

		local small = harness { saved = png(512, 512, "small") }
		local undersized = Provider.runStage(PROVIDER, small, PROVIDER_REQUEST, 1)
		expect(undersized.status):toBe "rejected"
		assert(undersized.status == "rejected")
		expect(undersized.detail):toContain "short side must be at least 896"
	end)
end)

describe("Image.postprocess", function()
	local SCRIPT = SOURCE_ROOT .. "/fixture-props/despeckle.spec"
	local BASE = OUTPUT_ROOT .. "/fixture/base.png"
	local DONOR = OUTPUT_ROOT .. "/fixture/donor.png"
	local EDITED = OUTPUT_ROOT .. "/fixture/edited.png"
	local SCRIPT_BYTES = "deterministic plate-face despeckle\n"

	local CONFIG: Image.PostprocessConfig = {
		adapter = "spec.image.postprocess.v1",
		capability = "deterministic-image-transform",
		interpreter = "spec-interpreter",
		digest = Fixture.digest,
		measure = MEASURE,
	}

	local function artifacts(): { Generate.Artifact }
		return {
			{
				id = "base",
				digest = Fixture.digest(png(1254, 1254, "base")),
				digestAlgorithm = "sha256",
				mediaType = "image/png",
				locator = BASE,
				metadata = {},
			},
			{
				id = "donor",
				digest = Fixture.digest(png(1254, 1254, "donor")),
				digestAlgorithm = "sha256",
				mediaType = "image/png",
				locator = DONOR,
				metadata = {},
			},
		}
	end

	local function transform(
		overrides: { scriptDigest: string?, inputs: { Postprocess.Input }? }
	): Image.PostprocessTransform
		local built: Image.PostprocessTransform = {
			id = "deterministic-edit",
			kind = "despeckle",
			scriptPath = SCRIPT,
			scriptDigest = Fixture.digest(SCRIPT_BYTES),
			inputs = { { role = "base", path = BASE }, { role = "donor", path = DONOR } },
			outputPath = EDITED,
			parameters = { seed = "0", sigma = "3" },
			attempt = 6,
		}
		built.scriptDigest = overrides.scriptDigest or built.scriptDigest
		built.inputs = overrides.inputs or built.inputs
		return built
	end

	local function harness(
		overrides: { files: { [string]: string }?, exitcode: number?, writes: { [string]: string }? }
	): (Image.ProviderDeps, { commands: { { string } } })
		local files: { [string]: string } = overrides.files
			or { [SCRIPT] = SCRIPT_BYTES, [BASE] = png(1254, 1254, "base"), [DONOR] = png(1254, 1254, "donor") }
		local log: { commands: { { string } } } = { commands = {} }
		return {
			exists = function(path: string): boolean
				return files[path] ~= nil
			end,
			read = function(path: string): string
				return files[path] or error("spec harness read a path that does not exist: " .. path)
			end,
			write = function() end,
			createDirectory = function() end,
			run = function(args: { string }): Image.ProviderRunResult
				table.insert(log.commands, args)
				local exitcode = overrides.exitcode or 0
				if exitcode ~= 0 then
					return { stdout = "", stderr = "", exitcode = exitcode }
				end
				local written: { [string]: string } = overrides.writes or { [EDITED] = png(1254, 1254, "despeckled") }
				for path, bytes in written do
					files[path] = bytes
				end
				return { stdout = "", stderr = "", exitcode = 0 }
			end,
		},
			log
	end

	it("runs one argv naming the pinned script with sorted parameters", function()
		local argv = Postprocess.argv(CONFIG, transform {})
		expect(argv[1]):toBe(CONFIG.interpreter)
		expect(argv[2]):toBe(SCRIPT)
		expect(argv[3]):toBe "--seed=0"
		expect(argv[4]):toBe "--sigma=3"
	end)

	it("executes the public host postprocess consumer and refuses script drift before spending", function()
		for _, drifted in { false, true } do
			local value = transform(if drifted then { scriptDigest = "changed" } else {})
			local deps, log = harness {}
			local tool = { tool = "fixture", toolVersion = "v1", adapter = "fixture" }
			local host = Host.create {
				name = "postprocess-request-fixture",
				deps = deps,
				bindings = { projection = { kind = "postprocess", transform = value, delivery = true } },
				codec = Fixture.codec,
				digest = Fixture.digest,
				measure = MEASURE,
				provider = PROVIDER,
				postprocess = CONFIG,
				review = Review.DEFAULT_CONFIG,
				tools = { matte = tool, register = tool, deliver = tool },
			}
			local outcome = host.runStage(
				Generate.plan(BRIEF, { { id = "projection", operation = "transform" } }).stages[1],
				BRIEF,
				artifacts(),
				{ capabilities = {}, destinations = {}, mutationBudget = 0 },
				{
					idempotencyKey = "fixture",
					cancelled = function()
						return false
					end,
				}
			)
			expect(outcome.status):toBe(if drifted then "rejected" else "returned")
			expect(#log.commands):toBe(if drifted then 0 else 1)
			if not drifted then
				assert(outcome.status == "returned")
				expect(assert(outcome.output.artifacts)[1].id):toBe(value.id)
				expect(assert(outcome.output.artifacts)[1].locator):toBe(EDITED)
				expect(assert(outcome.output.artifacts)[1].semanticId):toBe(BRIEF.delivery.semanticId)
				expect(assert(assert(outcome.output.derivations)[1].parents)[1].artifactDigest):toBe(
					artifacts()[1].digest
				)
			end
		end
	end)

	it("claims determinism and pins the script by digest in its invocation", function()
		local invocation = Postprocess.invocation(CONFIG, transform {})
		expect(invocation.deterministic):toBe(true)
		expect(invocation.tool):toBe(SCRIPT)
		expect(invocation.toolVersion):toBe(Fixture.digest(SCRIPT_BYTES))
		expect(invocation.provider):toBeNil()
		expect(invocation.parametersFingerprint):toBe(Generate.fingerprint(Postprocess.argv(CONFIG, transform {})))
	end)

	it("carries deterministic postprocess invocations through receipt execution", function()
		local deps, log = harness {}
		local function digest(bytes: string): string
			local hashed = crypto.digest(crypto.hash.sha256, bytes)
			local hex = {}
			for index = 0, buffer.len(hashed) - 1 do
				table.insert(hex, ("%02x"):format(buffer.readu8(hashed, index)))
			end
			return table.concat(hex)
		end
		local config = table.clone(CONFIG)
		config.digest = digest
		config.measure = { digest = digest, bounds = BOUNDS }
		local declared = transform { scriptDigest = digest(SCRIPT_BYTES) }
		local plan = Generate.plan(BRIEF, {
			{ id = "inputs", operation = "import" },
			{ id = "transform", operation = "transform", dependsOn = { "inputs" }, deterministic = true },
		})
		local receipt = Generate.execute(BRIEF, plan, {
			name = "postprocess-execution-fixture",
			capabilities = {},
			environment = {},
			now = function()
				return 0
			end,
			runStage = function(stage, _brief, inputs)
				if stage.id == "inputs" then
					local imported = artifacts()
					local lineage: { Generate.DerivationDraft } = {}
					for _, artifact in imported do
						artifact.digest = digest(deps.read(assert(artifact.locator)))
						local derivation: Generate.DerivationDraft = {
							artifactId = artifact.id,
							artifactDigest = artifact.digest,
							origin = "imported",
							parents = {},
							inputDigests = { artifact.digest },
							rights = { source = { state = "known", value = "fixture" } },
						}
						table.insert(lineage, derivation)
					end
					return { status = "returned", output = { artifacts = imported, derivations = lineage } }
				end
				return Postprocess.runStage(config, deps, declared, inputs)
			end,
		}, { capabilities = {}, destinations = {}, mutationBudget = 0 })
		for _, record in receipt.stages do
			assert(record.status == "returned", record.detail)
		end
		expect(receipt.status):toBe "produced"
		assert(receipt.status == "produced")
		expect(#log.commands):toBe(1)
		expect(receipt.stages[2].invocations[1].parametersFingerprint):toBe(
			Generate.fingerprint(Postprocess.argv(config, declared))
		)
	end)

	it("emits a derived candidate whose parents are the exact input frames", function()
		local deps, log = harness {}
		local outcome = Postprocess.runStage(CONFIG, deps, transform {}, artifacts())
		expect(outcome.status):toBe "returned"
		assert(outcome.status == "returned")
		expect(#log.commands):toBe(1)
		local output = outcome.output
		expect(assert(output.artifacts)[1].id):toBe "deterministic-edit"
		expect(assert(output.derivations)[1].origin):toBe "derived"
		expect(assert(output.derivations)[1].attempt):toBe(6)
		expect(#assert(assert(output.derivations)[1].parents)):toBe(2)
		expect(assert(assert(output.derivations)[1].environment).transformToolExitCode):toBe "0"
		expect(assert(assert(output.derivations)[1].environment).adapter):toBe(CONFIG.adapter)
	end)

	it("refuses a drifted script, an existing output, a non-zero exit, and no declared input", function()
		local drifted, driftedLog = harness {}
		local outcome =
			Postprocess.runStage(CONFIG, drifted, transform { scriptDigest = string.rep("0", 32) }, artifacts())
		expect(outcome.status):toBe "rejected"
		assert(outcome.status == "rejected")
		expect(outcome.detail):toContain "pins script digest"
		expect(#driftedLog.commands):toBe(0)

		local occupied, occupiedLog = harness {
			files = {
				[SCRIPT] = SCRIPT_BYTES,
				[BASE] = png(1254, 1254, "base"),
				[DONOR] = png(1254, 1254, "donor"),
				[EDITED] = png(1254, 1254, "already"),
			},
		}
		local overwritten = Postprocess.runStage(CONFIG, occupied, transform {}, artifacts())
		expect(stageDetail(overwritten)):toContain "would overwrite"
		expect(#occupiedLog.commands):toBe(0)

		local failing = harness { exitcode = 2 }
		expect(stageDetail(Postprocess.runStage(CONFIG, failing, transform {}, artifacts()))):toContain "exited 2"

		local silent = harness { writes = {} }
		expect(stageDetail(Postprocess.runStage(CONFIG, silent, transform {}, artifacts()))):toContain "wrote no"

		local empty, emptyLog = harness {}
		expect(stageDetail(Postprocess.runStage(CONFIG, empty, transform { inputs = {} }, {}))):toContain "no input frame"
		expect(#emptyLog.commands):toBe(0)
	end)

	it("faults a transform that rewrote its own read-only input", function()
		local deps = harness {
			writes = { [EDITED] = png(1254, 1254, "despeckled"), [BASE] = png(1254, 1254, "MUTATED") },
		}
		local outcome = Postprocess.runStage(CONFIG, deps, transform {}, artifacts())
		expect(outcome.status):toBe "faulted"
		assert(outcome.status == "faulted")
		expect(outcome.detail):toContain "rewrote its read-only input"
	end)
end)

describe("Image.host", function()
	local TOOLS: Image.HostTools = {
		matte = { tool = "spec/matte", toolVersion = "spec.matte.v1", adapter = "spec.image.matte.v1" },
		register = { tool = "spec/register", toolVersion = "spec.register.v1", adapter = "spec.image.register.v1" },
		deliver = { tool = "spec/deliver", toolVersion = "spec.deliver.v1", adapter = "spec.image.deliver.v1" },
	}

	local POSTPROCESS: Image.PostprocessConfig = {
		adapter = "spec.image.postprocess.v1",
		capability = "deterministic-image-transform",
		interpreter = "spec-interpreter",
		digest = Fixture.digest,
		measure = MEASURE,
	}

	local function options(deps: Image.HostDeps, bindings: { [string]: Image.HostBinding }): Image.HostOptions
		return {
			name = "spec-image",
			deps = deps,
			bindings = bindings,
			codec = Fixture.codec,
			digest = Fixture.digest,
			measure = MEASURE,
			provider = PROVIDER,
			postprocess = POSTPROCESS,
			review = Review.DEFAULT_CONFIG,
			tools = TOOLS,
		}
	end

	local function stage(id: string, mutation: boolean): Generate.Stage
		return {
			id = id,
			operation = if mutation then "publish" else "generate",
			dependsOn = {},
			requires = {},
			mutation = mutation,
			deterministic = false,
			rollback = if mutation then "required" else "none",
			parameters = {},
			estimatedCostMicros = 0,
		}
	end

	local SPEC_BRIEF = brief()
	local AUTHORITY: Generate.Authority = { capabilities = {}, destinations = {}, mutationBudget = 0 }
	local CONTEXT: Generate.RunContext = {
		idempotencyKey = "spec",
		cancelled = function(): boolean
			return false
		end,
	}

	local function world(seed: { [string]: string }): Image.HostDeps
		local files: { [string]: string } = seed
		return {
			exists = function(path: string): boolean
				return files[path] ~= nil
			end,
			read = function(path: string): string
				return files[path] or error("spec harness read a path that does not exist: " .. path)
			end,
			write = function(path: string, bytes: string)
				files[path] = bytes
			end,
			createDirectory = function(path: string)
				files[path] = ""
			end,
			run = function(_args: { string }): Image.ProviderRunResult
				files[OUTPUT] = png(1254, 1254, "sheet")
				return { stdout = OUTPUT, stderr = "", exitcode = 0 }
			end,
		}
	end

	it("routes a bound generate stage to the provider adapter", function()
		local host = Host.create(
			options(
				world { [SOURCE_ROOT .. "/fixture-props"] = "" },
				{ sheet = { kind = "provider", request = PROVIDER_REQUEST, attempt = 1 } }
			)
		)
		local outcome = host.runStage(stage("sheet", false), SPEC_BRIEF, {}, AUTHORITY, CONTEXT)
		expect(outcome.status):toBe "returned"
		assert(outcome.status == "returned")
		expect(#assert(outcome.output.artifacts)):toBe(1)
		expect(assert(outcome.output.derivations)[1].origin):toBe "original"
	end)

	it("refuses an unbound stage by name and a mutating stage outright", function()
		local unbound = Host.create(options(world {}, {}))
		local missing = unbound.runStage(stage("sheet", false), SPEC_BRIEF, {}, AUTHORITY, CONTEXT)
		expect(missing.status):toBe "rejected"
		assert(missing.status == "rejected")
		expect(missing.detail):toContain "no image adapter bound"

		local host =
			Host.create(options(world {}, { mint = { kind = "provider", request = PROVIDER_REQUEST, attempt = 1 } }))
		local mutating = host.runStage(stage("mint", true), SPEC_BRIEF, {}, AUTHORITY, CONTEXT)
		expect(mutating.status):toBe "rejected"
		assert(mutating.status == "rejected")
		expect(mutating.detail):toContain "holds no grant"
	end)

	it("routes a bound deliver stage to the deterministic resample adapter", function()
		local sourcePath = OUTPUT_ROOT .. "/fixture/spec-surface-source.png"
		local outputPath = OUTPUT_ROOT .. "/fixture/spec-surface-deliver.png"
		local files: { [string]: string } = {
			[sourcePath] = Fixture.codec.encodeRgba(1254, 1254, function(x: number, y: number): Image.Rgba
				local value = (x + y) % 256
				return { r = value, g = value, b = value, a = 255 }
			end),
		}
		local deps: Image.HostDeps = {
			exists = function(path: string): boolean
				return files[path] ~= nil
			end,
			read = function(path: string): string
				return files[path] or error("spec harness read a path that does not exist: " .. path)
			end,
			write = function(path: string, bytes: string)
				files[path] = bytes
			end,
			createDirectory = function() end,
			run = function(): Image.ProviderRunResult
				return { stdout = "", stderr = "", exitcode = 0 }
			end,
		}
		local host = Host.create(options(deps, {
			deliver = {
				kind = "deliver",
				sourceId = "spec.surface.original.v1",
				outputId = "spec.surface.deliver.v1",
				outputPath = outputPath,
				declaredWidth = 1024,
				declaredHeight = 1024,
			},
		}))
		local source: Generate.Artifact = {
			id = "spec.surface.original.v1",
			digest = "spec",
			digestAlgorithm = "sha256",
			mediaType = "image/png",
			byteCount = #files[sourcePath],
			locator = sourcePath,
			metadata = {},
		}
		local outcome = host.runStage(stage("deliver", false), SPEC_BRIEF, { source }, AUTHORITY, CONTEXT)
		expect(outcome.status):toBe "returned"
		assert(outcome.status == "returned")
		local complete = outcome
		expect(assert(complete.output.metadata).resampled):toBe(true)
		expect(width(assert(complete.output.metadata).preFacts)):toBe(1254)
		expect(width(assert(complete.output.metadata).postFacts)):toBe(1024)
		expect(assert(complete.output.invocations)[1].deterministic):toBe(true)
		expect(assert(complete.output.invocations)[1].tool):toBe(TOOLS.deliver.tool)
		local decoded = Fixture.codec.decode(files[outputPath])
		assert(decoded.ok)
		expect(decoded.image.width):toBe(1024)
	end)

	it("refuses a transform whose source artifact is absent rather than crashing", function()
		local host = Host.create(options(world {}, {
			deliver = {
				kind = "deliver",
				sourceId = "missing.v1",
				outputId = "spec.surface.deliver.v1",
				outputPath = OUTPUT_ROOT .. "/fixture/spec-surface-deliver.png",
				declaredWidth = 64,
				declaredHeight = 64,
			},
		}))
		local outcome = host.runStage(stage("deliver", false), SPEC_BRIEF, {}, AUTHORITY, CONTEXT)
		expect(outcome.status):toBe "rejected"
		assert(outcome.status == "rejected")
		expect(outcome.detail):toContain "deliver source"
	end)

	it("offers no compensation, because it performs no mutation to compensate", function()
		local host = Host.create(options(world {}, {}))
		expect(host.compensate):toBeNil()
		expect(host.name):toBe "spec-image"
	end)
end)

return nil
