--!strict

local Generate = require "../core"

type Authority = Generate.Authority
type Brief = Generate.Brief
type Host = Generate.Host
type Stage = Generate.Stage
type StageOutcome = Generate.StageOutcome

export type Options = {
	capabilities: { string }?,
	environment: { [string]: string }?,
	outcomes: { [string]: StageOutcome }?,
	compensationFaults: { [string]: string }?,
	trace: { string }?,
	idempotencyKeys: { string }?,
}

local function create(options: Options?): Host
	local settings: Options = options
		or {
			capabilities = nil,
			environment = nil,
			outcomes = nil,
			compensationFaults = nil,
			trace = nil,
			idempotencyKeys = nil,
		}
	local value = 0
	local trace = settings.trace or {}
	local outcomes = settings.outcomes
	return {
		name = "generate-fake",
		capabilities = settings.capabilities or {},
		environment = settings.environment or { fixture = "true" },
		now = function(): number
			value += 0.001
			return value
		end,
		runStage = function(
			stage: Stage,
			_brief: Brief,
			_artifacts: { Generate.Artifact },
			_authority: Authority,
			context: Generate.RunContext
		): StageOutcome
			table.insert(trace, "run:" .. stage.id)
			if settings.idempotencyKeys ~= nil then
				table.insert(settings.idempotencyKeys, context.idempotencyKey)
			end
			local found = if outcomes ~= nil then outcomes[stage.id] else nil
			return found or { status = "returned", output = {} }
		end,
		compensate = function(stage: Stage, _token: string, _authority: Authority): Generate.RollbackOutcome
			table.insert(trace, "rollback:" .. stage.id)
			local detail = if settings.compensationFaults ~= nil then settings.compensationFaults[stage.id] else nil
			if detail ~= nil then
				return { status = "faulted", detail = detail }
			end
			return { status = "returned" }
		end,
	}
end

return {
	create = create,
}
