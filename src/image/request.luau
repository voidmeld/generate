--!strict

local Generate = require "../core"
local Register = require "./register"
local Host = require "./host"
local Provider = require "./provider"
local Qa = require "./qa"
local Review = require "./review"
local Postprocess = require "./postprocess"

export type Config = { schema: string, indent: string, serialize: (value: unknown) -> string }

export type Artifact = {
	id: string,
	slug: string,
	role: string,
	tiles: boolean,
	transparentBackground: boolean,
	singleSubject: boolean,
	unlit: boolean?,
	pairedGroup: string?,
	hueBand: Qa.HueBand?,
	limitBrightMaxima: boolean?,
	declaredWidth: number?,
	declaredHeight: number?,
	dark: boolean?,
	registerTarget: Register.DeclarationTarget?,
}

export type Document = {
	schema: string,
	briefId: string,
	artifacts: { Artifact },
	matte: boolean,
	bindings: { [string]: unknown },
}

export type Refusal = { ok: false, reason: string, detail: string }
export type Decoded = { ok: true, document: Document }
export type Bound = { ok: true, bindings: { [string]: Host.Binding } }

local function refuse(reason: string, detail: string): Refusal
	return { ok = false, reason = reason, detail = detail }
end

local function object(value: unknown): { [string]: unknown }?
	if type(value) ~= "table" then
		return nil
	end
	return value :: { [string]: unknown }
end

local function fields(value: { [string]: unknown }, names: { string }, kind: string, optional: boolean): boolean
	for _, name in names do
		if (value[name] ~= nil or not optional) and type(value[name]) ~= kind then
			return false
		end
	end
	return true
end

