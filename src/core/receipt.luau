--!strict

local Canonical = require "./canonical"
local Types = require "./types"

type Receipt = Types.Receipt

local function receiptFingerprint(receipt: Receipt): string
	return Canonical.fingerprint {
		schemaVersion = receipt.schemaVersion,
		id = receipt.id,
		briefId = receipt.briefId,
		briefFingerprint = receipt.briefFingerprint,
		planFingerprint = receipt.planFingerprint,
		reviewContract = receipt.reviewContract,
		provenanceContract = receipt.provenanceContract,
		host = receipt.host,
		environment = receipt.environment,
		status = receipt.status,
		startedMicros = receipt.startedMicros,
		durationMicros = receipt.durationMicros,
		stages = receipt.stages,
		compensations = receipt.compensations,
		artifacts = receipt.artifacts,
		reviewPackets = receipt.reviewPackets,
		decisions = receipt.decisions,
		reviews = receipt.reviews,
		derivations = receipt.derivations,
		limitations = receipt.limitations,
		costMicros = receipt.costMicros,
		checkpoint = receipt.checkpoint,
		publication = receipt.publication,
	}
end

return { fingerprint = receiptFingerprint }
