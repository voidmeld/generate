--!strict

local BriefModel = require "./brief"
local Canonical = require "./canonical"
local PlanModel = require "./plan"
local Provenance = require "./provenance"
local ReceiptModel = require "./receipt"
local Review = require "./review"
local Secret = require "./secret"
local Types = require "./types"

type Artifact = Types.Artifact
type Authority = Types.Authority
type Brief = Types.Brief
type Checkpoint = Types.Checkpoint
type CompensationRecord = Types.CompensationRecord
type Derivation = Types.Derivation
type Host = Types.Host
type Invocation = Types.Invocation
type Plan = Types.Plan
type Receipt = Types.Receipt
type ResolvedReview = Types.ResolvedReview
type ReviewDecision = Types.ReviewDecision
type ReviewDecisionDraft = Types.ReviewDecisionDraft
type ReviewPacket = Types.ReviewPacket
type Stage = Types.Stage
type StageEconomics = Types.StageEconomics
type StageRecord = Types.StageRecord

local RECEIPT_SCHEMA_VERSION = 2

local CARRYING_OPERATIONS: { [string]: boolean } = { verify = true, review = true, publish = true }

local receiptFingerprint = ReceiptModel.fingerprint

local function micros(seconds: number): number
	return math.max(0, math.floor(seconds * 1e6 + 0.5))
end

