--!strict

local Canonical = require "./canonical"
local ReceiptModel = require "./receipt"
local Secret = require "./secret"
local Types = require "./types"

type Destination = Types.Destination
type HostVerification = Types.HostVerification
type PublicationRecord = Types.PublicationRecord
type Receipt = Types.Receipt

local SCHEMA_VERSION = 1
local HOST_VERIFICATION_SCHEMA_VERSION = 1

local STATES: { [string]: boolean } = {
	pending = true,
	confirmed = true,
	reconciled = true,
	stopped = true,
}

local function nonempty(value: unknown): boolean
	return type(value) == "string" and value ~= ""
end

local function sha256(value: unknown): boolean
	return type(value) == "string" and #value == 64 and string.match(value :: string, "^[0-9a-f]+$") ~= nil
end

local function destination(draft: unknown, hostVerification: unknown): (Destination?, boolean?)
	if draft == nil then
		if hostVerification ~= nil and hostVerification ~= false then
			error("Generate brief delivery.hostVerification requires delivery.destination", 3)
		end
		return nil, nil
	end
	if type(draft) ~= "table" then
		error("Generate brief delivery.destination must be a table", 3)
	end
	local fields = draft :: { [unknown]: unknown }
	for key in fields do
		if key ~= "adapter" and key ~= "descriptor" then
			error(("Generate brief delivery.destination carries unknown field %s"):format(tostring(key)), 3)
		end
	end
	if not nonempty(fields.adapter) or string.match(fields.adapter :: string, "^[a-z][a-z0-9%-]*$") == nil then
		error("Generate brief delivery.destination.adapter must name one adapter in lowercase", 3)
	end
	if type(fields.descriptor) ~= "table" then
		error("Generate brief delivery.destination.descriptor must be a data table", 3)
	end
	Secret.validate(fields.descriptor, "Generate brief delivery.destination.descriptor")
	if hostVerification ~= nil and type(hostVerification) ~= "boolean" then
		error("Generate brief delivery.hostVerification must be a boolean when declared", 3)
	end
	return {
		adapter = fields.adapter :: string,
		descriptor = Canonical.copy(fields.descriptor) :: { [string]: unknown },
	},
		hostVerification == true
end

local function verificationFault(verification: HostVerification): string?
	if type(verification) ~= "table" then
		return "publication record verification must be a table when declared"
	end
	if verification.schemaVersion ~= HOST_VERIFICATION_SCHEMA_VERSION then
		return ("publication record verification schemaVersion must be %d"):format(HOST_VERIFICATION_SCHEMA_VERSION)
	end
	if type(verification.requested) ~= "boolean" then
		return "publication record verification must say whether it was requested"
	end
	if verification.disposition ~= "verified" and verification.disposition ~= "refused" then
		return "publication record verification must name verified or refused"
	end
	if not nonempty(verification.contentId) then
		return "publication record verification must name the verified content id"
	end
	if not nonempty(verification.hostBuild) then
		return "publication record verification must name the host build"
	end
	if type(verification.windowSeconds) ~= "number" or verification.windowSeconds <= 0 then
		return "publication record verification must name a positive observation window"
	end
	if type(verification.measurements) ~= "table" then
		return "publication record verification must carry its measurements, even when empty"
	end
	if type(verification.diagnostics) ~= "table" then
		return "publication record verification must report its scanned diagnostics, even when empty"
	end
	if verification.disposition == "verified" then
		if verification.refusalReason ~= nil then
			return "publication record verification must carry no refusal reason when verified"
		end
		if not nonempty(verification.observationFingerprint) then
			return "publication record verification must carry an observation fingerprint when verified"
		end
	elseif not nonempty(verification.refusalReason) then
		return "publication record verification must name one refusal reason when refused"
	end
	return nil
end