local function stringList(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	for key, item in value :: { [unknown]: unknown } do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(item) ~= "string" then
			return false
		end
	end
	return true
end

local function registerTarget(value: unknown): boolean
	local target = object(value)
	if target == nil or not fields(target, { "hue", "saturationCeiling" }, "number", false) then
		return false
	end
	local values = object(target.value)
	if values == nil then
		return false
	end
	for _, name in { "p5", "p50", "p95" } do
		local bounds = object(values[name])
		if bounds == nil or not fields(bounds, { "min", "max", "target" }, "number", false) then
			return false
		end
	end
	return true
end

local function hueBand(value: unknown): boolean
	local band = object(value)
	if band == nil or not fields(band, { "fromDegrees", "toDegrees", "maxFraction" }, "number", false) then
		return false
	end
	local from, to, fraction = band.fromDegrees :: number, band.toDegrees :: number, band.maxFraction :: number
	return from >= 0 and from < 360 and to >= 0 and to < 360 and fraction >= 0 and fraction <= 1
end

local function providerRequest(value: unknown): boolean
	local request = object(value)
	if
		request == nil
		or not fields(
			request,
			{ "group", "slug", "subject", "family", "variant", "version", "sourceDirectory", "prompt" },
			"string",
			false
		)
		or not fields(request, { "operationId", "editOf" }, "string", true)
		or not fields(request, { "declaredWidth", "declaredHeight" }, "number", true)
		or (request.referenceImages ~= nil and not stringList(request.referenceImages))
	then
		return false
	end
	if request.rights ~= nil then
		local rights = object(request.rights)
		if rights == nil or (rights.notes ~= nil and not stringList(rights.notes)) then
			return false
		end
		for _, name in { "source", "license", "owner", "consent" } do
			if rights[name] ~= nil then
				local fact = object(rights[name])
				if
					fact == nil
					or (fact.state ~= "known" and fact.state ~= "unknown")
					or not fields(fact, { "value" }, "string", true)
				then
					return false
				end
			end
		end
	end
	return true
end

local function reviewRequest(value: unknown): boolean
	local request = object(value)
	if
		request == nil
		or not fields(request, { "packetId", "candidateId", "producer", "candidateArtifactId" }, "string", false)
		or type(request.revision) ~= "number"
		or not stringList(request.requestedViews)
	then
		return false
	end
	local rubric = object(request.rubric)
	local environment = object(request.captureEnvironment)
	if
		rubric == nil
		or not fields(rubric, { "id", "fingerprint" }, "string", false)
		or not fields(rubric, { "version" }, "string", true)
		or environment == nil
		or type(request.evidence) ~= "table"
	then
		return false
	end
	for key, item in request.captureEnvironment :: { [unknown]: unknown } do
		if type(key) ~= "string" or type(item) ~= "string" then
			return false
		end
	end
	for key, item in request.evidence :: { [unknown]: unknown } do
		local evidence = object(item)
		if
			type(key) ~= "number"
			or key < 1
			or key % 1 ~= 0
			or evidence == nil
			or not fields(evidence, { "artifactId", "view", "role" }, "string", false)
		then
			return false
		end
	end
	return true
end

local function artifactsRefusal(value: unknown, path: string): Refusal?
	if type(value) ~= "table" or #(value :: { unknown }) == 0 then
		return refuse("artifacts", path .. " declares no artifacts; every image run delivers at least one")
	end
	local seen: { [unknown]: boolean } = {}
	for index, candidate in value :: { unknown } do
		local entry = candidate :: { [string]: unknown }
		if type(entry) ~= "table" then
			return refuse("artifacts", ("artifact %d is not an object"):format(index))
		end
		for _, field in { "id", "slug", "role" } do
			if type(entry[field]) ~= "string" or entry[field] == "" then
				return refuse("artifacts", ("artifact %d carries no %s"):format(index, field))
			end
		end
		for _, field in { "tiles", "transparentBackground", "singleSubject" } do
			if type(entry[field]) ~= "boolean" then
				return refuse("artifacts", ("artifact %s carries no boolean %s"):format(tostring(entry.id), field))
			end
		end
		if entry.unlit ~= nil and type(entry.unlit) ~= "boolean" then
			return refuse("artifacts", ("artifact %s carries a non-boolean unlit"):format(tostring(entry.id)))
		end
		for _, field in { "limitBrightMaxima", "dark" } do
			if entry[field] ~= nil and type(entry[field]) ~= "boolean" then
				return refuse("artifacts", ("artifact %s carries a non-boolean %s"):format(tostring(entry.id), field))
			end
		end
		if entry.hueBand ~= nil and not hueBand(entry.hueBand) then
			return refuse("artifacts", ("artifact %s carries an invalid hueBand"):format(tostring(entry.id)))
		end
		if entry.declaredWidth ~= nil or entry.declaredHeight ~= nil then
			if type(entry.declaredWidth) ~= "number" or type(entry.declaredHeight) ~= "number" then
				return refuse(
					"artifacts",
					("artifact %s carries incomplete declared dimensions"):format(tostring(entry.id))
				)
			end
		end
		if entry.registerTarget ~= nil and not registerTarget(entry.registerTarget) then
			return refuse("artifacts", ("artifact %s carries an invalid register target"):format(tostring(entry.id)))
		end
		if entry.pairedGroup ~= nil and (type(entry.pairedGroup) ~= "string" or entry.pairedGroup == "") then
			return refuse("artifacts", ("artifact %s carries an invalid pairedGroup"):format(tostring(entry.id)))
		end
		if seen[entry.id] then
			return refuse("artifacts", ("artifact id %s is declared twice"):format(entry.id :: string))
		end
		seen[entry.id] = true
	end
	return nil
end

local function fromBrief(config: Config, moduleValue: unknown, path: string): Decoded | Refusal
	if type(moduleValue) ~= "table" then
		return refuse("brief", path .. " returned no module table")
	end
	local module = moduleValue :: { [string]: unknown }
	local declaration = module.imageRun
	if type(declaration) ~= "table" or type((declaration :: { [string]: unknown }).bindings) ~= "table" then
		return refuse("image-run", path .. " declares no imageRun bindings")
	end
	local declared = declaration :: { [string]: unknown }
	local count = 0
	for _ in declared.bindings :: { [string]: unknown } do
		count += 1
	end
	if count == 0 then
		return refuse("image-run", path .. " declares an empty imageRun binding set")
	end
	local brief = module.brief
	if
		type(brief) ~= "table"
		or type((brief :: { [string]: unknown }).id) ~= "string"
		or (brief :: { [string]: unknown }).id == ""
	then
		return refuse("brief", path .. " returned no Generate brief to bind the request to")
	end
	local artifacts = declared.artifacts
	local invalid = artifactsRefusal(artifacts, path)
	if invalid ~= nil then
		return invalid
	end
	return {
		ok = true,
		document = {
			schema = config.schema,
			briefId = (brief :: { [string]: unknown }).id :: string,
			artifacts = artifacts :: { Artifact },
			matte = declared.matte == true,
			bindings = declared.bindings :: { [string]: unknown },
		},
	}
end

local function decode(config: Config, documentValue: unknown, path: string): Decoded | Refusal
	if type(documentValue) ~= "table" then
		return refuse("request", path .. " is not a JSON object")
	end
	local value = documentValue :: { [string]: unknown }
	if value.schema ~= config.schema then
		return refuse(
			"request",
			("%s carries schema %q rather than %q"):format(path, tostring(value.schema), config.schema)
		)
	end
	if type(value.briefId) ~= "string" or value.briefId == "" then
		return refuse("request", path .. " names no brief")
	end
	if type(value.bindings) ~= "table" then
		return refuse("request", path .. " carries no bindings object")
	end
	local invalid = artifactsRefusal(value.artifacts, path)
	if invalid ~= nil then
		return invalid
	end
	if type(value.matte) ~= "boolean" then
		return refuse("request", path .. " carries no boolean matte declaration")
	end
	return { ok = true, document = documentValue :: Document }
end

local function providerBinding(stage: string, entry: { [string]: unknown }): Host.Binding | Refusal
	if not providerRequest(entry.request) then
		return refuse("bindings", ("provider binding %s carries an invalid request"):format(stage))
	end
	local attempt = entry.attempt
	if type(attempt) ~= "number" or attempt < 1 or attempt % 1 ~= 0 then
		return refuse("bindings", ("provider binding %s carries no whole attempt ordinal"):format(stage))
	end
	return {
		kind = "provider",
		request = entry.request :: Provider.Request,
		attempt = attempt,
		delivery = entry.delivery == true,
	} :: Host.Binding
end

local function reviewBinding(stage: string, entry: { [string]: unknown }): Host.Binding | Refusal
	if not reviewRequest(entry.request) then
		return refuse("bindings", ("review binding %s carries an invalid request"):format(stage))
	end
	return { kind = "review", request = entry.request :: Review.Request } :: Host.Binding
end

local function matteBinding(stage: string, entry: { [string]: unknown }): Host.Binding | Refusal
	if stage ~= "matte" then
		return refuse("bindings", ("matte binding %s must use the matte stage"):format(stage))
	end
	for _, field in { "sourceId", "outputId", "outputPath" } do
		if type(entry[field]) ~= "string" or entry[field] == "" then
			return refuse("bindings", ("matte binding %s carries no %s"):format(stage, field))
		end
	end
	return {
		kind = "matte",
		sourceId = entry.sourceId :: string,
		outputId = entry.outputId :: string,
		outputPath = entry.outputPath :: string,
		delivery = entry.delivery == true,
	} :: Host.Binding
end

local function deliverBinding(stage: string, entry: { [string]: unknown }): Host.Binding | Refusal
	if stage ~= "deliver" then
		return refuse("bindings", ("deliver binding %s must use the deliver stage"):format(stage))
	end
	for _, field in { "sourceId", "outputId", "outputPath" } do
		if type(entry[field]) ~= "string" or entry[field] == "" then
			return refuse("bindings", ("deliver binding %s carries no %s"):format(stage, field))
		end
	end
	for _, field in { "declaredWidth", "declaredHeight" } do
		local value = entry[field]
		if type(value) ~= "number" or value < 1 or value % 1 ~= 0 then
			return refuse("bindings", ("deliver binding %s carries no whole positive %s"):format(stage, field))
		end
	end
	return {
		kind = "deliver",
		sourceId = entry.sourceId :: string,
		outputId = entry.outputId :: string,
		outputPath = entry.outputPath :: string,
		declaredWidth = entry.declaredWidth :: number,
		declaredHeight = entry.declaredHeight :: number,
		delivery = entry.delivery == true,
	} :: Host.Binding
end

local function registerBinding(stage: string, entry: { [string]: unknown }): Host.Binding | Refusal
	if stage ~= "register" then
		return refuse("bindings", ("register binding %s must use the register stage"):format(stage))
	end
	for _, field in { "sourceId", "outputId", "outputPath" } do
		if type(entry[field]) ~= "string" or entry[field] == "" then
			return refuse("bindings", ("register binding %s carries no %s"):format(stage, field))
		end
	end
	if not registerTarget(entry.target) then
		return refuse("bindings", ("register binding %s carries an invalid target"):format(stage))
	end
	return {
		kind = "register",
		sourceId = entry.sourceId :: string,
		outputId = entry.outputId :: string,
		outputPath = entry.outputPath :: string,
		target = entry.target :: Register.DeclarationTarget,
		delivery = entry.delivery == true,
	} :: Host.Binding
end

local function postprocessBinding(stage: string, entry: { [string]: unknown }): Host.Binding | Refusal
	local transformValue = entry.transform
	if type(transformValue) ~= "table" then
		return refuse("bindings", ("postprocess binding %s carries no transform"):format(stage))
	end
	local transform = transformValue :: { [string]: unknown }
	for _, field in { "id", "scriptPath", "scriptDigest", "outputPath" } do
		if type(transform[field]) ~= "string" or transform[field] == "" then
			return refuse("bindings", ("postprocess binding %s carries no %s"):format(stage, field))
		end
	end
	if transform.kind ~= "composite" and transform.kind ~= "despeckle" and transform.kind ~= "region-pass" then
		return refuse("bindings", ("postprocess binding %s carries an unsupported transform kind"):format(stage))
	end
	if type(transform.attempt) ~= "number" or transform.attempt < 1 or transform.attempt % 1 ~= 0 then
		return refuse("bindings", ("postprocess binding %s carries no whole attempt ordinal"):format(stage))
	end
	if type(transform.inputs) ~= "table" or #(transform.inputs :: { unknown }) == 0 then
		return refuse("bindings", ("postprocess binding %s carries no input frames"):format(stage))
	end
	for _, input in transform.inputs :: { { [string]: unknown } } do
		if
			type(input) ~= "table"
			or type(input.role) ~= "string"
			or input.role == ""
			or type(input.path) ~= "string"
			or input.path == ""
		then
			return refuse("bindings", ("postprocess binding %s carries an invalid input frame"):format(stage))
		end
	end
	if type(transform.parameters) ~= "table" then
		return refuse("bindings", ("postprocess binding %s carries no parameters"):format(stage))
	end
	for name, value in transform.parameters :: { [unknown]: unknown } do
		if type(name) ~= "string" or name == "" or type(value) ~= "string" then
			return refuse("bindings", ("postprocess binding %s carries an invalid parameter"):format(stage))
		end
	end
	return {
		kind = "postprocess",
		transform = transformValue :: Postprocess.Transform,
		delivery = entry.delivery == true,
	} :: Host.Binding
end

local function bindings(document: Document, plan: Generate.Plan): Bound | Refusal
	if document.briefId ~= plan.briefId then
		return refuse(
			"bindings",
			("the request was written for brief %s and the plan belongs to %s"):format(document.briefId, plan.briefId)
		)
	end
	local declared: { [string]: boolean } = {}
	for _, stage in plan.stages do
		declared[stage.id] = not stage.mutation
	end
	local out: { [string]: Host.Binding } = {}
	for stage, bindingValue in document.bindings do
		if declared[stage] == nil then
			return refuse("bindings", ("binding %s names no stage in plan %s"):format(stage, plan.briefId))
		end
		if not declared[stage] then
			return refuse("bindings", ("binding %s names a mutating stage, which this lane never runs"):format(stage))
		end
		if type(bindingValue) ~= "table" then
			return refuse("bindings", ("binding %s is not an object"):format(stage))
		end
		local bound: Host.Binding | Refusal
		local entry = bindingValue :: { [string]: unknown }
		if entry.kind == "provider" then
			bound = providerBinding(stage, entry)
		elseif entry.kind == "review" then
			bound = reviewBinding(stage, entry)
		elseif entry.kind == "matte" and document.matte then
			bound = matteBinding(stage, entry)
		elseif entry.kind == "register" then
			bound = registerBinding(stage, entry)
		elseif entry.kind == "deliver" then
			bound = deliverBinding(stage, entry)
		elseif entry.kind == "postprocess" then
			bound = postprocessBinding(stage, entry)
		else
			return refuse("bindings", ("binding %s carries unsupported kind %q"):format(stage, tostring(entry.kind)))
		end
		if (bound :: Host.Binding & { ok: boolean? }).ok == false then
			return bound :: Refusal
		end
		out[stage] = bound :: Host.Binding
	end
	for stage, nonMutating in declared do
		if nonMutating and out[stage] == nil then
			return refuse("bindings", ("plan stage %s has no binding in the request"):format(stage))
		end
	end
	return { ok = true, bindings = out }
end

local function encodeValue(config: Config, input: unknown, indent: string): string
	if type(input) ~= "table" then
		return config.serialize(input)
	end
	local value = input :: { [unknown]: unknown }
	local nested = indent .. config.indent
	if #value > 0 then
		local items: { string } = {}
		for _, entry in value do
			table.insert(items, nested .. encodeValue(config, entry, nested))
		end
		return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
	end
	local keys: { string } = {}
	for key in value do
		table.insert(keys, tostring(key))
	end
	if #keys == 0 then
		return "{}"
	end
	table.sort(keys)
	local items: { string } = {}
	for _, key in keys do
		table.insert(items, nested .. config.serialize(key) .. ": " .. encodeValue(config, value[key], nested))
	end
	return "{\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "}"
end

local function encode(config: Config, document: Document): string
	return encodeValue(config, document, "") .. "\n"
end

return {
	refuse = refuse,
	artifactsRefusal = artifactsRefusal,
	fromBrief = fromBrief,
	decode = decode,
	bindings = bindings,
	encodeValue = encodeValue,
	encode = encode,
}
