--!strict

local Secret = require "./secret"
local Types = require "./types"

type Artifact = Types.Artifact
type StageEconomics = Types.StageEconomics

local function isSha256(value: string): boolean
	return #value == 64 and string.match(value, "^[0-9a-f]+$") ~= nil
end

local function isFingerprint(value: string): boolean
	return #value == 40 and string.match(value, "^gen%-fp2%-%x+$") ~= nil
end

local function artifactFault(artifact: Artifact): string?
	if artifact.id == "" then
		return "artifact id is empty"
	end
	if artifact.digestAlgorithm ~= "sha256" or not isSha256(artifact.digest) then
		return "artifact lacks lowercase SHA-256 identity"
	end
	if artifact.mediaType == "" then
		return "artifact mediaType is empty"
	end
	if artifact.byteCount ~= nil and (artifact.byteCount < 0 or artifact.byteCount % 1 ~= 0) then
		return "artifact byteCount is not a non-negative integer"
	end
	if artifact.semanticId ~= nil and artifact.semanticId == "" then
		return "artifact semanticId is empty"
	end
	local metadataOk = pcall(Secret.validate, artifact.metadata, "Generate artifact metadata")
	if not metadataOk then
		return "artifact metadata contains secret-shaped or non-data state"
	end
	return nil
end

local function economicsFault(economics: StageEconomics): string?
	if economics.wallSeconds ~= nil and economics.wallSeconds < 0 then
		return "wallSeconds is negative"
	end
	if economics.attemptCount ~= nil and (economics.attemptCount < 0 or economics.attemptCount % 1 ~= 0) then
		return "attemptCount is not a non-negative integer"
	end
	if economics.providerCalls ~= nil then
		for _, call in economics.providerCalls do
			if call.provider == "" or call.kind == "" then
				return "a provider call lacks a provider or kind"
			end
			if call.count < 0 or call.count % 1 ~= 0 then
				return "a provider call count is not a non-negative integer"
			end
			if call.costMicros ~= nil and (call.costMicros < 0 or call.costMicros % 1 ~= 0) then
				return "a provider call costMicros is not a non-negative integer"
			end
			if call.creditUnits ~= nil and call.creditUnits < 0 then
				return "a provider call creditUnits is negative"
			end
		end
	end
	if economics.reviewers ~= nil then
		for _, reviewer in economics.reviewers do
			if reviewer.actor == "" then
				return "a reviewer lacks an identity"
			end
			if reviewer.inputTokens ~= nil and (reviewer.inputTokens < 0 or reviewer.inputTokens % 1 ~= 0) then
				return "a reviewer inputTokens is not a non-negative integer"
			end
			if reviewer.outputTokens ~= nil and (reviewer.outputTokens < 0 or reviewer.outputTokens % 1 ~= 0) then
				return "a reviewer outputTokens is not a non-negative integer"
			end
		end
	end
	if economics.publicationAttempts ~= nil then
		for _, attempt in economics.publicationAttempts do
			if attempt.ordinal < 1 or attempt.ordinal % 1 ~= 0 then
				return "a publication attempt ordinal is not a positive integer"
			end
			if attempt.disposition == "" then
				return "a publication attempt lacks a disposition"
			end
		end
	end
	return nil
end

return { artifactFault = artifactFault, economicsFault = economicsFault, isFingerprint = isFingerprint }
