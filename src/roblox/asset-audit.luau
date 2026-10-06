--!strict

local ReferenceProvenance = require "./reference-provenance"

export type Files = ReferenceProvenance.Files

export type Reference = {
	committed_source_path: string?,
	source_sha256: string?,
	prompt_path: string?,
	prompt: string?,
	prompt_sha256: string?,
	lineage_path: string?,
	reviewer_verdict_ids: { string }?,
	reviewer_verdict_receipt: string?,
	reviewer_verdict_anchor: string?,
	image_readback_receipt: string?,
	image_asset_id: number?,
	subject: string?,
	family: string?,
	group: string?,
	rights_basis: string?,
	disposition: string?,
	[string]: unknown,
}

export type Model = {
	reference_sha256: string?,
	reference_image_asset_id: number?,
	model_prompt_sha256: string?,
	comparison_verdict_receipt: string?,
	model_uuid: string?,
	durable_model_asset_id: number?,
	[string]: unknown,
}

export type Config = {
	referenceSection: string,
	modelSection: string,
	terminalDisposition: string,
	ownedProvenance: string,
	eligibilityFields: { string },
	requiredReferenceFields: { string }?,
	receiptFields: { string }?,
}

export type Input = {
	config: Config,
	files: Files,
	digest: (bytes: string) -> string,
	references: { [string]: Reference },
	models: { [string]: Model },
}

local DEFAULT_REQUIRED_REFERENCE_FIELDS: { string } = {
	"committed_source_path",
	"source_sha256",
	"prompt_sha256",
	"lineage_path",
	"reviewer_verdict_receipt",
	"reviewer_verdict_anchor",
	"image_readback_receipt",
	"subject",
	"family",
	"group",
	"rights_basis",
	"disposition",
}

local DEFAULT_RECEIPT_FIELDS: { string } = {
	"lineage_path",
	"reviewer_verdict_receipt",
	"image_readback_receipt",
}

local hiddenPath = ReferenceProvenance.hiddenPath

local function nonEmptyStringList(value: unknown): boolean
	if type(value) ~= "table" or #(value :: { unknown }) == 0 then
		return false
	end
	for _, item in value :: { unknown } do
		if type(item) ~= "string" or item == "" then
			return false
		end
	end
	return true
end

local function positiveId(value: unknown): boolean
	return type(value) == "number" and (value :: number) > 0
end

local function validInput(input: Input): boolean
	return type(input) == "table"
		and type(input.config) == "table"
		and type(input.config.referenceSection) == "string"
		and input.config.referenceSection ~= ""
		and type(input.config.modelSection) == "string"
		and input.config.modelSection ~= ""
		and type(input.config.terminalDisposition) == "string"
		and input.config.terminalDisposition ~= ""
		and type(input.config.ownedProvenance) == "string"
		and input.config.ownedProvenance ~= ""
		and type(input.config.eligibilityFields) == "table"
		and type(input.files) == "table"
		and type(input.files.read) == "function"
		and type(input.files.exists) == "function"
		and type(input.digest) == "function"
		and type(input.references) == "table"
		and type(input.models) == "table"
end

