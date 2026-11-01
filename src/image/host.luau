--!strict

local Codec = require "./codec"
local Deliver = require "./deliver"
local Generate = require "../core"
local Matte = require "./matte"
local Measure = require "./measure"
local Postprocess = require "./postprocess"
local Provider = require "./provider"
local Register = require "./register"
local Review = require "./review"

export type Deps = {
	exists: (path: string) -> boolean,
	read: (path: string) -> string,
	write: (path: string, bytes: string) -> (),
	createDirectory: (path: string) -> (),
	run: (command: { string }) -> Provider.RunResult,
}

export type MatteBinding = { kind: "matte", sourceId: string, outputId: string, outputPath: string, delivery: boolean? }
export type RegisterBinding = {
	kind: "register",
	sourceId: string,
	outputId: string,
	outputPath: string,
	target: Register.DeclarationTarget,
	delivery: boolean?,
}
export type DeliverBinding = {
	kind: "deliver",
	sourceId: string,
	outputId: string,
	outputPath: string,
	declaredWidth: number,
	declaredHeight: number,
	delivery: boolean?,
}
export type Binding =
	{ kind: "provider", request: Provider.Request, attempt: number, delivery: boolean? }
	| MatteBinding
	| { kind: "postprocess", transform: Postprocess.Transform, delivery: boolean? }
	| RegisterBinding
	| DeliverBinding
	| { kind: "measure", evidence: { Measure.Evidence } }
	| { kind: "review", request: Review.Request }

export type Tool = { tool: string, toolVersion: string, adapter: string }

export type Tools = { matte: Tool, register: Tool, deliver: Tool }

type Converted = { bytes: string, tool: Tool, fingerprint: string, metadata: { [string]: unknown } }

export type Options = {
	name: string,
	deps: Deps,
	bindings: { [string]: Binding },
	codec: Codec.Codec,
	digest: Codec.Digest,
	measure: Measure.Config,
	provider: Provider.Config,
	postprocess: Postprocess.Config,
	review: Review.Config,
	tools: Tools,
	matteParameters: Matte.Parameters?,
	capabilities: { string }?,
	environment: { [string]: string }?,
}

local function sourceOf(artifacts: { Generate.Artifact }, id: string): Generate.Artifact?
	for _, artifact in artifacts do
		if artifact.id == id then
			return artifact
		end
	end
	return nil
end

local function derived(
	tool: Tool,
	artifact: Generate.Artifact,
	source: Generate.Artifact,
	fingerprint: string
): (Generate.Invocation, Generate.DerivationDraft)
	local invocation: Generate.Invocation = {
		tool = tool.tool,
		toolVersion = tool.toolVersion,
		provider = nil,
		model = nil,
		seed = nil,
		parametersFingerprint = fingerprint,
		deterministic = true,
	}
	return invocation,
		{
			artifactId = artifact.id,
			artifactDigest = artifact.digest,
			origin = "derived",
			parents = { { artifactId = source.id, artifactDigest = source.digest } },
			inputDigests = { source.digest },
			referenceDigests = {},
			invocation = invocation,
			environment = { adapter = tool.adapter },
			attempt = 1,
			disposition = "active",
		}
end

