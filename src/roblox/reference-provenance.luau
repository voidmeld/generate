--!strict

local AssetReadback = require "./asset-readback"

export type Owner = AssetReadback.Owner

export type Readback = {
	assetId: string,
	creatorType: string,
	creatorId: string,
	moderationState: string,
	closed: boolean,
}

export type Source = {
	path: string,
	tool: string,
	model: string,
	prompt: string?,
	date: string,
	sha256: string,
}

export type ReferenceDraft = {
	key: string,
	committedPath: string,
	promptPath: string?,
	reviewerVerdictIds: { string },
	reviewerVerdictReceipt: string,
	reviewerVerdictAnchor: string,
	disposition: string,
	imageAssetId: number,
	sourceAssetId: number,
	readbackReceipt: string,
	readback: Readback,
	attributes: { [string]: string }?,
}

export type Codecs = {
	decode: (text: string) -> unknown,
	encode: (value: unknown) -> string,
	digest: (bytes: string) -> string,
}

export type Files = {
	read: (path: string) -> string,
	write: (path: string, bytes: string) -> (),
	exists: (path: string) -> boolean,
	list: ((root: string) -> { string })?,
}

export type Config = {
	owner: Owner,
	sections: { string },
	referenceSection: string,
	manifestPath: string,
	renderedPath: string,
	lineagePath: string | { string },
	referenceRoot: string,
	terminalDisposition: string?,
	activeState: string?,
	render: (manifest: unknown) -> string,
}

export type Outcome = {
	contract: string,
	manifestPath: string,
	section: string,
	key: string,
	row: { [string]: RowValue }?,
	renderedPath: string,
	rowCount: number,
	diagnostic: string,
	boundary: { string },
}

export type RowValue = string | number | boolean | { string } | { number } | nil

local CONTRACT = "generate.roblox.reference-provenance.v1"
local SECTION_INDENT = "  "
local KEY_INDENT = "    "
local FIELD_INDENT = "      "
local DEFAULT_ACTIVE_STATE = "Active"
local DEFAULT_TERMINAL_DISPOSITION = "accepted"
local HIDDEN_PATH_RULE = "a receipt a row binds must live on a committed path, because a path under a dotted tree "
	.. "is ignored by the version control system and is absent from every fresh checkout"

local BOUNDARY: { string } = {
	"a row is spliced into the existing text so every other byte of the manifest survives unchanged",
	"a row is never written for an id whose readback is not owned by the declared creator and approved",
	"an existing key is never overwritten and the splice holds instead",
	"the rendered table is rendered by the consumer-supplied renderer and never by a second renderer",
	"a renderer that no longer reproduces the committed table holds the whole act before any byte is written",
	"a source named by no lineage file, or by more than one, is never recorded",
	"a source whose committed bytes do not match its lineage row's sha256 is never recorded",
	"this module reads no credential, makes no request, and publishes nothing",
}

local function sectionKnown(config: Config, section: string): boolean
	for _, known in config.sections do
		if known == section then
			return true
		end
	end
	return false
end

local function numberLiteral(value: number): string
	if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
		return string.format("%d", value)
	end
	return string.format("%.4f", value)
end

local function scalar(codecs: Codecs, value: unknown): string
	local kind = type(value)
	if kind == "string" then
		return codecs.encode(value)
	end
	if kind == "number" then
		return numberLiteral(value :: number)
	end
	if kind == "boolean" then
		return tostring(value)
	end
	if kind == "table" then
		local parts: { string } = {}
		local strings = false
		for _, component in value :: { unknown } do
			if type(component) == "string" then
				strings = true
			end
		end
		for _, component in value :: { unknown } do
			if strings then
				if type(component) ~= "string" or component == "" then
					error("Generate reference provenance: a row's string array holds only non-empty strings", 3)
				end
				table.insert(parts, codecs.encode(component))
			else
				if type(component) ~= "number" then
					error("Generate reference provenance: a row's array holds only numbers", 3)
				end
				table.insert(parts, numberLiteral(component))
			end
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end
	error("Generate reference provenance: a row field is a string, number, boolean, or array", 3)
end

local function renderRow(codecs: Codecs, row: { [string]: RowValue }): string
	local keys: { string } = {}
	for key in row do
		table.insert(keys, key)
	end
	table.sort(keys)
	local lines: { string } = {}
	for index, key in keys do
		local separator = if index == #keys then "" else ","
		table.insert(lines, FIELD_INDENT .. codecs.encode(key) .. ": " .. scalar(codecs, row[key]) .. separator)
	end
	return table.concat(lines, "\n")
end

local function renderEntry(codecs: Codecs, key: string, row: { [string]: RowValue }): string
	return table.concat({
		KEY_INDENT .. codecs.encode(key) .. ": {",
		renderRow(codecs, row),
		KEY_INDENT .. "}",
	}, "\n")
