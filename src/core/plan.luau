--!strict

local Brief = require "./brief"
local Canonical = require "./canonical"
local Secret = require "./secret"
local Types = require "./types"

type AssetBrief = Types.Brief
type Plan = Types.Plan
type Stage = Types.Stage
type StageDraft = Types.StageDraft

local SCHEMA_VERSION = 1

local function fingerprint(plan: Plan): string
	return Canonical.fingerprint {
		schemaVersion = plan.schemaVersion,
		id = plan.id,
		briefId = plan.briefId,
		briefFingerprint = plan.briefFingerprint,
		stages = plan.stages,
	}
end

local function copyMap(map: Types.StringMap?): Types.StringMap
	return table.clone(map or {})
end

local function copyUnique(values: { string }?, label: string): { string }
	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	local source: { string } = if values == nil then {} else values
	for _, value in source do
		if type(value) ~= "string" or value == "" then
			error(label .. " requires non-empty strings", 3)
		end
		if seen[value] then
			error(("%s contains duplicate %q"):format(label, value), 3)
		end
		seen[value] = true
		table.insert(result, value)
	end
	return result
end

local function compile(brief: AssetBrief, drafts: { StageDraft }): Plan
	if #drafts == 0 then
		error("Generate plan requires at least one stage", 2)
	end
	local seen: { [string]: boolean } = {}
	local stages: { Stage } = {}
	for _, draft in drafts do
		if type(draft.id) ~= "string" or draft.id == "" then
			error("Generate plan stage id must be a non-empty string", 2)
		end
		if seen[draft.id] then
			error(("Generate plan stage id %q is duplicated"):format(draft.id), 2)
		end
		local dependencies = copyUnique(draft.dependsOn, ("Generate plan stage %s dependencies"):format(draft.id))
		for _, dependency in dependencies do
			if not seen[dependency] then
				error(("Generate plan stage %q depends on unknown or later stage %q"):format(draft.id, dependency), 2)
			end
		end
		local mutation: boolean = draft.mutation == true
		if mutation and draft.rollback ~= "required" then
			error(("Generate mutation stage %q must declare rollback = required"):format(draft.id), 2)
		elseif not mutation and draft.rollback == "required" then
			error(("Generate non-mutation stage %q cannot declare rollback"):format(draft.id), 2)
		end
		local rollback: Types.RollbackContract = draft.rollback or "none"
		if draft.operation == "publish" and not mutation then
			error(("Generate publish stage %q must be an explicit mutation"):format(draft.id), 2)
		end
		local estimatedCostMicros = draft.estimatedCostMicros or 0
		if estimatedCostMicros < 0 or estimatedCostMicros % 1 ~= 0 then
			error(("Generate plan stage %q estimatedCostMicros must be a non-negative integer"):format(draft.id), 2)
		end
		Secret.validate(draft.parameters or {}, ("Generate plan stage %s parameters"):format(draft.id))
		seen[draft.id] = true
		local stage: Stage = {
			id = draft.id,
			operation = draft.operation,
			dependsOn = dependencies,
			requires = Canonical.sortedStrings(copyUnique(draft.requires, "Generate stage requirements")),
			mutation = mutation,
			rollback = rollback,
			parameters = copyMap(draft.parameters),
			deterministic = draft.deterministic == true,
			estimatedCostMicros = estimatedCostMicros,
		}
		table.insert(stages, stage)
	end
	local partial = {
		schemaVersion = SCHEMA_VERSION,
		id = brief.id .. "/production",
		briefId = brief.id,
		briefFingerprint = Brief.fingerprint(brief),
		stages = stages,
	}
	local result = table.clone(partial)
	result.fingerprint = Canonical.fingerprint(partial)
	return result
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	compile = compile,
	fingerprint = fingerprint,
}
