--!strict

local Generate = require "../core"

local DEFAULT_ADAPTER = "generate.image.review-staging.v1"

local DEFAULT_UNBLINDING_KEYS: { string } =
	{ "producer", "prompt", "promptPath", "brief", "briefId", "verdict", "reviewer" }

export type Config = { adapter: string, unblindingKeys: { string } }

local DEFAULT_CONFIG: Config = { adapter = DEFAULT_ADAPTER, unblindingKeys = DEFAULT_UNBLINDING_KEYS }

export type Request = {
	packetId: string,
	candidateId: string,
	revision: number,
	producer: string,
	candidateArtifactId: string,
	evidence: { { artifactId: string, view: string, role: string } },
	rubric: Generate.RubricIdentity,
	requestedViews: { string },
	captureEnvironment: { [string]: string },
}

export type Outcome = { ok: true, draft: Generate.ReviewPacketDraft } | { ok: false, diagnostic: string }

local function contains(values: { string }, wanted: string): boolean
	for _, value in values do
		if value == wanted then
			return true
		end
	end
	return false
end

local function stage(config: Config, request: Request, artifacts: { Generate.Artifact }): Outcome
	local byId: { [string]: Generate.Artifact } = {}
	for _, artifact in artifacts do
		byId[artifact.id] = artifact
	end
	local candidate = byId[request.candidateArtifactId]
	if candidate == nil then
		return {
			ok = false,
			diagnostic = ("packet %s names missing candidate %s"):format(request.packetId, request.candidateArtifactId),
		}
	end
	if #request.evidence == 0 then
		return {
			ok = false,
			diagnostic = ("packet %s stages no evidence for a reviewer to read"):format(request.packetId),
		}
	end
	if #request.requestedViews == 0 then
		return { ok = false, diagnostic = ("packet %s requests no view"):format(request.packetId) }
	end
	if request.rubric.fingerprint == "" then
		return { ok = false, diagnostic = ("packet %s pins no rubric fingerprint"):format(request.packetId) }
	end
	for key in request.captureEnvironment do
		if contains(config.unblindingKeys, key) then
			return {
				ok = false,
				diagnostic = ("packet %s carries %q in its capture environment, which unblinds the reviewer"):format(
					request.packetId,
					key
				),
			}
		end
	end

	local covered: { [string]: boolean } = {}
	local evidence: { Generate.EvidenceRef } = {}
	for _, entry in request.evidence do
		local artifact = byId[entry.artifactId]
		if artifact == nil then
			return {
				ok = false,
				diagnostic = ("packet %s names missing evidence %s"):format(request.packetId, entry.artifactId),
			}
		end
		if not contains(request.requestedViews, entry.view) then
			return {
				ok = false,
				diagnostic = ("packet %s binds evidence %s for view %q, which it never requested"):format(
					request.packetId,
					artifact.id,
					entry.view
				),
			}
		end
		covered[entry.view] = true
		table.insert(evidence, {
			id = artifact.id,
			digest = artifact.digest,
			digestAlgorithm = "sha256",
			view = entry.view,
			role = entry.role,
		})
	end
	for _, view in request.requestedViews do
		if not covered[view] then
			return {
				ok = false,
				diagnostic = ("packet %s requests view %q with no evidence bound to it"):format(request.packetId, view),
			}
		end
	end

	local views: { string } = {}
	for _, view in request.requestedViews do
		table.insert(views, view)
	end
	local environment: { [string]: string } = { adapter = config.adapter }
	for key, value in request.captureEnvironment do
		environment[key] = value
	end

	return {
		ok = true,
		draft = {
			id = request.packetId,
			candidate = {
				candidateId = request.candidateId,
				revision = request.revision,
				producer = request.producer,
				artifacts = { { id = candidate.id, digest = candidate.digest, digestAlgorithm = "sha256" } },
			},
			evidence = evidence,
			rubric = request.rubric,
			requestedViews = views,
			captureEnvironment = environment,
		},
	}
end

local function runStage(config: Config, request: Request, artifacts: { Generate.Artifact }): Generate.StageOutcome
	local outcome = stage(config, request, artifacts)
	if not outcome.ok then
		return { status = "rejected", detail = outcome.diagnostic }
	end
	return {
		status = "returned",
		output = { reviewPacket = outcome.draft, decisions = {} },
	}
end

return {
	DEFAULT_ADAPTER = DEFAULT_ADAPTER,
	DEFAULT_CONFIG = DEFAULT_CONFIG,
	stage = stage,
	runStage = runStage,
}