end

local function splice(
	config: Config,
	codecs: Codecs,
	text: string,
	section: string,
	key: string,
	row: { [string]: RowValue }
): (string, string?)
	if not sectionKnown(config, section) then
		return text, ("%q is not a manifest section"):format(section)
	end
	local parsedOk, parsed = pcall(codecs.decode, text)
	if not parsedOk or type(parsed) ~= "table" or type((parsed :: { [string]: unknown })[section]) ~= "table" then
		return text, ("the manifest carries no %s section"):format(section)
	end
	if ((parsed :: { [string]: unknown })[section] :: { [string]: unknown })[key] ~= nil then
		return text, ("%s already carries %q and a row is never overwritten"):format(section, key)
	end
	local opening = "\n" .. SECTION_INDENT .. codecs.encode(section) .. ": {"
	local start = string.find(text, opening, 1, true)
	if start == nil then
		return text, ("the %s section is not laid out in the committed shape"):format(section)
	end
	local after = (start :: number) + #opening
	local entry = renderEntry(codecs, key, row)
	local spliced: string
	if string.sub(text, after, after + 1) == "}," or string.sub(text, after, after) == "}" then
		spliced = string.sub(text, 1, after - 1) .. "\n" .. entry .. "\n" .. SECTION_INDENT .. string.sub(text, after)
	else
		spliced = string.sub(text, 1, after - 1) .. "\n" .. entry .. "," .. string.sub(text, after)
	end
	local ok, reparsed = pcall(codecs.decode, spliced)
	if not ok or type(reparsed) ~= "table" then
		return text, "the spliced manifest is no longer deserializable"
	end
	if (reparsed :: { [string]: { [string]: unknown } })[section][key] == nil then
		return text, "the spliced row did not land in its section"
	end
	return spliced, nil
end

local function readbackProves(config: Config, readback: Readback, assetId: number): string?
	if type(readback) ~= "table" then
		return "a reference row requires a readback"
	end
	if readback.creatorType ~= config.owner.creatorType or readback.creatorId ~= config.owner.creatorId then
		return "the readback does not prove the declared creator"
	end
	if AssetReadback.APPROVED_STATES[readback.moderationState] ~= true then
		return "the readback does not prove an approved moderation state"
	end
	if not readback.closed then
		return "the dependency census is not closed"
	end
	if type(assetId) ~= "number" or assetId <= 0 or assetId ~= math.floor(assetId) then
		return "a reference row requires a durable asset id"
	end
	if readback.assetId ~= string.format("%.0f", assetId) then
		return "the readback is for a different asset id"
	end
	return nil
end

local function inlinePromptFrom(block: string): string?
	local quoted = string.match(block, 'prompt = "([^"]+)"')
	if quoted ~= nil then
		return quoted
	end
	local level = string.match(block, "prompt = %[(=*)%[")
	if level == nil then
		return nil
	end
	local openStart, openEnd = string.find(block, "prompt = %[" .. level .. "%[")
	if openStart == nil then
		return nil
	end
	local closer = "]" .. (level :: string) .. "]"
	local closeStart = string.find(block, closer, (openEnd :: number) + 1, true)
	if closeStart == nil then
		return nil
	end
	return string.sub(block, (openEnd :: number) + 1, (closeStart :: number) - 1)
end

local function sourceFrom(config: Config, lineageText: string, committedPath: string): (Source?, string?)
	for block in string.gmatch(lineageText, 'source_path = ".-sha256 = "[0-9a-f]+"') do
		local path = string.match(block, '^source_path = "([^"]+)"')
		if path == committedPath then
			local tool = string.match(block, 'tool = "([^"]+)"')
			local model = string.match(block, 'model = "([^"]+)"')
			local prompt = inlinePromptFrom(block)
			local date = string.match(block, 'date = "([^"]+)"')
			local digest = string.match(block, 'sha256 = "([0-9a-f]+)"')
			if tool == nil or model == nil or date == nil or digest == nil then
				return nil, ("the lineage row for %s is incomplete"):format(committedPath)
			end
			return {
				path = path :: string,
				tool = tool :: string,
				model = model :: string,
				prompt = prompt,
				date = date :: string,
				sha256 = digest :: string,
			},
				nil
		end
	end
	return nil, ("%s names no lineage row for %s"):format(tostring(config.lineagePath), committedPath)
end