local function recordFault(record: PublicationRecord): string?
	if type(record) ~= "table" then
		return "publication record must be a table"
	end
	if record.schemaVersion ~= SCHEMA_VERSION then
		return ("publication record schemaVersion must be %d"):format(SCHEMA_VERSION)
	end
	if not nonempty(record.disposition) or string.match(record.disposition, "^[a-z][a-z%-]*$") == nil then
		return "publication record must name one disposition"
	end
	if not STATES[record.state] then
		return "publication record must be pending, confirmed, reconciled or stopped; no state means try again"
	end
	if record.quarantined ~= true then
		return "publication record must keep the content quarantined; promotion is the consumer's decision"
	end
	if type(record.dryRun) ~= "boolean" then
		return "publication record must say whether it was a dry run"
	end
	if type(record.placeholder) ~= "boolean" then
		return "publication record must say whether it is a placeholder"
	end
	if type(record.credential) ~= "table" then
		return "publication record must name the credential it spent"
	end
	if not nonempty(record.credential.name) then
		return "publication record credential must carry the credential name"
	end
	if record.credential.exposed ~= false then
		return "publication record must attest that no credential value was exposed"
	end
	if record.contentId ~= nil and not nonempty(record.contentId) then
		return "publication record content id must be non-empty when declared"
	end
	if record.writeAheadDigest ~= nil and not sha256(record.writeAheadDigest) then
		return "publication record write-ahead digest must be lowercase SHA-256"
	end
	if record.artifactDigest ~= nil and not sha256(record.artifactDigest) then
		return "publication record artifact digest must be lowercase SHA-256"
	end
	if record.idempotencyKey ~= nil and not sha256(record.idempotencyKey) then
		return "publication record idempotency key must be lowercase SHA-256"
	end
	if
		type(record.attemptsAuthorised) ~= "number"
		or type(record.attemptsMade) ~= "number"
		or record.attemptsMade > record.attemptsAuthorised
	then
		return "publication record attempts made may never exceed attempts authorised"
	end
	if type(record.stages) ~= "table" or #record.stages == 0 then
		return "publication record must report its stages"
	end
	if type(record.facts) ~= "table" then
		return "publication record must carry its adapter facts, even when empty"
	end
	if record.reconciliation ~= nil then
		local reconciled = record.reconciliation
		if
			not nonempty(reconciled.sourceReceiptFingerprint)
			or not nonempty(reconciled.evidencePath)
			or not sha256(reconciled.evidenceDigest)
		then
			return "publication reconciliation requires a bound source and SHA-256 evidence"
		end
	elseif record.state == "reconciled" then
		return "a reconciled publication record requires its reconciliation evidence"
	end
	local request = record.verificationRequest
	local completion = record.verificationCompletion
	if request ~= nil then
		if type(request) ~= "table" or request.schemaVersion ~= 1 then
			return "publication verificationRequest must name schemaVersion 1"
		end
		local payload: Types.HostVerificationRequestPayload & { fingerprint: string? } = table.clone(request)
		payload.fingerprint = nil
		if request.fingerprint ~= Canonical.fingerprint(payload) then
			return "publication verificationRequest fingerprint changed"
		end
		if
			request.contentId ~= record.contentId
			or request.version ~= record.version
			or request.artifactId ~= record.artifactId
			or request.artifactDigest ~= record.artifactDigest
			or request.grantId ~= record.grantId
			or request.grantFingerprint ~= record.grantFingerprint
			or request.writeAheadDigest ~= record.writeAheadDigest
		then
			return "publication verificationRequest must bind the exact publication identity"
		end
	end
	if completion ~= nil then
		if
			type(completion) ~= "table"
			or request == nil
			or completion.requestFingerprint ~= request.fingerprint
			or not nonempty(completion.pendingReceiptFingerprint)
			or not nonempty(completion.evidencePath)
			or not sha256(completion.evidenceDigest)
			or not nonempty(completion.stateFingerprint)
			or record.verification == nil
		then
			return "publication verificationCompletion requires its request, evidence and observation"
		end
		if record.verification ~= nil and record.verification.hostBuild ~= request.hostBuild then
			return "publication verification must name the host build of its request"
		end
	end
	if record.verificationRebindings ~= nil then
		if request == nil or #record.verificationRebindings == 0 then
			return "publication verification rebindings require a request and nonempty lineage"
		end
		for _, previous in record.verificationRebindings do
			if
				not nonempty(previous.receiptFingerprint)
				or not nonempty(previous.requestFingerprint)
				or not nonempty(previous.hostBuild)
			then
				return "publication verification rebindings require prior receipt request and build identities"
			end
		end
	end
	if record.verification ~= nil then
		return verificationFault(record.verification)
	end
	return nil
