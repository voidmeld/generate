--!strict

local Generate = require "../src/core"

type Artifact = Generate.Artifact
type Brief = Generate.Brief
type StageOutcome = Generate.StageOutcome

export type Operations = {
	tool: string,
	version: string,
	compile: (kind: Generate.AssetKind, source: string, schema: string, semanticId: string) -> Artifact,
}

local function compile(operations: Operations, brief: Brief, source: string, schema: string): StageOutcome
	if source == "" or schema == "" then
		return { status = "rejected", detail = "structured content requires source and schema identities" }
	end
	if operations.tool == "" or operations.version == "" then
		return { status = "faulted", detail = "structured content compiler requires exact tool identity" }
	end
	local ok, artifact = pcall(operations.compile, brief.kind, source, schema, brief.delivery.semanticId)
	if not ok then
		return { status = "faulted", detail = "structured content compilation raised: " .. tostring(artifact) }
	end
	return {
		status = "returned",
		output = {
			artifacts = { artifact :: Artifact },
			invocations = {
				{
					tool = operations.tool,
					toolVersion = operations.version,
					parametersFingerprint = Generate.fingerprint { kind = brief.kind, source = source, schema = schema },
					deterministic = true,
				},
			},
		},
	}
end

return {
	compile = compile,
}
