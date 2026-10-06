--!strict

local Generate = require "../core"
local Matte = require "./matte"
local Measure = require "./measure"
local Qa = require "./qa"
local Request = require "./request"

export type Config = { qa: Qa.Config, matteParameters: Matte.Parameters }

export type MatteHashes = { preMatteSha256: string?, postMatteSha256: string? }
export type RegisterHashes = { preRegisterSha256: string?, postRegisterSha256: string? }
export type TransformedSummary = {
	schema: string,
	status: string,
	thresholds: Qa.Thresholds,
	artifacts: { Qa.Assessment },
	refusals: { string },
	pairs: { [string]: Qa.Pair }?,
	preMatte: Qa.Gate?,
	postMatte: Qa.Gate?,
	matte: { applied: boolean, parameters: Matte.Parameters, sha256: { [string]: MatteHashes } }?,
	preRegister: Qa.Gate?,
	postRegister: Qa.Gate?,
	register: { applied: boolean, sha256: { [string]: RegisterHashes } }?,
}

export type Summary = TransformedSummary

local function declarationOf(artifact: Request.Artifact, full: boolean): Qa.Declaration
	if not full then
		return {
			id = artifact.id,
			role = artifact.role,
			tiles = artifact.tiles,
			transparentBackground = artifact.transparentBackground,
			singleSubject = artifact.singleSubject,
		}
	end
	return {
		id = artifact.id,
		role = artifact.role,
		tiles = artifact.tiles,
		transparentBackground = artifact.transparentBackground,
		singleSubject = artifact.singleSubject,
		unlit = artifact.unlit,
		hueBand = artifact.hueBand,
		limitBrightMaxima = artifact.limitBrightMaxima,
		declaredWidth = artifact.declaredWidth,
		declaredHeight = artifact.declaredHeight,
		dark = artifact.dark,
		registerTarget = artifact.registerTarget,
	}
end

local function delivered(artifacts: { Generate.Artifact }): { [string]: string }
	local located: { [string]: string } = {}
	for _, artifact in artifacts do
		if artifact.mediaType == Measure.MEDIA_TYPE and type(artifact.locator) == "string" then
			located[artifact.id] = artifact.locator :: string
		end
	end
	return located
end

local function sourcesByOutput(document: Request.Document, kind: string): { [string]: string }
	local out: { [string]: string } = {}
	for _, binding in document.bindings do
		if type(binding) == "table" and (binding :: { [string]: unknown }).kind == kind then
			local fields = binding :: { [string]: unknown }
			out[fields.outputId :: string] = fields.sourceId :: string
		end
	end
	return out
end

local function summary(
	config: Config,
	deps: Qa.Deps,
	document: Request.Document,
	artifacts: { Generate.Artifact }
): Summary
	local allLocated = delivered(artifacts)
	local located: { [string]: string } = {}
	local declarations: { Qa.Declaration } = {}
	for _, artifact in document.artifacts do
		if allLocated[artifact.id] ~= nil then
			located[artifact.id] = allLocated[artifact.id]
		end
		table.insert(declarations, declarationOf(artifact, true))
	end
	local post = Qa.gate(config.qa, deps, declarations, located)
	local registerSources = sourcesByOutput(document, "register")
	if next(registerSources) == nil and not document.matte then
		return (post :: unknown) :: Summary
	end
	local sourceByOutput = sourcesByOutput(document, "matte")

	local preDeclarations: { Qa.Declaration } = {}
	local preLocated: { [string]: string } = {}
	local matteHashes: { [string]: MatteHashes } = {}
	local registerDeclarations: { Qa.Declaration } = {}
	local registerLocated: { [string]: string } = {}
	local registerHashes: { [string]: RegisterHashes } = {}
	for _, artifact in document.artifacts do
		local sourceId = sourceByOutput[artifact.id]
		if sourceId ~= nil then
			local declaration = declarationOf(artifact, false)
			declaration.id = sourceId
			table.insert(preDeclarations, declaration)
		end
		local registerSource = registerSources[artifact.id]
		if registerSource ~= nil then
			local declaration = declarationOf(artifact, true)
			declaration.id = registerSource
			table.insert(registerDeclarations, declaration)
		end
	end
	for _, artifact in artifacts do
		if sourceByOutput[artifact.id] ~= nil then
			matteHashes[artifact.id] = matteHashes[artifact.id] or {}
			matteHashes[artifact.id].postMatteSha256 = artifact.digest
		end
		if registerSources[artifact.id] ~= nil then
			registerHashes[artifact.id] = registerHashes[artifact.id] or {}
			registerHashes[artifact.id].postRegisterSha256 = artifact.digest
		else
			for outputId, sourceId in sourceByOutput do
				if sourceId == artifact.id and type(artifact.locator) == "string" then
					preLocated[sourceId] = artifact.locator :: string
					matteHashes[outputId] = matteHashes[outputId] or {}
					matteHashes[outputId].preMatteSha256 = artifact.digest
				end
			end
			for outputId, sourceId in registerSources do
				if sourceId == artifact.id and type(artifact.locator) == "string" then
					registerLocated[sourceId] = artifact.locator :: string
					registerHashes[outputId] = registerHashes[outputId] or {}
					registerHashes[outputId].preRegisterSha256 = artifact.digest
				end
			end
		end
	end
	local registered = next(registerSources) ~= nil
	return {
		schema = post.schema,
		status = post.status,
		thresholds = post.thresholds,
		artifacts = post.artifacts,
		refusals = post.refusals,
		preMatte = if document.matte then Qa.gate(config.qa, deps, preDeclarations, preLocated) else nil,
		postMatte = if document.matte then post else nil,
		matte = if document.matte
			then { applied = true, parameters = config.matteParameters, sha256 = matteHashes }
			else nil,
		preRegister = if registered then Qa.gate(config.qa, deps, registerDeclarations, registerLocated) else nil,
		postRegister = if registered then post else nil,
		register = if registered then { applied = true, sha256 = registerHashes } else nil,
	}
end

return {
	delivered = delivered,
	sourcesByOutput = sourcesByOutput,
	summary = summary,
}
