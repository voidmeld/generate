--!strict

local json = require "@std/json"
local crypto = require "@lute/crypto"

local Fixture = require "./fixtures/image-codec"
local Thresholds = require "./fixtures/image-thresholds"
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
local Lane = require "../src/image/lane"

local MATTE_PARAMETERS: Image.MatteParameters = { interiorDistance = 3, boundaryDistance = 2, featherRadius = 1.5 }

local BOUNDS: Image.MeasureBounds = { minShortSide = 896, maxLongSide = 2048 }
local MEASURE: Image.MeasureConfig = { digest = Fixture.digest, bounds = BOUNDS }

local REQUEST_CONFIG: Image.RequestConfig = {
	schema = "spec.image-run.v2",
	indent = "  ",
	serialize = function(value: unknown): string
		return json.serialize(value :: json.Value)
	end,
}

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
	disposition = "active" :: Generate.CandidateDisposition,
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

local function altered(overrides: unknown): Image.ProviderRequest
	local request = table.clone(PROVIDER_REQUEST)
	local fields = request :: Image.ProviderRequest & { [string]: unknown }
	for key, value in overrides :: { [string]: unknown } do
		fields[key] = value
	end
	return request :: Image.ProviderRequest
end

local function brief(): Generate.Brief
	return Generate.brief {
		schemaVersion = 1,
		id = "spec.surface.v1",
		kind = "image" :: Generate.AssetKind,
		intent = { role = "a spec surface", style = "plain", description = "one spec subject" },
		constraints = { opacity = "opaque" },
		review = {
			rubric = "docs/review.md",
			rubricFingerprint = string.rep("d6ee7295", 8),
			views = { "artifact" },
			blindness = "required" :: Generate.ReviewRequirement,
			independence = "required" :: Generate.ReviewRequirement,
		},
		provenance = { requireParentLineage = false, requiredRightsFacts = { "source" } :: { Generate.RightsFactName } },
		delivery = { semanticId = "spec.surface", target = "image" },
	}
end

local BRIEF = brief()

local PLAN = Generate.plan(BRIEF, {
	{ id = "candidate", operation = "generate", requires = { "reference-image" } },
	{ id = "review", operation = "review", dependsOn = { "candidate" } },
})

local function document(): Image.RequestDocument
	return {
		schema = REQUEST_CONFIG.schema,
		briefId = BRIEF.id,
		artifacts = {
			{
				id = "spec.surface.original.v1",
				slug = "spec-surface",
				role = "spec-surface",
				tiles = true,
				transparentBackground = false,
				singleSubject = true,
			},
		},
		matte = false,
		bindings = {
			candidate = {
				kind = "provider",
				attempt = 1,
				delivery = true,
				request = {
					group = "fixture",
					slug = "spec-surface",
					prompt = "draw one spec surface",
					subject = "surface",
					family = "surface",
					variant = "single_plane",
					version = "v1",
					sourceDirectory = SOURCE_ROOT .. "/fixture-props",
				},
			},
			review = {
				kind = "review",
				request = {
					packetId = "spec.surface.v1/review",
					candidateId = "spec.surface.v1",
					revision = 1,
					producer = "spec",
					candidateArtifactId = "spec.surface.original.v1",
					evidence = {},
					rubric = { id = "spec", fingerprint = "spec" },
					requestedViews = {},
					captureEnvironment = {},
				},
			},
		},
	}
end

local function requestRefusal(
	value: Image.RequestDecoded | Image.RequestBound | Image.RequestRefusal
): Image.RequestRefusal
	assert(not value.ok)
	return value
end

local function stageDetail(value: Generate.StageOutcome): string
	assert(value.status ~= "returned")
	return value.detail
end

local function bindingFields(value: unknown): { [string]: unknown }
	assert(type(value) == "table")
	return value :: { [string]: unknown }
end

local function withBindings(mutate: (bindings: { [string]: unknown }) -> ()): Image.RequestDocument
	local built = document()
	mutate(built.bindings)
	return built
end