local function referenceViolations(input: Input): { string }
	if not validInput(input) then
		error("Generate asset audit requires a config, file reader, digest, and both row tables", 2)
	end
	local config = input.config
	local files = input.files
	local digest = input.digest
	local referenceLabel = config.referenceSection
	local modelLabel = config.modelSection
	local requiredFields = config.requiredReferenceFields or DEFAULT_REQUIRED_REFERENCE_FIELDS
	local receiptFields = config.receiptFields or DEFAULT_RECEIPT_FIELDS

	local violations: { string } = {}
	local seenOriginalHashes: { [string]: string } = {}
	local seenImageIds: { [number]: string } = {}
	local knownOriginalHashes: { [string]: true } = {}
	local knownImageIds: { [number]: true } = {}
	local knownReferencePairs: { [string]: string } = {}
	local linkedOriginalHashes: { [string]: true } = {}
	local linkedImageIds: { [number]: true } = {}

	local function referenceViolation(name: string, tail: string)
		table.insert(violations, ('%s["%s"] %s'):format(referenceLabel, name, tail))
	end

	local function modelViolation(name: string, tail: string)
		table.insert(violations, ('%s["%s"] %s'):format(modelLabel, name, tail))
	end

	for name, reference in input.references do
		for _, field in requiredFields do
			if type(reference[field]) ~= "string" or reference[field] == "" then
				referenceViolation(name, "missing " .. field)
			end
		end
		if not positiveId(reference.image_asset_id) then
			referenceViolation(name, "missing image_asset_id")
		end
		if not nonEmptyStringList(reference.reviewer_verdict_ids) then
			referenceViolation(name, "missing reviewer_verdict_ids")
		end
		for _, receiptField in receiptFields do
			local receipt = reference[receiptField]
			if type(receipt) == "string" and receipt ~= "" then
				if hiddenPath(receipt :: string) then
					referenceViolation(name, ("%s is a hidden path at %s"):format(receiptField, receipt :: string))
				end
				if not files.exists(receipt :: string) then
					referenceViolation(name, ("%s missing at %s"):format(receiptField, receipt :: string))
				end
			end
		end
		if type(reference.committed_source_path) == "string" and type(reference.source_sha256) == "string" then
			local committedPath = reference.committed_source_path :: string
			if not files.exists(committedPath) then
				referenceViolation(name, "original missing at " .. committedPath)
			elseif digest(files.read(committedPath)) ~= reference.source_sha256 then
				referenceViolation(name, "original hash drift")
			end
			local first = seenOriginalHashes[reference.source_sha256 :: string]
			if first ~= nil then
				referenceViolation(name, ('duplicates original identity of %s["%s"]'):format(referenceLabel, first))
			else
				seenOriginalHashes[reference.source_sha256 :: string] = name
			end
			knownOriginalHashes[reference.source_sha256 :: string] = true
		end
		local hasPromptPath = type(reference.prompt_path) == "string" and reference.prompt_path ~= ""
		local hasInlinePrompt = type(reference.prompt) == "string" and reference.prompt ~= ""
		if not hasPromptPath and not hasInlinePrompt then
			referenceViolation(name, "missing prompt_path or prompt")
		end
		if hasPromptPath and type(reference.prompt_sha256) == "string" then
			local promptPath = reference.prompt_path :: string
			if not files.exists(promptPath) then
				referenceViolation(name, "prompt missing at " .. promptPath)
			elseif digest(files.read(promptPath)) ~= reference.prompt_sha256 then
				referenceViolation(name, "prompt hash drift")
			end
		end
		if hasInlinePrompt and type(reference.prompt_sha256) == "string" then
			if digest(reference.prompt :: string) ~= reference.prompt_sha256 then
				referenceViolation(name, "inline prompt hash drift")
			end
		end
		if positiveId(reference.image_asset_id) then
			local imageId = reference.image_asset_id :: number
			local first = seenImageIds[imageId]
			if first ~= nil then
				referenceViolation(name, ('duplicates image identity of %s["%s"]'):format(referenceLabel, first))
			else
				seenImageIds[imageId] = name
			end
			knownImageIds[imageId] = true
		end
		if type(reference.source_sha256) == "string" and positiveId(reference.image_asset_id) then
			local pair = (reference.source_sha256 :: string) .. "|" .. tostring(reference.image_asset_id :: number)
			knownReferencePairs[pair] = name
		end
		local eligible = false
		for _, field in config.eligibilityFields do
			if reference[field] == true then
				eligible = true
			end
		end
		if
			eligible
			and (
				reference.disposition ~= config.terminalDisposition
				or reference.rights_basis ~= config.ownedProvenance
			)
		then
			referenceViolation(name, "grants eligibility without the terminal disposition and owned rights")
		end
	end

	local seenModels: { [string]: string } = {}
	for name, model in input.models do
		if type(model.reference_sha256) ~= "string" or model.reference_sha256 == "" then
			modelViolation(name, "missing reference_sha256 reverse link")
		else
			linkedOriginalHashes[model.reference_sha256 :: string] = true
			if not knownOriginalHashes[model.reference_sha256 :: string] then
				modelViolation(name, "reference_sha256 does not resolve to a reference image")
			end
		end
		if not positiveId(model.reference_image_asset_id) then
			modelViolation(name, "missing reference_image_asset_id reverse link")
		else
			local imageId = model.reference_image_asset_id :: number
			linkedImageIds[imageId] = true
			if not knownImageIds[imageId] then
				modelViolation(name, "reference_image_asset_id does not resolve to a reference image")
			end
		end
		if type(model.reference_sha256) == "string" and positiveId(model.reference_image_asset_id) then
			local pair = (model.reference_sha256 :: string) .. "|" .. tostring(model.reference_image_asset_id :: number)
			if knownReferencePairs[pair] == nil then
				modelViolation(name, "reference SHA/Image ID pair does not resolve to one reference image")
			end
		end
		if type(model.model_prompt_sha256) ~= "string" or model.model_prompt_sha256 == "" then
			modelViolation(name, "missing model_prompt_sha256")
		end
		if type(model.comparison_verdict_receipt) ~= "string" or model.comparison_verdict_receipt == "" then
			modelViolation(name, "missing comparison_verdict_receipt")
		elseif not files.exists(model.comparison_verdict_receipt :: string) then
			modelViolation(
				name,
				"comparison_verdict_receipt missing at " .. (model.comparison_verdict_receipt :: string)
			)
		end
		local hasUuid = type(model.model_uuid) == "string" and model.model_uuid ~= ""
		local hasDurableId = positiveId(model.durable_model_asset_id)
		if not hasUuid and not hasDurableId then
			modelViolation(name, "missing model_uuid/durable_model_asset_id")
		else
			local identities: { string } = {}
			if hasUuid then
				table.insert(identities, model.model_uuid :: string)
			end
			if hasDurableId then
				table.insert(identities, tostring(model.durable_model_asset_id :: number))
			end
			for _, identity in identities do
				local first = seenModels[identity]
				if first ~= nil then
					modelViolation(name, ('duplicates model identity of %s["%s"]'):format(modelLabel, first))
				else
					seenModels[identity] = name
				end
			end
		end
	end

	for name, reference in input.references do
		if reference.disposition == config.terminalDisposition then
			if
				type(reference.source_sha256) ~= "string"
				or not linkedOriginalHashes[reference.source_sha256 :: string]
			then
				referenceViolation(name, "missing conditioned-model reverse link by original SHA")
			end
			if not positiveId(reference.image_asset_id) or not linkedImageIds[reference.image_asset_id :: number] then
				referenceViolation(name, "missing conditioned-model reverse link by Image asset ID")
			end
		end
	end

	table.sort(violations)
	return violations
end

return {
	referenceViolations = referenceViolations,
}
