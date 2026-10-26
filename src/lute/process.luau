--!strict

local crypto = require "@lute/crypto"
local fs = require "@std/fs"
local process = require "@std/process"

local Generate = require "../core"

type Artifact = Generate.Artifact
type StageOutcome = Generate.StageOutcome

export type Options = {
	command: { string },
	output: string,
	id: string,
	mediaType: string,
	semanticId: string?,
	tool: string,
	toolVersion: string,
	parameters: { [string]: string }?,
	deterministic: boolean,
}

local function sha256(bytes: string): string
	local digest = crypto.digest(crypto.hash.sha256, bytes)
	local pieces: { string } = {}
	for index = 0, buffer.len(digest) - 1 do
		table.insert(pieces, string.format("%02x", buffer.readu8(digest, index)))
	end
	return table.concat(pieces)
end

local function run(options: Options): StageOutcome
	if #options.command == 0 or options.output == "" then
		return { status = "rejected", detail = "DCC/media process requires a command and output path" }
	end
	local result = process.run(options.command)
	if not result.ok then
		return {
			status = "faulted",
			detail = ("%s exited %d: %s"):format(options.tool, result.exitcode, result.stderr),
		}
	end
	if not fs.exists(options.output) then
		return { status = "faulted", detail = options.tool .. " returned without its declared output" }
	end
	local bytes = fs.readFileToString(options.output)
	local artifact: Artifact = {
		id = options.id,
		digest = sha256(bytes),
		digestAlgorithm = "sha256",
		mediaType = options.mediaType,
		byteCount = #bytes,
		locator = options.output,
		semanticId = options.semanticId,
		metadata = {},
	}
	return {
		status = "returned",
		output = {
			artifacts = { artifact },
			invocations = {
				{
					tool = options.tool,
					toolVersion = options.toolVersion,
					parametersFingerprint = Generate.fingerprint(options.parameters or {}),
					deterministic = options.deterministic,
				},
			},
		},
	}
end

return {
	run = run,
}