local function set(values: { string }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, value in values do
		result[value] = true
	end
	return result
end

local function limitationFor(stage: Stage, reason: string): string
	return ("stage %s (%s): %s"):format(stage.id, stage.operation, reason)
end

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

local function measuredEconomics(duration: number): StageEconomics
	return { wallSeconds = duration / 1e6 }
end

local function mergeEconomics(declared: StageEconomics?, duration: number): StageEconomics
	local merged: StageEconomics = if declared == nil then {} else table.clone(declared)
	if merged.wallSeconds == nil then
		merged.wallSeconds = duration / 1e6
	end
	return merged
end

local function sameViews(left: { string }, right: { string }): boolean
	if #left ~= #right then
		return false
	end
	local seen = set(right)
	for _, value in left do
		if not seen[value] then
			return false
		end
	end
	return true
end

local function executeInternal(brief: Brief, plan: Plan, host: Host, authority: Authority, resume: Checkpoint?): Receipt
	if plan.briefId ~= brief.id then
		error(("Generate execute plan %q belongs to %q, not %q"):format(plan.id, plan.briefId, brief.id), 2)
	end
	if plan.briefFingerprint ~= BriefModel.fingerprint(brief) then
		error(("Generate execute plan %q does not bind the supplied brief contents"):format(plan.id), 2)
	end
	if plan.fingerprint ~= PlanModel.fingerprint(plan) then
		error(("Generate execute plan %q contents changed after compilation"):format(plan.id), 2)
	end
	if authority.mutationBudget < 0 or authority.mutationBudget % 1 ~= 0 then
		error("Generate authority mutationBudget must be a non-negative integer", 2)
	end
	Secret.validate(host.environment, "Generate host environment")
	local costBudget = authority.costBudgetMicros or 0
	if costBudget < 0 or costBudget % 1 ~= 0 then
		error("Generate authority costBudgetMicros must be a non-negative integer", 2)
	end
	local started = host.now()
	local records: { StageRecord } = {}
	local compensations: { CompensationRecord } = {}
	local artifacts: { Artifact } = {}
	local packets: { ReviewPacket } = {}
	local decisions: { ReviewDecision } = {}
	local derivations: { Derivation } = {}
	local limitations: { string } = {}
	local available = set(host.capabilities)
	local authorized = set(authority.capabilities)
	local completedMutations: { { stage: Stage, token: string } } = {}
	local terminal: Types.ReceiptStatus = "produced"
	local mutationCount = 0
	local costMicros = 0
	local destinationSet = set(authority.destinations)
	local nextStage = 1
	local artifactIds: { [string]: boolean } = {}
	local artifactById: { [string]: Artifact } = {}
	local packetIds: { [string]: boolean } = {}
	local derivationByArtifactId: { [string]: Derivation } = {}
	local derivationOperation: { [string]: Types.Operation } = {}

	local function adoptArtifact(artifact: Artifact)
		artifactIds[artifact.id] = true
		artifactById[artifact.id] = artifact
		table.insert(artifacts, artifact)
	end

	local function adoptPacket(value: ReviewPacket)
		packetIds[value.id] = true
		table.insert(packets, value)
	end

	local function adoptDerivation(value: Derivation)
		derivationByArtifactId[value.artifactId] = value
		table.insert(derivations, value)
	end

	if resume ~= nil then
		local checkpoint = resume
		if
			checkpoint.schemaVersion ~= 1
			or checkpoint.briefFingerprint ~= plan.briefFingerprint
			or checkpoint.planFingerprint ~= plan.fingerprint
			or checkpoint.nextStage < 1
			or checkpoint.nextStage > #plan.stages + 1
			or #checkpoint.records ~= checkpoint.nextStage - 1
		then
			error("Generate execute checkpoint does not bind the supplied plan state", 2)
		end
		local rebuiltArtifacts: { Artifact } = {}
		local rebuiltPackets: { ReviewPacket } = {}
		local rebuiltDecisions: { ReviewDecision } = {}
		local rebuiltDerivations: { Derivation } = {}
		local rebuiltCost = 0
		for index, record in checkpoint.records do
			local stage = plan.stages[index]
			if
				record.id ~= stage.id
				or record.operation ~= stage.operation
				or stage.mutation
				or record.status ~= "returned"
				or record.idempotencyKey ~= plan.fingerprint .. ":" .. record.id
				or record.costMicros < 0
				or record.costMicros % 1 ~= 0
				or record.costMicros > stage.estimatedCostMicros
			then
				error("Generate execute checkpoints may resume only returned non-mutation stages in plan order", 2)
			end
			if Canonical.encode(record.inputArtifacts) ~= Canonical.encode(rebuiltArtifacts) then
				error("Generate execute checkpoint artifact lineage does not match its stage records", 2)
			end
			if not pcall(Secret.validate, record.metadata, "Generate checkpoint stage metadata") then
				error("Generate execute checkpoint carries invalid stage metadata", 2)
			end
			for _, invocation in record.invocations do
				if
					invocation.tool == ""
					or invocation.toolVersion == ""
					or not isFingerprint(invocation.parametersFingerprint)
					or (stage.deterministic and not invocation.deterministic)
				then
					error("Generate execute checkpoint carries invalid invocation evidence", 2)
				end
			end
			for _, artifact in record.artifacts do
				local fault = artifactFault(artifact)
				if fault ~= nil or artifactIds[artifact.id] then
					error("Generate execute checkpoint carries invalid or duplicate artifact identity", 2)
				end
				adoptArtifact(artifact)
				table.insert(rebuiltArtifacts, artifact)
			end
			for _, value in record.derivations do
				derivationOperation[value.artifactId] = record.operation
				if value.fingerprint ~= Provenance.fingerprintOf(value) then
					error("Generate execute checkpoint carries a derivation changed after execution", 2)
				end
				if derivationByArtifactId[value.artifactId] ~= nil then
					error("Generate execute checkpoint repeats a derivation for one artifact", 2)
				end
				adoptDerivation(value)
				table.insert(rebuiltDerivations, value)
			end
			if record.reviewPacket ~= nil then
				local value = record.reviewPacket
				if packetIds[value.id] then
					error("Generate execute checkpoint repeats a review packet identity", 2)
				end
				if value.rubric.fingerprint ~= brief.review.rubric.fingerprint then
					error("Generate execute checkpoint carries a review packet bound to a drifted rubric", 2)
				end
				adoptPacket(value)
				table.insert(rebuiltPackets, value)
			end
			for _, value in record.decisions do
				if not packetIds[value.packetId] then
					error("Generate execute checkpoint carries a decision without its review packet", 2)
				end
				table.insert(decisions, value)
				table.insert(rebuiltDecisions, value)
			end
			rebuiltCost += record.costMicros
		end
		if
			rebuiltCost ~= checkpoint.costMicros
			or Canonical.encode(rebuiltArtifacts) ~= Canonical.encode(checkpoint.artifacts)
			or Canonical.encode(rebuiltPackets) ~= Canonical.encode(checkpoint.reviewPackets)
			or Canonical.encode(rebuiltDecisions) ~= Canonical.encode(checkpoint.decisions)
			or Canonical.encode(rebuiltDerivations) ~= Canonical.encode(checkpoint.derivations)
		then
			error("Generate execute checkpoint summary does not match its stage records", 2)
		end
		records = table.clone(checkpoint.records)
		costMicros = checkpoint.costMicros
		if costMicros > costBudget then
			error("Generate execute checkpoint exceeds supplied cost authority", 2)
		end
		nextStage = checkpoint.nextStage
	end

	local function staleness(value: ReviewPacket): Types.ReviewStaleness
		local bound: { [string]: boolean } = {}
		for _, reference in value.candidate.artifacts do
			bound[reference.id] = true
		end
		local carried: { [string]: boolean } = table.clone(bound)
		for _, reference in value.evidence do
			carried[reference.id] = true
		end
		for _, derivation in derivations do
			if carried[derivation.artifactId] or CARRYING_OPERATIONS[derivationOperation[derivation.artifactId]] then
				continue
			end
			for _, parent in derivation.parents do
				if parent.artifactId ~= nil and bound[parent.artifactId] then
					return {
						stale = true,
						reason = ("artifact %q was transformed into %q after this packet was reviewed"):format(
							parent.artifactId,
							derivation.artifactId
						),
					}
				end
			end
		end
		for _, other in packets do
			if
				other.candidate.candidateId == value.candidate.candidateId
				and other.candidate.revision > value.candidate.revision
			then
				return {
					stale = true,
					reason = ("candidate %q advanced to revision %d after this packet was reviewed"):format(
						value.candidate.candidateId,
						other.candidate.revision
					),
				}
			end
		end
		return { stale = false, reason = nil }
	end

	local function resolveReviews(): { ResolvedReview }
		local resolved: { ResolvedReview } = {}
		for _, value in packets do
			local bound: { ReviewDecision } = {}
			for _, decision in decisions do
				if decision.packetId == value.id then
					table.insert(bound, decision)
				end
			end
			table.insert(resolved, Review.resolve(value, brief.review, bound, staleness(value)))
		end
		return resolved
	end

	local function provenanceFaults(review: ResolvedReview): { string }
		local faults: { string } = {}
		for _, reference in review.candidateArtifacts do
			for _, fault in
				Provenance.requirementFaults(
					derivationByArtifactId[reference.id],
					brief.provenance,
					derivationByArtifactId,
					reference.id
				)
			do
				table.insert(faults, fault)
			end
		end
		return faults
	end

	local function deliveryReview(reviews: { ResolvedReview }): (ResolvedReview?, { string })
		local faults: { string } = {}
		for _, review in reviews do
			if review.disposition ~= "approved" then
				continue
			end
			for _, artifact in artifacts do
				if artifact.semanticId ~= brief.delivery.semanticId then
					continue
				end
				if not Review.binds(review, artifact.id, artifact.digest) then
					continue
				end
				local missing = provenanceFaults(review)
				if #missing == 0 then
					return review, {}
				end
				for _, fault in missing do
					table.insert(faults, fault)
				end
			end
		end
		return nil, faults
	end

	local function appendNotRun(after: number, detail: string)
		for later = after + 1, #plan.stages do
			local skipped = plan.stages[later]
			table.insert(records, {
				id = skipped.id,
				operation = skipped.operation,
				status = "not_run",
				startedMicros = micros(host.now() - started),
				durationMicros = 0,
				detail = detail,
				inputArtifacts = {},
				artifacts = {},
				invocations = {},
				decisions = {},
				derivations = {},
				idempotencyKey = plan.fingerprint .. ":" .. skipped.id,
				costMicros = 0,
				metadata = {},
			})
		end
	end

	local function compensate()
		for index = #completedMutations, 1, -1 do
			local entry = completedMutations[index]
			if host.compensate == nil then
				table.insert(compensations, {
					stageId = entry.stage.id,
					status = "faulted",
					detail = "host has no compensation operation",
				})
				continue
			end
			local ok, outcome = pcall(host.compensate, entry.stage, entry.token, authority)
			if not ok then
				table.insert(compensations, {
					stageId = entry.stage.id,
					status = "faulted",
					detail = tostring(outcome),
				})
			elseif outcome.status == "returned" then
				table.insert(compensations, { stageId = entry.stage.id, status = "returned" })
			else
				table.insert(compensations, {
					stageId = entry.stage.id,
					status = "faulted",
					detail = outcome.detail,
				})
			end
		end
	end

	for position, stage in plan.stages do
		if position < nextStage then
			continue
		end
		local idempotencyKey = plan.fingerprint .. ":" .. stage.id
		local stageInputs = table.clone(artifacts)
		local missing: { string } = {}
		for _, requirement in stage.requires do
			if not available[requirement] or not authorized[requirement] then
				table.insert(missing, requirement)
			end
		end
		if stage.mutation then
			mutationCount += 1
			if mutationCount > authority.mutationBudget then
				table.insert(missing, "mutation-budget")
			end
		end
		if costMicros + stage.estimatedCostMicros > costBudget then
			table.insert(missing, "cost-budget")
		end
		if stage.operation == "publish" then
			if not destinationSet[brief.delivery.target] then
				table.insert(missing, "destination:" .. brief.delivery.target)
			end
			local approved, faults = deliveryReview(resolveReviews())
			if approved == nil then
				table.insert(missing, "resolved-review-decision")
				for _, fault in faults do
					table.insert(limitations, limitationFor(stage, fault))
				end
			end
		end
		if #missing > 0 then
			table.insert(records, {
				id = stage.id,
				operation = stage.operation,
				status = "unsupported",
				startedMicros = micros(host.now() - started),
				durationMicros = 0,
				detail = "missing capability or authority: " .. table.concat(missing, ", "),
				inputArtifacts = stageInputs,
				artifacts = {},
				invocations = {},
				decisions = {},
				derivations = {},
				idempotencyKey = idempotencyKey,
				costMicros = 0,
				metadata = {},
			})
			table.insert(limitations, limitationFor(stage, "missing " .. table.concat(missing, ", ")))
			terminal = "unsupported"
			appendNotRun(position, "an earlier stage was unsupported")
			compensate()
			break
		end

		local stageStarted = host.now()
		local ok, outcome = pcall(host.runStage, stage, brief, stageInputs, authority, {
			idempotencyKey = idempotencyKey,
		})
		local duration = micros(host.now() - stageStarted)
		if not ok then
			outcome = { status = "faulted", detail = tostring(outcome) }
		end
		if outcome.status ~= "returned" then
			local status: "rejected" | "faulted" = if outcome.status == "rejected" then "rejected" else "faulted"
			if stage.mutation and outcome.rollbackToken ~= nil and outcome.rollbackToken ~= "" then
				table.insert(completedMutations, { stage = stage, token = outcome.rollbackToken :: string })
			end
			table.insert(records, {
				id = stage.id,
				operation = stage.operation,
				status = status,
				startedMicros = micros(stageStarted - started),
				durationMicros = duration,
				detail = outcome.detail,
				inputArtifacts = stageInputs,
				artifacts = {},
				invocations = {},
				decisions = {},
				derivations = {},
				rollbackToken = outcome.rollbackToken,
				idempotencyKey = idempotencyKey,
				costMicros = 0,
				metadata = {},
				economics = measuredEconomics(duration),
			})
			terminal = if status == "rejected" then "rejected" else "failed"
			appendNotRun(position, "an earlier stage did not return")
			compensate()
			break
		end

		local output = outcome.output
		local actualCost = output.costMicros or 0
		local produced: { Artifact } = if output.artifacts == nil then {} else output.artifacts
		local contractFault: string? = nil
		if actualCost < 0 or actualCost % 1 ~= 0 or actualCost > stage.estimatedCostMicros then
			contractFault = ("Generate stage %q returned costMicros outside its declared estimate"):format(stage.id)
		end
		local producedById: { [string]: Artifact } = {}
		for _, artifact in produced do
			local fault = artifactFault(artifact)
			if fault ~= nil then
				contractFault = ("Generate stage %q returned invalid %s"):format(stage.id, fault)
				break
			end
			if artifactIds[artifact.id] or producedById[artifact.id] ~= nil then
				contractFault = ("Generate stage %q returned duplicate artifact id %q"):format(stage.id, artifact.id)
				break
			end
			producedById[artifact.id] = artifact
		end
		local invocations: { Invocation } = output.invocations or {}
		if contractFault == nil then
			for _, invocation in invocations do
				if invocation.tool == "" or invocation.toolVersion == "" then
					contractFault = ("Generate stage %q returned an invocation without exact tool identity"):format(
						stage.id
					)
					break
				end
				if not isFingerprint(invocation.parametersFingerprint) then
					contractFault = ("Generate stage %q returned an invocation without a parameter fingerprint"):format(
						stage.id
					)
					break
				end
				if stage.deterministic and not invocation.deterministic then
					contractFault = ("Generate deterministic stage %q returned a stochastic invocation"):format(
						stage.id
					)
					break
				end
				if invocation.costMicros ~= nil and (invocation.costMicros < 0 or invocation.costMicros % 1 ~= 0) then
					contractFault = ("Generate stage %q returned invalid invocation cost"):format(stage.id)
					break
				end
			end
		end
		if output.metadata ~= nil and not pcall(Secret.validate, output.metadata, "Generate stage metadata") then
			contractFault = ("Generate stage %q returned secret-shaped or non-data metadata"):format(stage.id)
		end
		if contractFault == nil and output.economics ~= nil then
			local fault = economicsFault(output.economics)
			if fault ~= nil then
				contractFault = ("Generate stage %q returned invalid economics: %s"):format(stage.id, fault)
			end
		end

		local stageDerivations: { Derivation } = {}
		if contractFault == nil then
			local derivationDrafts: { Types.DerivationDraft } = output.derivations or {}
			for _, draft in derivationDrafts do
				local built, thrown = pcall(Provenance.derivation, draft)
				if not built then
					contractFault = ("Generate stage %q returned an invalid derivation: %s"):format(
						stage.id,
						tostring(thrown)
					)
					break
				end
				local value = thrown :: Derivation
				local target = producedById[value.artifactId]
				if target == nil then
					contractFault = ("Generate stage %q derived %q without producing it"):format(
						stage.id,
						value.artifactId
					)
					break
				end
				if target.digest ~= value.artifactDigest then
					contractFault = ("Generate stage %q derivation digest does not bind artifact %q"):format(
						stage.id,
						value.artifactId
					)
					break
				end
				if derivationByArtifactId[value.artifactId] ~= nil then
					contractFault = ("Generate stage %q repeated the derivation of %q"):format(
						stage.id,
						value.artifactId
					)
					break
				end
				local parentFault: string? = nil
				for _, parent in value.parents do
					if parent.artifactId == nil then
						continue
					end
					local parentId = parent.artifactId :: string
					if artifactIds[parentId] then
						local known = artifactById[parentId]
						if parent.artifactDigest ~= nil and parent.artifactDigest ~= known.digest then
							parentFault = ("Generate stage %q derivation misbinds parent digest for %q"):format(
								stage.id,
								parentId
							)
						end
					elseif parent.receiptId == nil and parent.jobId == nil then
						parentFault = ("Generate stage %q derivation names unknown parent artifact %q without a cross-job identity"):format(
							stage.id,
							parentId
						)
					end
					if parentFault ~= nil then
						break
					end
				end
				if parentFault ~= nil then
					contractFault = parentFault
					break
				end
				derivationByArtifactId[value.artifactId] = value
				table.insert(stageDerivations, value)
			end
		end
		if contractFault ~= nil then
			for _, value in stageDerivations do
				derivationByArtifactId[value.artifactId] = nil
			end
			stageDerivations = {}
		end

		local stagePacket: ReviewPacket? = nil
		if contractFault == nil and output.reviewPacket ~= nil then
			local binding: Types.PacketBinding = {
				briefId = brief.id,
				briefFingerprint = plan.briefFingerprint,
				planFingerprint = plan.fingerprint,
				stageId = stage.id,
			}
			local built, thrown = pcall(Review.packet, output.reviewPacket, binding)
			if not built then
				contractFault = ("Generate stage %q returned an invalid review packet: %s"):format(
					stage.id,
					tostring(thrown)
				)
			else
				local value = thrown :: ReviewPacket
				if packetIds[value.id] then
					contractFault = ("Generate stage %q repeated review packet identity %q"):format(stage.id, value.id)
				elseif
					value.rubric.id ~= brief.review.rubric.id
					or value.rubric.fingerprint ~= brief.review.rubric.fingerprint
				then
					contractFault = ("Generate stage %q bound rubric %q/%s against brief rubric %q/%s"):format(
						stage.id,
						value.rubric.id,
						value.rubric.fingerprint,
						brief.review.rubric.id,
						brief.review.rubric.fingerprint
					)
				elseif not sameViews(value.requestedViews, brief.review.views) then
					contractFault = ("Generate stage %q requested review views the brief does not declare"):format(
						stage.id
					)
				else
					for _, reference in value.candidate.artifacts do
						local known = artifactById[reference.id] or producedById[reference.id]
						if known == nil or known.digest ~= reference.digest then
							contractFault = ("Generate stage %q bound candidate artifact %q that this receipt does not carry at that digest"):format(
								stage.id,
								reference.id
							)
							break
						end
					end
					if contractFault == nil then
						for _, reference in value.evidence do
							local known = artifactById[reference.id] or producedById[reference.id]
							if known == nil or known.digest ~= reference.digest then
								contractFault = ("Generate stage %q bound evidence artifact %q that this receipt does not carry at that digest"):format(
									stage.id,
									reference.id
								)
								break
							end
						end
					end
					if contractFault == nil then
						stagePacket = value
					end
				end
			end
		end

		local stageDecisions: { ReviewDecision } = {}
		if contractFault == nil then
			local knownPacket = if stagePacket ~= nil then stagePacket.id else nil
			local decisionDrafts: { Types.ReviewDecisionDraft } = output.decisions or {}
			for _, draft in decisionDrafts do
				local built, thrown = pcall(Review.decision, draft)
				if not built then
					contractFault = ("Generate stage %q returned an invalid review decision: %s"):format(
						stage.id,
						tostring(thrown)
					)
					break
				end
				local value = thrown :: ReviewDecision
				if not packetIds[value.packetId] and value.packetId ~= knownPacket then
					contractFault = ("Generate stage %q reported a decision on unknown review packet %q"):format(
						stage.id,
						value.packetId
					)
					break
				end
				table.insert(stageDecisions, value)
			end
		end

		if stage.mutation and (output.rollbackToken == nil or output.rollbackToken == "") then
			contractFault = ("Generate mutation stage %q returned without a rollback token"):format(stage.id)
		end
		if contractFault ~= nil then
			for _, value in stageDerivations do
				derivationByArtifactId[value.artifactId] = nil
			end
			if stage.mutation and output.rollbackToken ~= nil and output.rollbackToken ~= "" then
				table.insert(completedMutations, { stage = stage, token = output.rollbackToken })
			end
			table.insert(records, {
				id = stage.id,
				operation = stage.operation,
				status = "faulted",
				startedMicros = micros(stageStarted - started),
				durationMicros = duration,
				detail = contractFault,
				inputArtifacts = stageInputs,
				artifacts = {},
				invocations = {},
				decisions = {},
				derivations = {},
				idempotencyKey = idempotencyKey,
				costMicros = 0,
				metadata = {},
				economics = measuredEconomics(duration),
			})
			table.insert(limitations, limitationFor(stage, contractFault))
			terminal = "failed"
			appendNotRun(position, "an earlier stage violated the host contract")
			compensate()
			break
		end
		for _, artifact in produced do
			adoptArtifact(artifact)
		end
		for _, value in stageDerivations do
			derivationOperation[value.artifactId] = stage.operation
			table.insert(derivations, value)
		end
		if stagePacket ~= nil then
			adoptPacket(stagePacket)
		end
		for _, value in stageDecisions do
			table.insert(decisions, value)
		end
		costMicros += actualCost
		if stage.mutation then
			table.insert(completedMutations, { stage = stage, token = output.rollbackToken :: string })
		end
		table.insert(records, {
			id = stage.id,
			operation = stage.operation,
			status = "returned",
			startedMicros = micros(stageStarted - started),
			durationMicros = duration,
			inputArtifacts = stageInputs,
			artifacts = table.clone(produced),
			invocations = table.clone(output.invocations or {}),
			reviewPacket = stagePacket,
			decisions = table.clone(stageDecisions),
			derivations = table.clone(stageDerivations),
			rollbackToken = output.rollbackToken,
			idempotencyKey = idempotencyKey,
			costMicros = actualCost,
			metadata = table.clone(output.metadata or {}),
			economics = mergeEconomics(output.economics, duration),
		})
	end

	local reviews = resolveReviews()
	if terminal == "produced" then
		local approved, faults = deliveryReview(reviews)
		if approved ~= nil then
			terminal = "accepted"
		else
			local rejected = false
			for _, review in reviews do
				if review.disposition ~= "approved" then
					table.insert(
						limitations,
						("review %s: %s (%s)"):format(review.id, review.disposition, review.resolution)
					)
				end
				if review.disposition == "rejected" then
					rejected = true
				end
			end
			for _, fault in faults do
				table.insert(limitations, "provenance: " .. fault)
			end
			if #reviews == 0 then
				table.insert(limitations, "no resolved review binds the delivered candidate")
			end
			if rejected then
				terminal = "rejected"
			end
		end
	end

	local approvedReview = if terminal == "accepted" then (deliveryReview(reviews)) else nil
	local rejectedArtifacts: { [string]: boolean } = {}
	local approvedArtifacts: { [string]: boolean } = {}
	for _, review in reviews do
		if review.disposition == "rejected" then
			for _, reference in review.candidateArtifacts do
				rejectedArtifacts[reference.id] = true
			end
		end
	end
	if approvedReview ~= nil then
		for _, reference in approvedReview.candidateArtifacts do
			approvedArtifacts[reference.id] = true
		end
	end
	local supersededArtifacts: { [string]: boolean } = {}
	for _, derivation in derivations do
		for _, parent in derivation.parents do
			if parent.artifactId ~= nil and parent.artifactId ~= derivation.artifactId then
				supersededArtifacts[parent.artifactId] = true
			end
		end
	end
	local finalDerivations: { Derivation } = {}
	for _, derivation in derivations do
		local disposition: Types.CandidateDisposition = derivation.disposition
		if approvedArtifacts[derivation.artifactId] then
			disposition = "approved"
		elseif rejectedArtifacts[derivation.artifactId] then
			disposition = "rejected"
		elseif supersededArtifacts[derivation.artifactId] then
			disposition = "superseded"
		end
		table.insert(finalDerivations, Provenance.withDisposition(derivation, disposition))
	end
	for index, record in records do
		if #record.derivations == 0 then
			continue
		end
		local rebound: { Derivation } = {}
		for _, derivation in record.derivations do
			for _, final in finalDerivations do
				if final.artifactId == derivation.artifactId then
					table.insert(rebound, final)
					break
				end
			end
		end
		local updated = table.clone(record)
		updated.derivations = rebound
		records[index] = updated
	end

	local payload = {
		schemaVersion = RECEIPT_SCHEMA_VERSION,
		id = plan.id .. "/receipt",
		briefId = brief.id,
		briefFingerprint = plan.briefFingerprint,
		planFingerprint = plan.fingerprint,
		reviewContract = brief.review,
		provenanceContract = brief.provenance,
		host = host.name,
		environment = table.clone(host.environment),
		status = terminal,
		startedMicros = micros(started),
		durationMicros = micros(host.now() - started),
		stages = records,
		compensations = compensations,
		artifacts = artifacts,
		reviewPackets = packets,
		decisions = decisions,
		reviews = reviews,
		derivations = finalDerivations,
		limitations = limitations,
		costMicros = costMicros,
	}
	local result = table.clone(payload)
	result.fingerprint = Canonical.fingerprint(payload)
	return result
end

local function execute(brief: Brief, plan: Plan, host: Host, authority: Authority): Receipt
	return executeInternal(brief, plan, host, authority, nil)
end

local function continueReview(brief: Brief, plan: Plan, receipt: Receipt, drafts: { ReviewDecisionDraft }): Receipt
	if receipt.fingerprint ~= receiptFingerprint(receipt) then
		error("Generate continueReview requires an unchanged receipt", 2)
	end
	if receipt.status ~= "produced" or receipt.checkpoint ~= nil then
		error("Generate continueReview requires one completed produced receipt", 2)
	end
	if receipt.briefId ~= brief.id or receipt.briefFingerprint ~= BriefModel.fingerprint(brief) then
		error("Generate continueReview receipt does not bind the supplied brief", 2)
	end
	if
		receipt.planFingerprint ~= plan.fingerprint
		or plan.briefId ~= brief.id
		or plan.briefFingerprint ~= receipt.briefFingerprint
	then
		error("Generate continueReview receipt does not bind the supplied plan", 2)
	end
	if #receipt.reviewPackets == 0 then
		error("Generate continueReview receipt carries no review packet", 2)
	end
	if #drafts == 0 then
		error("Generate continueReview requires at least one review decision", 2)
	end
	local source = Canonical.copy(receipt) :: Receipt

	local packetIds: { [string]: boolean } = {}
	for _, packet in source.reviewPackets do
		packetIds[packet.id] = true
	end
	local appended: { ReviewDecision } = {}
	for _, draft in drafts do
		local decision = Review.decision(draft)
		if not packetIds[decision.packetId] then
			error(("Generate continueReview decision names unknown packet %q"):format(decision.packetId), 2)
		end
		table.insert(appended, decision)
	end

	local records: { StageRecord } = {}
	local attached = 0
	for position, record in source.stages do
		local stage = plan.stages[position]
		if stage == nil or record.id ~= stage.id or record.status ~= "returned" or stage.mutation then
			error("Generate continueReview may continue only completed non-mutation stages", 2)
		end
		local copy = table.clone(record)
		copy.decisions = table.clone(record.decisions)
		if record.reviewPacket ~= nil then
			for _, decision in appended do
				if decision.packetId == (record.reviewPacket :: ReviewPacket).id then
					table.insert(copy.decisions, decision)
					attached += 1
				end
			end
		end
		table.insert(records, copy)
	end
	if #records ~= #plan.stages or attached ~= #appended then
		error("Generate continueReview could not bind every decision to its review stage", 2)
	end

	local decisions = table.clone(source.decisions)
	for _, decision in appended do
		table.insert(decisions, decision)
	end
	local checkpoint: Checkpoint = {
		schemaVersion = 1,
		briefFingerprint = source.briefFingerprint,
		planFingerprint = source.planFingerprint,
		nextStage = #plan.stages + 1,
		records = records,
		artifacts = table.clone(source.artifacts),
		reviewPackets = table.clone(source.reviewPackets),
		decisions = decisions,
		derivations = table.clone(source.derivations),
		costMicros = source.costMicros,
	}
	local calls = 0
	local host: Host = {
		name = source.host,
		environment = table.clone(source.environment),
		capabilities = {},
		now = function(): number
			calls += 1
			return (source.startedMicros + if calls == 1 then 0 else source.durationMicros) / 1e6
		end,
		runStage = function()
			error("Generate continueReview attempted to replay production", 2)
		end,
		compensate = nil,
	}
	local integrated = executeInternal(brief, plan, host, {
		capabilities = {},
		destinations = {},
		mutationBudget = 0,
		costBudgetMicros = source.costMicros,
	}, checkpoint)
	return Canonical.copy(integrated) :: Receipt
end

return {
	RECEIPT_SCHEMA_VERSION = RECEIPT_SCHEMA_VERSION,
	receiptFingerprint = receiptFingerprint,
	execute = execute,
	continueReview = continueReview,
}