end

local function hostVerified(receipt: Receipt): boolean
	local record = receipt.publication
	if receipt.status ~= "accepted" or record == nil then
		return false
	end
	if
		record.state ~= "confirmed"
		or record.dryRun ~= false
		or record.placeholder ~= false
		or not nonempty(record.contentId)
	then
		return false
	end
	if record.verificationRequest ~= nil then
		local source = table.clone(receipt)
		source.publication = nil
		if record.verificationRequest.sourceReceiptFingerprint ~= ReceiptModel.fingerprint(source) then
			return false
		end
		if record.verificationCompletion == nil then
			return false
		end
	end
	local verification = record.verification
	if verification == nil or verification.disposition ~= "verified" or verification.contentId ~= record.contentId then
		return false
	end
	if recordFault(record) ~= nil then
		return false
	end
	return receipt.fingerprint == ReceiptModel.fingerprint(receipt)
end

local function integrate(receipt: Receipt, record: PublicationRecord): Receipt
	local fault = recordFault(record)
	if fault ~= nil then
		error("Generate publication record integration refuses an invalid publication record: " .. fault, 3)
	end
	local safe = pcall(Secret.validate, {
		readback = record.readback,
		attempts = record.attempts,
		compensations = record.compensations,
		stages = record.stages,
		detail = record.detail,
		facts = record.facts,
		verification = record.verification,
		verificationRequest = record.verificationRequest,
		verificationCompletion = record.verificationCompletion,
		verificationRebindings = record.verificationRebindings,
		reconciliation = record.reconciliation,
	}, "Generate publication record")
	if not safe then
		error(
			"Generate publication record integration refuses a publication record carrying secret-shaped or non-data state",
			3
		)
	end
	local integrated = Canonical.copy(receipt) :: Receipt
	integrated.publication = Canonical.copy(record) :: PublicationRecord
	integrated.fingerprint = ReceiptModel.fingerprint(integrated)
	return integrated
end

local function attach(receipt: Receipt, record: PublicationRecord): Receipt
	if receipt.fingerprint ~= ReceiptModel.fingerprint(receipt) then
		error("Generate attachPublication requires an unchanged receipt", 2)
	end
	if receipt.publication ~= nil and receipt.publication.dryRun ~= true then
		error("Generate attachPublication refuses a receipt that already records a publication attempt", 2)
	end
	return integrate(receipt, record)
end

local function reconcile(receipt: Receipt, record: PublicationRecord): Receipt
	if receipt.fingerprint ~= ReceiptModel.fingerprint(receipt) then
		error("Generate reconcilePublication requires an unchanged receipt", 2)
	end
	local prior = receipt.publication
	if prior == nil or prior.state ~= "stopped" or prior.dryRun or prior.placeholder then
		error("Generate reconcilePublication requires a stopped publication record", 2)
	end
	local reconciliation = record.reconciliation
	if
		reconciliation == nil
		or reconciliation.sourceReceiptFingerprint ~= receipt.fingerprint
		or record.state ~= "reconciled"
		or record.readback == nil
		or record.version == nil
		or prior.reconciliation ~= nil
	then
		error("Generate reconcilePublication requires read-only evidence bound to the original receipt", 2)
	end
	local attempt = prior.attempts[1]
	local compensation = prior.compensations[1]
	if
		prior.attemptsMade ~= 1
		or prior.attemptsAuthorised ~= 1
		or #prior.attempts ~= 1
		or attempt.action ~= "create"
		or attempt.state ~= "failed-readback"
		or #prior.compensations ~= 1
		or compensation.status ~= "failed"
		or prior.verification ~= nil
		or prior.verificationRequest ~= nil
		or prior.verificationCompletion ~= nil
	then
		error(
			"Generate reconcilePublication requires one failed-readback create with failed compensation and no verification",
			2
		)
	end
	local expected = Canonical.copy(prior) :: PublicationRecord
	expected.disposition = record.disposition
	expected.state = record.state
	expected.detail = record.detail
	expected.version = record.version
	expected.readback = record.readback
	expected.reconciliation = reconciliation
	if
		(prior.version ~= nil and prior.version ~= record.version)
		or Canonical.fingerprint(record) ~= Canonical.fingerprint(expected)
	then
		error("Generate reconcilePublication must preserve the original attempts compensation journal and stages", 2)
	end
	return integrate(receipt, record)