describe("Image.request", function()
	it("derives one document from the brief that owns the prompt", function()
		local source = document()
		local derived = Request.fromBrief(
			REQUEST_CONFIG,
			{ brief = BRIEF, imageRun = { artifacts = source.artifacts, bindings = source.bindings } },
			"spec.generate.luau"
		)
		expect(derived.ok):toBe(true)
		assert(derived.ok == true)
		expect(derived.document.schema):toBe(REQUEST_CONFIG.schema)
		expect(derived.document.briefId):toBe(BRIEF.id)
		expect(#derived.document.artifacts):toBe(1)

		local undeclared =
			Request.fromBrief(REQUEST_CONFIG, { brief = BRIEF, imageRun = { bindings = source.bindings } }, "spec")
		expect(undeclared.ok):toBe(false)
		assert(undeclared.ok == false)
		expect(undeclared.reason):toBe "artifacts"
	end)

	it("refuses a brief that declares no image run rather than inventing an empty one", function()
		expect(requestRefusal(Request.fromBrief(REQUEST_CONFIG, {}, "spec")).reason):toBe "image-run"
		expect(
			requestRefusal(Request.fromBrief(REQUEST_CONFIG, { brief = BRIEF, imageRun = { bindings = {} } }, "spec")).reason
		):toBe "image-run"
		expect(
			requestRefusal(Request.fromBrief(REQUEST_CONFIG, { imageRun = { bindings = document().bindings } }, "spec")).reason
		):toBe "brief"
	end)

	it("refuses a document carrying another schema or naming no brief", function()
		local decoded =
			Request.decode(REQUEST_CONFIG, { schema = "spec.image-run.v0", briefId = BRIEF.id, bindings = {} }, "spec")
		expect(decoded.ok):toBe(false)
		assert(decoded.ok == false)
		expect(decoded.reason):toBe "request"
		local unnamed = Request.decode(REQUEST_CONFIG, { schema = REQUEST_CONFIG.schema, bindings = {} }, "spec")
		expect(unnamed.ok):toBe(false)
		assert(unnamed.ok == false)
		expect(unnamed.reason):toBe "request"
	end)

	it("preserves the decoded document and extension fields", function()
		local value = document()
		local extension = value :: Image.RequestDocument & { marker: string? }
		extension.marker = "consumer extension"
		local decoded = Request.decode(REQUEST_CONFIG, value, "spec")
		assert(decoded.ok)
		expect(decoded.document == value):toBe(true)
		expect(extension.marker):toBe "consumer extension"
	end)

	it("refuses malformed nested provider and review request fields", function()
		local cases: { { stage: string, field: string, value: unknown } } = {
			{ stage = "candidate", field = "subject", value = 12 },
			{ stage = "candidate", field = "operationId", value = false },
			{ stage = "candidate", field = "declaredWidth", value = "wide" },
			{ stage = "candidate", field = "referenceImages", value = { 12 } },
			{ stage = "candidate", field = "rights", value = { source = { state = "invented" } } },
			{ stage = "candidate", field = "rights", value = { notes = { false } } },
			{ stage = "review", field = "revision", value = "first" },
			{ stage = "review", field = "rubric", value = { id = "spec" } },
			{ stage = "review", field = "evidence", value = { { artifactId = "spec", view = "front", role = false } } },
			{ stage = "review", field = "requestedViews", value = { 12 } },
			{ stage = "review", field = "captureEnvironment", value = { adapter = false } },
		}
		for _, case in cases do
			local value = document()
			local binding = bindingFields(value.bindings[case.stage])
			bindingFields(binding.request)[case.field] = case.value
			local outcome = Request.bindings(value, PLAN)
			expect(requestRefusal(outcome).reason):toBe "bindings"
		end
	end)

	it("validates register target bands in artifacts and stage bindings", function()
		local target = {
			hue = 220,
			saturationCeiling = 0.3,
			value = {
				p5 = { min = 0, max = 50, target = 25 },
				p50 = { min = 50, max = 150, target = 100 },
				p95 = { min = 150, max = 255, target = 200 },
			},
		}
		local value = document()
		value.artifacts[1].registerTarget = target
		local plan = Generate.plan(BRIEF, {
			{ id = "candidate", operation = "generate" },
			{ id = "register", operation = "generate", dependsOn = { "candidate" } },
			{ id = "review", operation = "review", dependsOn = { "register" } },
		})
		value.bindings.register = {
			kind = "register",
			sourceId = "source",
			outputId = "output",
			outputPath = "output.png",
			target = target,
		}
		expect(Request.bindings(value, plan).ok):toBe(true)
		for _, invalid in
			{
				{},
				{ hue = 220, saturationCeiling = 0.3 },
				{ hue = 220, saturationCeiling = 0.3, value = { p5 = {}, p50 = {}, p95 = {} } },
			}
		do
			bindingFields(value.bindings.register).target = invalid
			expect(Request.bindings(value, plan).ok):toBe(false)
			expect(Request.artifactsRefusal({
				{
					id = "spec",
					slug = "spec",
					role = "spec",
					tiles = true,
					transparentBackground = false,
					singleSubject = true,
					registerTarget = invalid,
				},
			}, "spec") ~= nil):toBe(true)
		end
	end)

	it("refuses a document written for another brief even when the stage names line up", function()
		local crossed = document()
		crossed.briefId = "spec.other.v1"
		local bound = Request.bindings(crossed, PLAN)
		expect(bound.ok):toBe(false)
		assert(bound.ok == false)
		expect(bound.detail):toContain "was written for brief"
	end)

	it("binds a provider and a review stage the plan actually declares", function()
		local bound = Request.bindings(document(), PLAN)
		expect(bound.ok):toBe(true)
		assert(bound.ok == true)
		local bindings = bound.bindings
		assert(bindings.candidate.kind == "provider")
		expect(bindings.candidate.kind):toBe "provider"
		expect(bindings.candidate.attempt):toBe(1)
		expect(bindings.candidate.delivery):toBe(true)
		expect(bindings.review.kind):toBe "review"
	end)

	it("admits the declared matte stage and refuses every other postprocess in its place", function()
		local mattePlan = Generate.plan(BRIEF, {
			{ id = "candidate", operation = "generate", requires = { "reference-image" } },
			{
				id = "matte",
				operation = "generate",
				dependsOn = { "candidate" },
				requires = { "deterministic-image-matte" },
			},
			{ id = "review", operation = "review", dependsOn = { "matte" } },
		})
		local matted = document()
		matted.matte = true
		matted.bindings.matte = {
			kind = "matte",
			sourceId = "spec.surface.original.v1",
			outputId = "spec.surface.matte.v1",
			outputPath = OUTPUT_ROOT .. "/fixture/spec-surface-matte.png",
		}
		expect(Request.bindings(matted, mattePlan).ok):toBe(true)
		bindingFields(matted.bindings.matte).kind = "postprocess"
		expect(Request.bindings(matted, mattePlan).ok):toBe(false)
	end)

	it("admits a declared deliver stage and refuses a non-whole or missing declared size", function()
		local deliverPlan = Generate.plan(BRIEF, {
			{ id = "candidate", operation = "generate", requires = { "reference-image" } },
			{
				id = "deliver",
				operation = "generate",
				dependsOn = { "candidate" },
				requires = { "deterministic-image-deliver" },
			},
			{ id = "review", operation = "review", dependsOn = { "deliver" } },
		})
		local delivered = document()
		delivered.bindings.deliver = {
			kind = "deliver",
			sourceId = "spec.surface.original.v1",
			outputId = "spec.surface.deliver.v1",
			outputPath = OUTPUT_ROOT .. "/fixture/spec-surface-deliver.png",
			declaredWidth = 1024,
			declaredHeight = 1024,
		}
		local bound = Request.bindings(delivered, deliverPlan)
		expect(bound.ok):toBe(true)
		assert(bound.ok == true)
		assert(bound.bindings.deliver.kind == "deliver")
		expect(bound.bindings.deliver.declaredWidth):toBe(1024)

		local fractional = document()
		fractional.bindings.deliver = table.clone(bindingFields(delivered.bindings.deliver))
		bindingFields(fractional.bindings.deliver).declaredWidth = 1024.5
		expect(Request.bindings(fractional, deliverPlan).ok):toBe(false)

		local missing = document()
		missing.bindings.deliver = table.clone(bindingFields(delivered.bindings.deliver))
		bindingFields(missing.bindings.deliver).declaredHeight = nil
		expect(Request.bindings(missing, deliverPlan).ok):toBe(false)

		local misnamedPlan = Generate.plan(BRIEF, {
			{ id = "candidate", operation = "generate", requires = { "reference-image" } },
			{
				id = "resize",
				operation = "generate",
				dependsOn = { "candidate" },
				requires = { "deterministic-image-deliver" },
			},
			{ id = "review", operation = "review", dependsOn = { "resize" } },
		})
		local misnamed = document()
		misnamed.bindings.resize = table.clone(bindingFields(delivered.bindings.deliver))
		expect(Request.bindings(misnamed, misnamedPlan).ok):toBe(false)
	end)

	it("refuses a binding whose stage the plan never declared and a plan stage left unbound", function()
		local extra = Request.bindings(
			withBindings(function(bindings)
				bindings.postprocess = { kind = "review", request = {} }
			end),
			PLAN
		)
		expect(extra.ok):toBe(false)
		assert(extra.ok == false)
		expect(extra.reason):toBe "bindings"

		local unbound = Request.bindings(
			withBindings(function(bindings)
				bindings.review = nil
			end),
			PLAN
		)
		expect(unbound.ok):toBe(false)
		assert(unbound.ok == false)
		expect(unbound.detail):toContain "no binding"
	end)

	it("refuses an unsupported binding kind and a provider attempt that is not a whole ordinal", function()
		expect(Request.bindings(
			withBindings(function(bindings)
				bindings.candidate = { kind = "publish", request = {} }
			end),
			PLAN
		).ok):toBe(false)
		expect(Request.bindings(
			withBindings(function(bindings)
				bindingFields(bindings.candidate).attempt = 1.5
			end),
			PLAN
		).ok):toBe(false)
	end)

	it("refuses a declaration with no artifacts, a missing field, or a duplicate id", function()
		expect(Request.artifactsRefusal(nil, "spec") ~= nil):toBe(true)
		expect(Request.artifactsRefusal({}, "spec") ~= nil):toBe(true)
		local complete = document().artifacts[1]
		for _, field in { "id", "slug", "role", "tiles", "transparentBackground", "singleSubject" } do
			local partial: { [string]: unknown } = {}
			for key, value in complete do
				partial[key :: string] = value
			end
			partial[field] = nil
			expect(Request.artifactsRefusal({ partial }, "spec") ~= nil):toBe(true)
		end
		local twice = Request.artifactsRefusal({ complete, table.clone(complete) }, "spec")
		expect(assert(twice).detail):toContain "declared twice"
		expect(Request.artifactsRefusal({ complete }, "spec")):toBe(nil)
	end)

	it("encodes every object key in sorted order so a request file stays diff-stable", function()
		local encoded = Request.encode(REQUEST_CONFIG, document())
		expect(string.sub(encoded, -1)):toBe "\n"
		expect(Request.encode(REQUEST_CONFIG, document())):toBe(encoded)
		local schemaAt = string.find(encoded, '"schema"', 1, true)
		local bindingsAt = string.find(encoded, '"bindings"', 1, true)
		expect(bindingsAt ~= nil and schemaAt ~= nil and bindingsAt < schemaAt):toBe(true)
		expect(Request.encodeValue(REQUEST_CONFIG, { b = 1, a = 2 }, "")):toBe '{\n  "a": 2,\n  "b": 1\n}'
		expect(Request.encodeValue(REQUEST_CONFIG, { "x", "y" }, "")):toBe '[\n  "x",\n  "y"\n]'
	end)
end)

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

	local function staging(overrides: unknown): Image.ReviewRequest
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
		for key, value in overrides :: { [string]: unknown } do
			(built :: typeof(built) & { [string]: unknown })[key] = value
		end
		return built :: Image.ReviewRequest
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
		local log = { written = {} :: { Recorded }, invocations = {} :: { { string } } }
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

	local function transform(overrides: unknown): Image.PostprocessTransform
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
		for key, value in overrides :: { [string]: unknown } do
			(built :: typeof(built) & { [string]: unknown })[key] = value
		end
		return built :: Image.PostprocessTransform
	end

	local function harness(
		overrides: { files: { [string]: string }?, exitcode: number?, writes: { [string]: string }? }
	): (Image.ProviderDeps, { commands: { { string } } })
		local files: { [string]: string } = overrides.files
			or { [SCRIPT] = SCRIPT_BYTES, [BASE] = png(1254, 1254, "base"), [DONOR] = png(1254, 1254, "donor") }
		local log = { commands = {} :: { { string } } }
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
				if (overrides.exitcode or 0) ~= 0 then
					return { stdout = "", stderr = "", exitcode = overrides.exitcode :: number }
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

	local function boundTransform(entry: unknown, mutation: boolean?): Image.RequestBound | Image.RequestRefusal
		local value = document()
		value.bindings = { projection = entry }
		return Request.bindings(
			value,
			(
					{
						briefId = value.briefId,
						stages = { { id = "projection", mutation = mutation == true } },
					} :: unknown
				) :: Generate.Plan
		)
	end

	it("binds each supported postprocess kind without changing artifact, input, output or rights identity", function()
		for _, kind in { "composite", "despeckle", "region-pass" } do
			local value =
				transform { kind = kind, rights = { source = { state = "known", value = "fixture-original" } } }
			local bound = boundTransform { kind = "postprocess", transform = value, delivery = true }
			expect(bound.ok):toBe(true)
			assert(bound.ok == true)
			assert(bound.bindings.projection.kind == "postprocess")
			expect(bound.bindings.projection.kind):toBe "postprocess"
			expect(bound.bindings.projection.transform):toBe(value)
			expect(bound.bindings.projection.transform.id):toBe "deterministic-edit"
			expect(bound.bindings.projection.transform.inputs[1].path):toBe(BASE)
			expect(bound.bindings.projection.transform.outputPath):toBe(EDITED)
			expect(bound.bindings.projection.delivery):toBe(true)
		end
	end)

	it("refuses malformed, unsupported, undeclared and mutating postprocess requests before execution", function()
		for _, field in { "id", "kind", "scriptPath", "scriptDigest", "inputs", "outputPath", "parameters", "attempt" } do
			local value = transform {}
			value[field] = nil
			expect(boundTransform({ kind = "postprocess", transform = value }).ok):toBe(false)
		end
		local invalid: { unknown } = {
			{ kind = "unknown" },
			{ attempt = 0 },
			{ attempt = 1.5 },
			{ inputs = {} },
			{ inputs = { { role = "", path = BASE } } },
			{ parameters = { seed = 0 } },
		}
		for _, changed in invalid do
			expect(boundTransform({ kind = "postprocess", transform = transform(changed) }).ok):toBe(false)
		end
		expect(boundTransform({ kind = "unknown", transform = transform {} }).ok):toBe(false)
		expect(boundTransform({ kind = "postprocess" }).ok):toBe(false)
		expect(boundTransform({ kind = "postprocess", transform = transform {} }, true).ok):toBe(false)
		local extra = document()
		extra.bindings = { absent = { kind = "postprocess", transform = transform {} } }
		expect(Request.bindings(extra, PLAN).ok):toBe(false)
	end)

	it("executes the public request-to-host postprocess consumer and refuses script drift before spending", function()
		for _, drifted in { false, true } do
			local value = transform(if drifted then { scriptDigest = "changed" } else {})
			local bound = boundTransform { kind = "postprocess", transform = value, delivery = true }
			expect(bound.ok):toBe(true)
			assert(bound.ok == true)
			local deps, log = harness {}
			local tool = { tool = "fixture", toolVersion = "v1", adapter = "fixture" }
			local host = Host.create {
				name = "postprocess-request-fixture",
				deps = deps,
				bindings = bound.bindings,
				codec = Fixture.codec,
				digest = Fixture.digest,
				measure = MEASURE,
				provider = PROVIDER,
				postprocess = CONFIG,
				review = Review.DEFAULT_CONFIG,
				tools = { matte = tool, register = tool, deliver = tool },
			}
			local outcome = host.runStage(
				({ id = "projection", mutation = false } :: unknown) :: Generate.Stage,
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
						table.insert(lineage, {
							artifactId = artifact.id,
							artifactDigest = artifact.digest,
							origin = "imported",
							parents = {},
							inputDigests = { artifact.digest },
							rights = { source = { state = "known", value = "fixture" } },
						})
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
		expect((assert(complete.output.metadata).preFacts :: Image.DeliverFacts).width):toBe(1254)
		expect((assert(complete.output.metadata).postFacts :: Image.DeliverFacts).width):toBe(1024)
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

describe("Image.lane", function()
	local QA: Image.QaConfig = { schema = "spec.image-qa.v1", codec = Fixture.codec, thresholds = Thresholds }
	local CONFIG: Image.LaneConfig = { qa = QA, matteParameters = MATTE_PARAMETERS }

	local function card(opacity: (x: number, y: number) -> number): string
		return Fixture.codec.encodeRgba(16, 16, function(x: number, y: number): Image.Rgba
			return { r = 100, g = 100, b = 100, a = opacity(x, y) }
		end)
	end

	local function feathered(x: number, y: number): number
		local dx, dy = x - 7.5, y - 7.5
		return math.clamp(math.floor((5.5 - math.sqrt(dx * dx + dy * dy)) * 170), 0, 255)
	end

	local PRE = "pre.png"
	local POST = "post.png"
	local files: { [string]: string } = { [PRE] = card(function()
		return 255
	end), [POST] = card(feathered) }
	local deps: Image.QaDeps = {
		exists = function(path: string): boolean
			return files[path] ~= nil
		end,
		read = function(path: string): string
			return files[path] or error("spec harness read " .. path)
		end,
	}

	local function artifact(id: string, locator: string, digest: string): Generate.Artifact
		return {
			id = id,
			digest = digest,
			digestAlgorithm = "sha256",
			mediaType = Measure.MEDIA_TYPE,
			byteCount = #files[locator],
			locator = locator,
			metadata = {},
		}
	end

	local function laneDocument(matte: boolean): Image.RequestDocument
		return {
			schema = REQUEST_CONFIG.schema,
			briefId = BRIEF.id,
			artifacts = {
				{
					id = "card.matte.v1",
					slug = "card",
					role = "cutout-card",
					tiles = false,
					transparentBackground = true,
					singleSubject = false,
				},
			},
			matte = matte,
			bindings = {
				matte = {
					kind = "matte",
					sourceId = "card.original.v1",
					outputId = "card.matte.v1",
					outputPath = POST,
				},
			},
		}
	end

	it("returns the produced gate alone when the lane applied no matte and no register", function()
		local plain: Image.RequestDocument = laneDocument(false)
		plain.bindings = {}
		plain.artifacts[1].id = "card.original.v1"
		local produced = Lane.summary(CONFIG, deps, plain, { artifact("card.original.v1", POST, string.rep("a", 8)) })
		expect(produced.status):toBe "produced"
		expect(produced.preMatte):toBeNil()
		expect(produced.matte):toBeNil()
	end)

	it("records a before gate, an after gate, and both digests when a matte was applied", function()
		local summary = Lane.summary(CONFIG, deps, laneDocument(true), {
			artifact("card.original.v1", PRE, string.rep("b", 8)),
			artifact("card.matte.v1", POST, string.rep("c", 8)),
		})
		expect(summary.status):toBe "produced"
		expect(assert(summary.matte).applied):toBe(true)
		expect(assert(summary.matte).parameters.featherRadius):toBe(MATTE_PARAMETERS.featherRadius)
		expect(assert(summary.matte).sha256["card.matte.v1"].preMatteSha256):toBe(string.rep("b", 8))
		expect(assert(summary.matte).sha256["card.matte.v1"].postMatteSha256):toBe(string.rep("c", 8))
		expect(assert(summary.preMatte).status):toBe "refused"
		expect(assert(summary.postMatte).status):toBe "produced"
	end)

	it("locates only the delivered image artifacts a receipt carries", function()
		local located = Lane.delivered {
			artifact("card.matte.v1", POST, string.rep("c", 8)),
			{
				id = "note",
				digest = "d",
				digestAlgorithm = "sha256",
				mediaType = "text/plain",
				locator = "note.txt",
				metadata = {},
			},
		}
		expect(located["card.matte.v1"]):toBe(POST)
		expect(located.note):toBeNil()
	end)
end)

return nil
