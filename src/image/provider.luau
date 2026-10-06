--!strict

local Generate = require "../core"
local Measure = require "./measure"

export type Config = {
	tool: string,
	toolVersion: string,
	provider: string,
	model: string,
	capability: string,
	disposition: Generate.CandidateDisposition,
	rightsSource: string,
	parentOrigin: string,
	outputRoot: string,
	sourceRoot: string,
	editBaseRoots: { string },
	operationRoot: string,
	operationLeaf: string,
	promptSuffix: string,
	environment: { [string]: string },
	measure: Measure.Config,
	instruction: (request: Request, paths: Paths) -> string,
	command: (request: Request, paths: Paths, inputs: { string }, instruction: string) -> { string },
}

export type Request = {
	operationId: string?,
	group: string,
	slug: string,
	subject: string,
	family: string,
	variant: string,
	version: string,
	sourceDirectory: string,
	prompt: string,
	editOf: string?,
	declaredWidth: number?,
	declaredHeight: number?,
	referenceImages: { string }?,
	rights: {
		source: Generate.RightsFact?,
		license: Generate.RightsFact?,
		owner: Generate.RightsFact?,
		consent: Generate.RightsFact?,
		notes: { string }?,
	}?,
}

export type Paths = {
	directory: string,
	imagePath: string,
	imageFileName: string,
	promptPath: string,
	candidateId: string,
	editOf: string,
}

export type RunResult = {
	stdout: string,
	stderr: string,
	exitcode: number,
}

export type Deps = {
	exists: (string) -> boolean,
	read: (string) -> string,
	write: (string, string) -> (),
	createDirectory: (string) -> (),
	run: ({ string }) -> RunResult,
}

local function isSlug(value: string): boolean
	return string.match(value, "^[a-z][a-z0-9%-]*$") ~= nil
end

local function isSnake(value: string): boolean
	return string.match(value, "^[a-z][a-z0-9_]*$") ~= nil
end

local function snake(value: string): string
	return (string.gsub(value, "%-", "_"))
end

local function requireField(value: unknown, name: string, predicate: (string) -> boolean, shape: string): string
	if type(value) ~= "string" or value == "" then
		error(("image provider: %s is required"):format(name), 3)
	end
	if not predicate(value) then
		error(("image provider: %s %q is not %s"):format(name, value, shape), 3)
	end
	return value
end