local function lineageCandidates(config: Config, files: Files): ({ string }?, string?)
	local declared = config.lineagePath
	if type(declared) == "table" then
		local list = declared :: { string }
		if #list == 0 then
			return nil, "a reference config's lineagePath list is empty"
		end
		return list, nil
	end
	if type(declared) ~= "string" or declared == "" then
		return nil, "a reference config requires a lineagePath"
	end
	if files.exists(declared) then
		return { declared }, nil
	end
	if files.list == nil then
		return nil, "the declared lineage path is absent: " .. declared
	end
	local names = files.list(declared)
	if type(names) ~= "table" or #names == 0 then
		return nil, "the declared lineage directory carries no committed files: " .. declared
	end
	return names, nil
end

local function resolveSource(config: Config, files: Files, committedPath: string): (Source?, string?, string?)
	local candidates, candidatesDiagnostic = lineageCandidates(config, files)
	if candidates == nil then
		return nil, nil, candidatesDiagnostic
	end
	local matches: { { source: Source, file: string } } = {}
	local searched: { string } = {}
	for _, path in candidates :: { string } do
		table.insert(searched, path)
		if files.exists(path) then
			local source = sourceFrom(config, files.read(path), committedPath)
			if source ~= nil then
				table.insert(matches, { source = source :: Source, file = path })
			end
		end
	end
	if #matches == 0 then
		return nil,
			nil,
			("no lineage file names a row for %s; searched %s"):format(committedPath, table.concat(searched, ", "))
	end
	if #matches > 1 then
		local matchedFiles: { string } = {}
		for _, match in matches do
			table.insert(matchedFiles, match.file)
		end
		return nil,
			nil,
			("more than one lineage file names a row for %s: %s"):format(
				committedPath,
				table.concat(matchedFiles, ", ")
			)
	end
	return matches[1].source, matches[1].file, nil
end

local function hiddenPath(path: string): boolean
	if string.sub(path, 1, 1) == "." then
		return true
	end
	return string.find(path, "/.", 1, true) ~= nil
end