local function create(options: Options): Generate.Host
	local clock = 0
	local deps = options.deps
	local registerConfig: Register.Config = { codec = options.codec, digest = options.digest }
	local deliverConfig: Deliver.Config = { codec = options.codec, digest = options.digest }
	return {
		name = options.name,
		capabilities = options.capabilities or {
			options.provider.capability,
			options.postprocess.capability,
			"deterministic-image-matte",
			"deterministic-image-register",
			"deterministic-image-deliver",
		},
		environment = options.environment or { runtime = "lute", modality = "image" },
		now = function(): number
			clock += 0.001
			return clock
		end,
		runStage = function(
			stage: Generate.Stage,
			brief: Generate.Brief,
			artifacts: { Generate.Artifact },
			_authority: Generate.Authority,
			_context: Generate.RunContext
		): Generate.StageOutcome
			if stage.mutation then
				return {
					status = "rejected",
					detail = ("stage %s mutates; this image host holds no grant, destination or credential"):format(
						stage.id
					),
				}
			end
			local binding = options.bindings[stage.id]
			if binding == nil then
				return {
					status = "rejected",
					detail = ("stage %s has no image adapter bound to it"):format(stage.id),
				}
			end
			if binding.kind == "provider" then
				local outcome = Provider.runStage(options.provider, deps, binding.request, binding.attempt)
				if binding.delivery and outcome.status == "returned" then
					for _, artifact in outcome.output.artifacts or {} do
						artifact.semanticId = brief.delivery.semanticId
					end
				end
				return outcome
			elseif binding.kind == "postprocess" then
				local outcome = Postprocess.runStage(options.postprocess, deps, binding.transform, artifacts)
				if binding.delivery and outcome.status == "returned" then
					for _, artifact in outcome.output.artifacts or {} do
						artifact.semanticId = brief.delivery.semanticId
					end
				end
				return outcome
			elseif binding.kind == "measure" then
				return Measure.runStage(options.measure, deps, binding.evidence)
			elseif binding.kind == "review" then
				return Review.runStage(options.review, binding.request, artifacts)
			end

			local transform = binding
			local label = transform.kind
			if deps.exists(transform.outputPath) then
				return { status = "rejected", detail = ("%s would overwrite %s"):format(label, transform.outputPath) }
			end
			local source = sourceOf(artifacts, transform.sourceId)
			if source == nil or source.locator == nil then
				return { status = "rejected", detail = ("%s source %s is absent"):format(label, transform.sourceId) }
			end
			local found = source
			local locator = source.locator

			local converted: Converted
			if transform.kind == "matte" then
				if options.matteParameters == nil then
					return { status = "rejected", detail = "matte requires the consumer to declare matteParameters" }
				end
				local result = Matte.run(options.codec, deps.read(locator), options.matteParameters)
				if not result.ok then
					return { status = "rejected", detail = ("%s source %s: %s"):format(label, found.id, result.reason) }
				end
				converted = {
					bytes = result.bytes,
					tool = options.tools.matte,
					fingerprint = Generate.fingerprint(result.parameters),
					metadata = { sourceSha256 = found.digest, parameters = result.parameters },
				}
			elseif transform.kind == "register" then
				local declared = transform.target
				if
					type(declared) ~= "table"
					or type(declared.hue) ~= "number"
					or type(declared.saturationCeiling) ~= "number"
					or type(declared.value) ~= "table"
				then
					return { status = "rejected", detail = "register target is malformed" }
				end
				local target = {
					hue = declared.hue,
					saturationCeiling = declared.saturationCeiling,
					values = {
						p5 = declared.value.p5 and declared.value.p5.target,
						p50 = declared.value.p50 and declared.value.p50.target,
						p95 = declared.value.p95 and declared.value.p95.target,
					},
				}
				if
					type(target.values.p5) ~= "number"
					or type(target.values.p50) ~= "number"
					or type(target.values.p95) ~= "number"
				then
					return { status = "rejected", detail = "register target carries no percentile targets" }
				end
				local fingerprint = Generate.fingerprint(target)
				local result = Register.run(registerConfig, deps.read(locator), target)
				if not result.ok then
					return { status = "rejected", detail = ("%s source %s: %s"):format(label, found.id, result.reason) }
				end
				converted = {
					bytes = result.bytes,
					tool = options.tools.register,
					fingerprint = fingerprint,
					metadata = {
						preFacts = result.preFacts,
						postFacts = result.postFacts,
						sha256 = result.sha256,
						parameters = result.parameters,
					},
				}
			else
				local result =
					Deliver.run(deliverConfig, deps.read(locator), transform.declaredWidth, transform.declaredHeight)
				if not result.ok then
					return { status = "rejected", detail = ("%s source %s: %s"):format(label, found.id, result.reason) }
				end
				converted = {
					bytes = result.bytes,
					tool = options.tools.deliver,
					fingerprint = Generate.fingerprint(result.parameters),
					metadata = {
						resampled = result.resampled,
						preFacts = result.preFacts,
						postFacts = result.postFacts,
						sha256 = result.sha256,
						parameters = result.parameters,
					},
				}
			end
			deps.write(transform.outputPath, converted.bytes)
			local measured = Measure.measure(options.measure, converted.bytes)
			if not measured.ok then
				return {
					status = "rejected",
					detail = ("%s output %s: %s"):format(label, transform.outputId, measured.diagnostic),
				}
			end
			local artifact =
				Measure.artifact(options.measure, transform.outputId, transform.outputPath, measured.measurement)
			if transform.delivery then
				artifact.semanticId = brief.delivery.semanticId
			end
			if transform.kind == "matte" then
				converted.metadata.outputSha256 = artifact.digest
			end
			local invocation, derivation = derived(converted.tool, artifact, found, converted.fingerprint)
			return {
				status = "returned",
				output = {
					artifacts = { artifact },
					invocations = { invocation },
					derivations = { derivation },
					metadata = converted.metadata,
				},
			}
		end,
		compensate = nil,
	}
end

return {
	create = create,
}