local function withinRoot(path: string, root: string): boolean
	if string.find(path, "..", 1, true) ~= nil then
		return false
	end
	if string.sub(path, 1, 1) == "/" then
		return false
	end
	return string.sub(path, 1, #root + 1) == root .. "/"
end

local function withinEitherRoot(path: string, roots: { string }): boolean
	for _, root in roots do
		if withinRoot(path, root) then
			return true
		end
	end
	return false
end

local function paths(config: Config, request: Request): Paths
	local group = requireField(request.group, "group", isSlug, "lower kebab-case")
	local slug = requireField(request.slug, "slug", isSlug, "lower kebab-case")
	local variant = requireField(request.variant, "variant", isSnake, "lower snake_case")
	local version = requireField(request.version, "version", isSlug, "lower kebab-case")
	local sourceDirectory = requireField(request.sourceDirectory, "sourceDirectory", function(value: string): boolean
		return withinRoot(value, config.sourceRoot)
	end, "a directory under " .. config.sourceRoot)
	local directory = config.outputRoot .. "/" .. group
	if request.operationId ~= nil then
		local operationId = requireField(request.operationId, "operationId", function(value: string): boolean
			return string.match(value, "^[0-9A-Za-z][0-9A-Za-z._-]*$") ~= nil
		end, "one safe operation id")
		directory = config.operationRoot .. "/" .. operationId .. "/" .. config.operationLeaf
	end
	local imagePath = directory .. "/" .. slug .. ".png"
	local editOf = ""
	if request.editOf ~= nil then
		editOf = requireField(request.editOf, "editOf", function(value: string): boolean
			return withinEitherRoot(value, config.editBaseRoots) and string.sub(value, -4) == ".png"
		end, "a PNG under " .. table.concat(config.editBaseRoots, " or "))
		if editOf == imagePath then
			error("image provider: editOf names the output itself, which would overwrite the base", 3)
		end
	end
	return {
		directory = directory,
		imagePath = imagePath,
		imageFileName = slug .. ".png",
		promptPath = if request.operationId == nil
			then sourceDirectory .. "/" .. slug .. config.promptSuffix
			else directory .. "/" .. slug .. config.promptSuffix,
		candidateId = table.concat({ group, snake(slug), variant, version }, "."),
		editOf = editOf,
	}
end

local function references(config: Config, request: Request, resolved: Paths): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(path: string)
		if path == resolved.imagePath then
			error("image provider: a reference image names the output itself", 3)
		end
		if not seen[path] then
			seen[path] = true
			table.insert(out, path)
		end
	end
	if resolved.editOf ~= "" then
		add(resolved.editOf)
	end
	if request.referenceImages ~= nil then
		for index, path in request.referenceImages do
			add(requireField(path, ("referenceImages[%d]"):format(index), function(value: string): boolean
				return withinEitherRoot(value, config.editBaseRoots) and string.sub(value, -4) == ".png"
			end, "a PNG under " .. table.concat(config.editBaseRoots, " or ")))
		end
	end
	return out
end

local function invocation(config: Config, command: { string }): Generate.Invocation
	return {
		tool = config.tool,
		toolVersion = config.toolVersion,
		provider = config.provider,
		model = config.model,
		seed = nil,
		parametersFingerprint = Generate.fingerprint(command),
		deterministic = false,
	}
end

local function replyPath(stdout: string): string
	local selected = ""
	for line in string.gmatch(stdout, "[^\r\n]+") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") or ""
		if trimmed ~= "" then
			selected = trimmed
		end
	end
	return selected
end

local function normalizedReply(reply: string, resolved: Paths): string
	if reply == resolved.imageFileName or reply == "./" .. resolved.imageFileName then
		return resolved.imagePath
	end
	if reply == resolved.imagePath or reply == "./" .. resolved.imagePath then
		return resolved.imagePath
	end
	if string.sub(reply, -#resolved.imagePath) == resolved.imagePath then
		return resolved.imagePath
	end
	return reply
end

local function rejected(detail: string): Generate.StageOutcome
	return { status = "rejected", detail = detail }
end

local function runStage(config: Config, deps: Deps, request: Request, attempt: number): Generate.StageOutcome
	local resolved = paths(config, request)
	if not withinRoot(resolved.imagePath, config.outputRoot) then
		return rejected("the image path escapes " .. config.outputRoot)
	end
	if not withinRoot(resolved.promptPath, config.sourceRoot) then
		return rejected("the prompt path escapes " .. config.sourceRoot)
	end
	if deps.exists(resolved.imagePath) then
		return rejected "the reference already exists and is never overwritten in place"
	end
	local inputs = references(config, request, resolved)
	for _, input in inputs do
		if not deps.exists(input) then
			return rejected("the reference image " .. input .. " does not exist")
		end
	end

	if not deps.exists(request.sourceDirectory) then
		deps.createDirectory(request.sourceDirectory)
	end
	local instruction = config.instruction(request, resolved)
	deps.write(resolved.promptPath, instruction .. "\n")
	if not deps.exists(resolved.directory) then
		deps.createDirectory(resolved.directory)
	end

	local command = config.command(request, resolved, inputs, instruction)
	local result = deps.run(command)
	if result.exitcode ~= 0 then
		return rejected(("the reference command exited %d"):format(result.exitcode))
	end
	local reply = normalizedReply(replyPath(result.stdout), resolved)
	if reply ~= resolved.imagePath then
		return rejected("the reply named " .. reply .. " rather than " .. resolved.imagePath)
	end
	if not deps.exists(resolved.imagePath) then
		return rejected "the reply named a path that does not exist"
	end

	local measured = Measure.measure(config.measure, deps.read(resolved.imagePath))
	if not measured.ok then
		return rejected(measured.diagnostic)
	end
	local measurement = measured.measurement :: Measure.Measurement

	local candidate = Measure.artifact(config.measure, resolved.candidateId, resolved.imagePath, measurement)
	local parents: { Generate.ParentRef } = {}
	local referenceDigests: { string } = {}
	if #inputs > 0 then
		for _, input in inputs do
			local baseDigest = config.measure.digest(deps.read(input))
			table.insert(parents, {
				artifactId = input,
				artifactDigest = baseDigest,
				jobId = config.parentOrigin .. input,
			})
			table.insert(referenceDigests, baseDigest)
		end
	end
	local derivation: Generate.DerivationDraft = {
		artifactId = candidate.id,
		artifactDigest = candidate.digest,
		origin = if #inputs > 0 then "derived" else "original",
		parents = parents,
		inputDigests = { config.measure.digest(deps.read(resolved.promptPath)) },
		referenceDigests = referenceDigests,
		invocation = invocation(config, command),
		environment = config.environment,
		attempt = attempt,
		disposition = config.disposition,
		rights = request.rights or { source = { state = "known", value = config.rightsSource } },
	}
	local metadata: { [string]: unknown } = {
		promptPath = resolved.promptPath,
		imagePath = resolved.imagePath,
		editOf = resolved.editOf,
		referenceImages = table.concat(inputs, ","),
	}
	return {
		status = "returned",
		output = {
			artifacts = { candidate },
			invocations = { invocation(config, command) },
			derivations = { derivation },
			metadata = metadata,
		},
	}
end

return {
	withinRoot = withinRoot,
	withinEitherRoot = withinEitherRoot,
	paths = paths,
	references = references,
	invocation = invocation,
	replyPath = replyPath,
	normalizedReply = normalizedReply,
	runStage = runStage,
}