local function referenceRow(
	config: Config,
	draft: ReferenceDraft,
	source: Source,
	lineageFile: string,
	promptDigest: string?
): ({ [string]: RowValue }?, string?)
	local proof = readbackProves(config, draft.readback, draft.imageAssetId)
	if proof ~= nil then
		return nil, proof
	end
	if type(draft.sourceAssetId) ~= "number" or draft.sourceAssetId <= 0 then
		return nil, "a reference row requires the durable asset id it was extracted from"
	end
	if string.sub(draft.committedPath, 1, #config.referenceRoot) ~= config.referenceRoot then
		return nil, "a reference source must stay committed under " .. config.referenceRoot
	end
	if string.sub(draft.committedPath, -4) ~= ".png" then
		return nil, "a reference source must be a committed PNG"
	end
	if type(draft.readbackReceipt) ~= "string" or draft.readbackReceipt == "" then
		return nil, "a reference row requires the recorded readback receipt path"
	end
	for _, receipt in { draft.readbackReceipt, draft.reviewerVerdictReceipt } do
		if type(receipt) == "string" and receipt ~= "" and hiddenPath(receipt) then
			return nil, ("%s is not a committed path: %s"):format(receipt, HIDDEN_PATH_RULE)
		end
	end
	if type(draft.reviewerVerdictIds) ~= "table" or #draft.reviewerVerdictIds ~= 1 then
		return nil, "a reference row requires exactly one independent reviewer verdict id"
	end
	local reviewer = draft.reviewerVerdictIds[1]
	if type(reviewer) ~= "string" or reviewer == "" then
		return nil, "the reviewer verdict id must be a non-empty string"
	end
	if type(draft.reviewerVerdictReceipt) ~= "string" or draft.reviewerVerdictReceipt == "" then
		return nil, "a reference row requires the recorded reviewer verdict receipt"
	end
	if type(draft.reviewerVerdictAnchor) ~= "string" or draft.reviewerVerdictAnchor == "" then
		return nil, "a reference row requires the reviewer verdict anchor"
	end
	if draft.disposition == (config.terminalDisposition or DEFAULT_TERMINAL_DISPOSITION) then
		return nil,
			"a a reference row cannot take the terminal disposition; the consumer sets it after the dependent content is published and linked back"
	end
	if type(draft.disposition) ~= "string" or draft.disposition == "" then
		return nil, "a reference row requires a disposition"
	end
	local row: { [string]: RowValue } = {
		id = draft.key,
		committed_source_path = draft.committedPath,
		source_sha256 = source.sha256,
		generation_tool = source.tool,
		generation_model = source.model,
		generation_date = source.date,
		lineage_path = lineageFile,
		image_asset_id = draft.imageAssetId,
		source_asset_id = draft.sourceAssetId,
		owner = string.lower(config.owner.creatorType),
		owner_id = config.owner.creatorId,
		state = config.activeState or DEFAULT_ACTIVE_STATE,
		creator_transfer_pending = false,
		moderation_state = draft.readback.moderationState,
		image_readback_receipt = draft.readbackReceipt,
		reviewer_verdict_ids = draft.reviewerVerdictIds,
		reviewer_verdict_receipt = draft.reviewerVerdictReceipt,
		reviewer_verdict_anchor = draft.reviewerVerdictAnchor,
		rights_basis = "generated_by_owner",
		disposition = draft.disposition,
	}
	if type(source.prompt) == "string" and source.prompt ~= "" then
		row.prompt = source.prompt
		row.prompt_sha256 = promptDigest
	else
		row.prompt_path = draft.promptPath
		row.prompt_sha256 = promptDigest
	end
	local attributes: { [string]: string } = draft.attributes or {}
	for key, value in attributes do
		if row[key] ~= nil then
			return nil, ("a reference row attribute may not restate %q"):format(key)
		end
		row[key] = value
	end
	return row, nil
end

local function rendererParity(
	config: { render: (manifest: unknown) -> string },
	codecs: { decode: (text: string) -> unknown },
	manifestText: string,
	renderedText: string
): string?
	local ok, parsed = pcall(codecs.decode, manifestText)
	if not ok or type(parsed) ~= "table" then
		return "the manifest is not deserializable"
	end
	if config.render(parsed) == renderedText then
		return nil
	end
	return "the renderer no longer reproduces the committed table, so baking would discard committed content"
end

local function record(config: Config, codecs: Codecs, files: Files, draft: ReferenceDraft): Outcome
	local outcome: Outcome = {
		contract = CONTRACT,
		manifestPath = config.manifestPath,
		section = config.referenceSection,
		key = draft.key,
		row = nil,
		renderedPath = config.renderedPath,
		rowCount = 0,
		diagnostic = "",
		boundary = BOUNDARY,
	}
	for _, required in { config.manifestPath, config.renderedPath, draft.committedPath } do
		if type(required) ~= "string" or required == "" or not files.exists(required) then
			outcome.diagnostic = "a required committed input is absent: " .. tostring(required)
			return outcome
		end
	end
	if not files.exists(draft.reviewerVerdictReceipt) then
		outcome.diagnostic = "the reviewer verdict receipt is absent: " .. tostring(draft.reviewerVerdictReceipt)
		return outcome
	end
	local source, lineageFile, plateDiagnostic = resolveSource(config, files, draft.committedPath)
	if source == nil then
		outcome.diagnostic = plateDiagnostic or "the source lineage row is malformed"
		return outcome
	end
	local committedDigest = codecs.digest(files.read(draft.committedPath))
	if committedDigest ~= (source :: Source).sha256 then
		outcome.diagnostic = "the committed source bytes do not match the lineage row's sha256"
		return outcome
	end
	local usesInlinePrompt = type((source :: Source).prompt) == "string" and (source :: Source).prompt ~= ""
	local promptDigest: string? = nil
	if usesInlinePrompt then
		promptDigest = codecs.digest((source :: Source).prompt :: string)
	else
		if type(draft.promptPath) ~= "string" or draft.promptPath == "" then
			outcome.diagnostic = "a reference row requires either a committed prompt path or an inline lineage prompt"
			return outcome
		end
		if not files.exists(draft.promptPath) then
			outcome.diagnostic = "a required committed input is absent: " .. draft.promptPath
			return outcome
		end
		promptDigest = codecs.digest(files.read(draft.promptPath))
	end
	local row, rowDiagnostic = referenceRow(config, draft, source :: Source, lineageFile :: string, promptDigest)
	if row == nil then
		outcome.diagnostic = rowDiagnostic or "the reference draft is malformed"
		return outcome
	end
	local manifestText = files.read(config.manifestPath)
	local parityDiagnostic = rendererParity(config, codecs, manifestText, files.read(config.renderedPath))
	if parityDiagnostic ~= nil then
		outcome.diagnostic = parityDiagnostic
		return outcome
	end
	local spliced, spliceDiagnostic = splice(config, codecs, manifestText, config.referenceSection, draft.key, row)
	if spliceDiagnostic ~= nil then
		outcome.diagnostic = spliceDiagnostic
		return outcome
	end
	local reparsed = codecs.decode(spliced)
	files.write(config.manifestPath, spliced)
	files.write(config.renderedPath, config.render(reparsed))
	local rowCount = 0
	for _, entry in (reparsed :: { [string]: { [string]: unknown } })[config.referenceSection] do
		if type(entry) == "table" and type((entry :: { [string]: unknown }).image_asset_id) == "number" then
			rowCount += 1
		end
	end
	outcome.row = row
	outcome.rowCount = rowCount
	return outcome
end

return {
	hiddenPath = hiddenPath,
	rendererParity = rendererParity,
	record = record,
}
