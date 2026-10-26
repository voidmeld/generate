--!strict

local Generate = require "../core"

type Certainty = Generate.Certainty
type ReviewDecisionDraft = Generate.ReviewDecisionDraft
type RubricIdentity = Generate.RubricIdentity
type Verdict = Generate.Verdict

export type Decode = (text: string) -> unknown

export type StreamContract = {
	threadEventType: string,
	threadIdField: string,
	answerEventType: string,
	answerItemType: string,
	actorPrefix: string,
}

export type StreamVerdict = {
	actor: string,
	threadId: string,
	verdict: Verdict,
	certainty: Certainty,
	reasons: { string },
}

export type PacketRef = {
	id: string,
	fingerprint: string,
	candidateFingerprint: string,
	evidenceFingerprint: string,
	rubric: RubricIdentity,
}

export type StreamOptions = {
	decode: Decode,
	contract: StreamContract,
	packet: PacketRef,
	streams: { string },
	role: string,
	modelFamily: string?,
	providerFamily: string?,
}

local VERDICTS: { [unknown]: boolean } = { approved = true, rejected = true, abstained = true }
local CERTAINTIES: { [unknown]: boolean } = { high = true, medium = true, low = true }

local function nonempty(value: unknown): boolean
	return type(value) == "string" and value ~= ""
end

local function contractFault(contract: StreamContract): string?
	if type(contract) ~= "table" then
		return "reviewer stream contract must be a table"
	end
	local named: { { name: string, value: unknown } } = {
		{ name = "threadEventType", value = contract.threadEventType },
		{ name = "threadIdField", value = contract.threadIdField },
		{ name = "answerEventType", value = contract.answerEventType },
		{ name = "answerItemType", value = contract.answerItemType },
	}
	for _, entry in named do
		if not nonempty(entry.value) then
			return ("reviewer stream contract must name %s"):format(entry.name)
		end
	end
	if type(contract.actorPrefix) ~= "string" then
		return "reviewer stream contract actorPrefix must be a string"
	end
	return nil
end

local function parse(decode: Decode, contract: StreamContract, stream: string): (StreamVerdict?, string?)
	local fault = contractFault(contract)
	if fault ~= nil then
		error("Generate " .. fault, 2)
	end
	if type(stream) ~= "string" then
		error("Generate reviewer stream must be the reviewer's raw output", 2)
	end
	local threadId: string? = nil
	local answer: string? = nil
	for line in string.gmatch(stream, "[^\r\n]+") do
		local ok, event = pcall(decode, line)
		if not ok or type(event) ~= "table" then
			continue
		end
		local record = event :: { [string]: unknown }
		if record.type == contract.threadEventType and nonempty(record[contract.threadIdField]) then
			local named = record[contract.threadIdField] :: string
			if threadId ~= nil and threadId ~= named then
				return nil, "reviewer stream names more than one thread"
			end
			threadId = named
		elseif
			record.type == contract.answerEventType
			and type(record.item) == "table"
			and (record.item :: { [string]: unknown }).type == contract.answerItemType
			and nonempty((record.item :: { [string]: unknown }).text)
		then
			answer = (record.item :: { [string]: unknown }).text :: string
		end
	end
	if threadId == nil or answer == nil then
		return nil, "reviewer stream carries no thread and terminal answer"
	end
	local ok, value = pcall(decode, answer :: string)
	if not ok or type(value) ~= "table" then
		return nil, "reviewer answer is not one exact JSON object"
	end
	local document = value :: { [string]: unknown }
	if not VERDICTS[document.verdict] or not CERTAINTIES[document.certainty] or type(document.reasons) ~= "table" then
		return nil, "reviewer answer has an invalid verdict, certainty, or reasons"
	end
	local reasons: { string } = {}
	for _, reason in document.reasons :: { unknown } do
		if not nonempty(reason) then
			return nil, "reviewer answer carries an empty or non-string reason"
		end
		table.insert(reasons, reason :: string)
	end
	if #reasons == 0 then
		return nil, "reviewer answer has an invalid verdict, certainty, or reasons"
	end
	return {
		actor = contract.actorPrefix .. (threadId :: string),
		threadId = threadId :: string,
		verdict = document.verdict :: Verdict,
		certainty = document.certainty :: Certainty,
		reasons = reasons,
	},
		nil
end

local function decisions(options: StreamOptions): ({ ReviewDecisionDraft }?, string?)
	if type(options) ~= "table" then
		error("Generate.reviewerStream.decisions expects its decoder, contract, packet, and streams", 2)
	end
	local packet = options.packet
	if
		type(packet) ~= "table"
		or not nonempty(packet.id)
		or not nonempty(packet.fingerprint)
		or not nonempty(packet.candidateFingerprint)
		or not nonempty(packet.evidenceFingerprint)
		or type(packet.rubric) ~= "table"
	then
		return nil, "reviewer streams carry no bound review packet"
	end
	if not nonempty(options.role) then
		error("Generate reviewer stream decisions require a reviewer role", 2)
	end
	if #options.streams ~= 1 then
		return nil, "review requires exactly one review stream"
	end
	local answer, fault = parse(options.decode, options.contract, options.streams[1])
	if answer == nil then
		return nil, fault
	end
	local read = answer :: StreamVerdict
	local draft: ReviewDecisionDraft = {
		packetId = packet.id,
		packetFingerprint = packet.fingerprint,
		candidateFingerprint = packet.candidateFingerprint,
		evidenceFingerprint = packet.evidenceFingerprint,
		rubric = packet.rubric,
		actor = read.actor,
		role = options.role,
		context = "independent",
		blind = true,
		modelFamily = options.modelFamily,
		providerFamily = options.providerFamily,
		certainty = read.certainty,
		verdict = read.verdict,
		reasons = read.reasons,
	}
	local valid = pcall(Generate.reviewDecision, draft)
	if not valid then
		return nil, "a review stream could not form a valid decision"
	end
	local drafts = { draft }
	return drafts, nil
end

return {
	parse = parse,
	decisions = decisions,
}