end

local function confirm(receipt: Receipt, record: PublicationRecord): Receipt
	if receipt.fingerprint ~= ReceiptModel.fingerprint(receipt) then
		error("Generate confirmPublication requires an unchanged receipt", 2)
	end
	local pending = receipt.publication
	if pending == nil or (pending.state ~= "pending" and pending.state ~= "reconciled") then
		error("Generate confirmPublication requires a receipt whose publication record is pending or reconciled", 2)
	end
	if pending.verificationRequest ~= nil then
		local source = table.clone(receipt)
		source.publication = nil
		if pending.verificationRequest.sourceReceiptFingerprint ~= ReceiptModel.fingerprint(source) then
			error("Generate confirmPublication requires the original deferred source receipt", 2)
		end
		if record.verificationRebindings ~= nil and record.verificationCompletion == nil then
			local priorFault = recordFault(pending)
			if priorFault ~= nil then
				error("Generate confirmPublication build rebind refuses invalid prior publication: " .. priorFault, 2)
			end
			local requested = record.verificationRequest
			if
				pending.state ~= "pending"
				or pending.verification ~= nil
				or pending.verificationCompletion ~= nil
				or requested == nil
				or type(requested.hostBuild) ~= "string"
				or requested.hostBuild == ""
				or requested.hostBuild == pending.verificationRequest.hostBuild
			then
				error(
					"Generate confirmPublication build rebind requires an uncompleted pending verification and a different build",
					2
				)
			end
			local expected = Canonical.copy(pending) :: PublicationRecord
			local rebound = Canonical.copy(pending.verificationRequest) :: Types.HostVerificationRequest
			rebound.hostBuild = requested.hostBuild
			local payload: Types.HostVerificationRequestPayload & { fingerprint: string? } = table.clone(rebound)
			payload.fingerprint = nil
			rebound.fingerprint = Canonical.fingerprint(payload)
			expected.verificationRequest = rebound
			expected.verificationRebindings = expected.verificationRebindings or {}
			table.insert(assert(expected.verificationRebindings), {
				receiptFingerprint = receipt.fingerprint,
				requestFingerprint = pending.verificationRequest.fingerprint,
				hostBuild = pending.verificationRequest.hostBuild,
			})
			if Canonical.fingerprint(record) ~= Canonical.fingerprint(expected) then
				error(
					"Generate confirmPublication build rebind must preserve every protected request field transaction and prior lineage",
					2
				)
			end
			return integrate(receipt, record)
		end
		local completion = record.verificationCompletion
		if
			completion == nil
			or record.verification == nil
			or completion.requestFingerprint ~= pending.verificationRequest.fingerprint
			or completion.pendingReceiptFingerprint ~= receipt.fingerprint
		then
			error(
				"Generate confirmPublication requires a completion bound to the pending verification request and receipt",
				2
			)
		end
		local expected = Canonical.copy(pending) :: PublicationRecord
		expected.disposition = record.disposition
		expected.state = "confirmed"
		expected.detail = record.verification.detail
		expected.verification = record.verification
		expected.verificationCompletion = completion
		table.insert(expected.stages, {
			id = "complete-host-verification",
			status = if record.verification.disposition == "verified" then "passed" else "refused",
			detail = record.verification.detail,
		})
		if Canonical.fingerprint(record) ~= Canonical.fingerprint(expected) then
			error("Generate confirmPublication must preserve the deferred request and original publication history", 2)
		end
	end
	return integrate(receipt, record)
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	HOST_VERIFICATION_SCHEMA_VERSION = HOST_VERIFICATION_SCHEMA_VERSION,
	destination = destination,
	recordFault = recordFault,
	hostVerified = hostVerified,
	attach = attach,
	confirm = confirm,
	reconcile = reconcile,
}
