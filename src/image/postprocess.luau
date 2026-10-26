--!strict

local Codec = require "./codec"
local Generate = require "../core"
local Measure = require "./measure"

export type Config = {
	adapter: string,
	capability: string,
	interpreter: string,
	digest: Codec.Digest,
	measure: Measure.Config,
}

export type Kind = "composite" | "despeckle" | "region-pass"

export type Input = {
	role: string,
	path: string,
}

export type Transform = {
	id: string,
	kind: Kind,
	scriptPath: string,
	scriptDigest: string,
	inputs: { Input },
	outputPath: string,
	parameters: { [string]: string },
	attempt: number,
	rights: {
		source: Generate.RightsFact?,
		license: Generate.RightsFact?,
		owner: Generate.RightsFact?,
		consent: Generate.RightsFact?,
		notes: { string }?,
	}?,
}

export type RunResult = {
	stdout: string,
	stderr: string,
	exitcode: number,
}

export type Deps = {
	exists: (string) -> boolean,
	read: (string) -> string,
	run: ({ string }) -> RunResult,
}

local function rejected(detail: string): Generate.StageOutcome
	return { status = "rejected", detail = detail }
end

local function faulted(detail: string): Generate.StageOutcome
	return { status = "faulted", detail = detail }
end

local function argv(config: Config, transform: Transform): { string }
	local command: { string } = { config.interpreter, transform.scriptPath }
	local keys: { string } = {}
	for key in transform.parameters do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		table.insert(command, ("--%s=%s"):format(key, transform.parameters[key]))
	end
	return command
end

local function invocation(config: Config, transform: Transform): Generate.Invocation
	return {
		tool = transform.scriptPath,
		toolVersion = transform.scriptDigest,
		provider = nil,
		model = nil,
		seed = nil,
		parametersFingerprint = Generate.fingerprint(argv(config, transform)),
		deterministic = true,
	}
end

local function runStage(
	config: Config,
	deps: Deps,
	transform: Transform,
	artifacts: { Generate.Artifact }
): Generate.StageOutcome
	if #transform.inputs == 0 then
		return rejected(("transform %s declares no input frame"):format(transform.id))
	end
	if not deps.exists(transform.scriptPath) then
		return rejected(
			("transform %s names script %s, which does not exist"):format(transform.id, transform.scriptPath)
		)
	end
	local scriptDigest = config.digest(deps.read(transform.scriptPath))
	if scriptDigest ~= transform.scriptDigest then
		return rejected(
			("transform %s pins script digest %s but %s hashes to %s"):format(
				transform.id,
				transform.scriptDigest,
				transform.scriptPath,
				scriptDigest
			)
		)
	end
	if deps.exists(transform.outputPath) then
		return rejected(
			("transform %s would overwrite %s, and no frame is ever overwritten"):format(
				transform.id,
				transform.outputPath
			)
		)
	end

	local before: { [string]: string } = {}
	local artifactByPath: { [string]: Generate.Artifact } = {}
	for _, artifact in artifacts do
		if artifact.locator ~= nil then
			artifactByPath[artifact.locator :: string] = artifact
		end
	end
	for _, input in transform.inputs do
		if not deps.exists(input.path) then
			return rejected(
				("transform %s names input %s (%s), which does not exist"):format(transform.id, input.role, input.path)
			)
		end
		if artifactByPath[input.path] == nil then
			return rejected(
				("transform %s input %s is not carried by this Generate run"):format(transform.id, input.path)
			)
		end
		before[input.path] = config.digest(deps.read(input.path))
	end

	local result = deps.run(argv(config, transform))
	if result.exitcode ~= 0 then
		return rejected(("transform %s exited %d"):format(transform.id, result.exitcode))
	end

	for _, input in transform.inputs do
		if config.digest(deps.read(input.path)) ~= before[input.path] then
			return faulted(("transform %s rewrote its read-only input %s"):format(transform.id, input.path))
		end
	end
	if not deps.exists(transform.outputPath) then
		return rejected(("transform %s exited 0 but wrote no %s"):format(transform.id, transform.outputPath))
	end

	local measured = Measure.measure(config.measure, deps.read(transform.outputPath))
	if not measured.ok then
		return rejected(("transform %s: %s"):format(transform.id, measured.diagnostic))
	end
	local measurement = measured.measurement :: Measure.Measurement
	local artifact = Measure.artifact(config.measure, transform.id, transform.outputPath, measurement)

	local parents: { Generate.ParentRef } = {}
	local inputDigests: { string } = {}
	for _, input in transform.inputs do
		table.insert(
			parents,
			{ artifactId = (artifactByPath[input.path] :: Generate.Artifact).id, artifactDigest = before[input.path] }
		)
		table.insert(inputDigests, before[input.path])
	end
	local environment: { [string]: string } = {
		adapter = config.adapter,
		kind = transform.kind,
		interpreter = config.interpreter,
		transformToolExitCode = tostring(result.exitcode),
	}
	local derivation: Generate.DerivationDraft = {
		artifactId = artifact.id,
		artifactDigest = artifact.digest,
		origin = "derived",
		parents = parents,
		inputDigests = inputDigests,
		referenceDigests = { scriptDigest },
		invocation = invocation(config, transform),
		environment = environment,
		attempt = transform.attempt,
		disposition = "active",
		rights = transform.rights,
	}
	local metadata: { [string]: unknown } = { outputPath = transform.outputPath, scriptPath = transform.scriptPath }
	return {
		status = "returned",
		output = {
			artifacts = { artifact },
			invocations = { invocation(config, transform) },
			derivations = { derivation },
			metadata = metadata,
		},
	}
end

return {
	argv = argv,
	invocation = invocation,
	runStage = runStage,
}
