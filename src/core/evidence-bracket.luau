--!strict

export type EvidencePoseDraft = {
	id: string,
	evidenceId: string,
	parameters: { [string]: unknown }?,
}

export type EvidenceBracketDraft = {
	id: string,
	poses: { EvidencePoseDraft },
}

export type EvidencePose = {
	id: string,
	index: number,
	evidenceId: string,
	parameters: { [string]: unknown },
}

export type EvidenceBracket = {
	schemaVersion: number,
	id: string,
	poses: { EvidencePose },
}

export type EvidenceCapture = {
	pose: string,
	digest: string?,
	bytes: number?,
	posed: boolean?,
}

export type EvidenceManifestEntry = {
	index: number,
	pose: string,
	evidenceId: string,
	digest: string,
	bytes: number?,
}

export type EvidenceBracketReason =
	"empty-bracket"
	| "unknown-pose"
	| "duplicate-pose"
	| "out-of-order"
	| "short-bracket"
	| "unposed"
	| "missing-digest"
	| "unexpected-digest"

export type EvidenceBracketFault = {
	reason: EvidenceBracketReason,
	pose: string,
	index: number,
	detail: string,
}

export type EvidenceBracketStatus = "bound" | "refused"

export type EvidenceDigestRequirement = "required" | "absent"

export type EvidenceBracketReport = {
	bracketId: string,
	status: EvidenceBracketStatus,
	digests: EvidenceDigestRequirement,
	entries: { EvidenceManifestEntry },
	ordered: { string },
	faults: { EvidenceBracketFault },
	reasons: { string },
}

local SCHEMA_VERSION = 1

local REASONS: { [string]: EvidenceBracketReason } = {
	EMPTY = "empty-bracket",
	UNKNOWN = "unknown-pose",
	DUPLICATE = "duplicate-pose",
	OUT_OF_ORDER = "out-of-order",
	SHORT = "short-bracket",
	UNPOSED = "unposed",
	MISSING_DIGEST = "missing-digest",
	UNEXPECTED_DIGEST = "unexpected-digest",
}

local function plan(draft: EvidenceBracketDraft): EvidenceBracket
	if draft.id == "" then
		error("Generate evidence bracket requires an explicit bracket id", 2)
	end
	if #draft.poses == 0 then
		error(("Generate evidence bracket %q declares no pose"):format(draft.id), 2)
	end
	local claimed: { [string]: boolean } = {}
	local poses: { EvidencePose } = {}
	for index, entry in draft.poses do
		if entry.id == "" then
			error(("Generate evidence bracket %q declares an unnamed pose at position %d"):format(draft.id, index), 2)
		end
		if entry.evidenceId == "" then
			error(("Generate evidence bracket %q declares pose %q with no evidence id"):format(draft.id, entry.id), 2)
		end
		for _, name in { entry.id, entry.evidenceId } do
			if claimed[name] then
				error(("Generate evidence bracket %q claims the name %q twice"):format(draft.id, name), 2)
			end
			claimed[name] = true
		end
		table.insert(poses, {
			id = entry.id,
			index = index,
			evidenceId = entry.evidenceId,
			parameters = entry.parameters or {},
		})
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		id = draft.id,
		poses = poses,
	}
end

local function poseFor(bracket: EvidenceBracket, name: string): EvidencePose?
	for _, pose in bracket.poses do
		if pose.id == name or pose.evidenceId == name then
			return pose
		end
	end
	return nil
end

local function bind(
	bracket: EvidenceBracket,
	captures: { EvidenceCapture },
	digests: EvidenceDigestRequirement?
): EvidenceBracketReport
	local requirement: EvidenceDigestRequirement = digests or "required"
	local faults: { EvidenceBracketFault } = {}
	local entries: { EvidenceManifestEntry } = {}
	local ordered: { string } = {}
	local seen: { [string]: boolean } = {}

	local function fault(reason: EvidenceBracketReason, pose: string, index: number, detail: string)
		table.insert(faults, { reason = reason, pose = pose, index = index, detail = detail })
	end

	if #captures == 0 then
		fault(REASONS.EMPTY, "", 0, ("bracket %s was offered no capture"):format(bracket.id))
	end

	for index, capture in captures do
		local pose = poseFor(bracket, capture.pose)
		if pose == nil then
			fault(
				REASONS.UNKNOWN,
				capture.pose,
				index,
				("%s is not a pose bracket %s declares"):format(capture.pose, bracket.id)
			)
			continue
		end
		local selected = pose :: EvidencePose
		if seen[selected.id] then
			fault(REASONS.DUPLICATE, selected.id, index, ("pose %s is offered twice"):format(selected.id))
			continue
		end
		seen[selected.id] = true
		local expected = bracket.poses[index]
		local ok = true
		if expected == nil or expected.id ~= selected.id then
			ok = false
			fault(
				REASONS.OUT_OF_ORDER,
				selected.id,
				index,
				("position %d carries pose %s where bracket %s declares %s"):format(
					index,
					selected.id,
					bracket.id,
					if expected ~= nil then expected.id else "no pose"
				)
			)
		end
		if capture.posed == false then
			ok = false
			fault(REASONS.UNPOSED, selected.id, index, ("pose %s reports that it never posed"):format(selected.id))
		end
		local digest = capture.digest or ""
		if requirement == "required" and digest == "" then
			ok = false
			fault(
				REASONS.MISSING_DIGEST,
				selected.id,
				index,
				("pose %s carries no evidence digest"):format(selected.id)
			)
		end
		if requirement == "absent" and digest ~= "" then
			ok = false
			fault(
				REASONS.UNEXPECTED_DIGEST,
				selected.id,
				index,
				("pose %s carries a digest this bracket does not bind"):format(selected.id)
			)
		end
		if ok then
			table.insert(entries, {
				index = index,
				pose = selected.id,
				evidenceId = selected.evidenceId,
				digest = digest,
				bytes = capture.bytes,
			})
			table.insert(ordered, if requirement == "required" then selected.id .. ":" .. digest else selected.id)
		end
	end

	if #captures > 0 then
		local missing: { string } = {}
		for _, pose in bracket.poses do
			if not seen[pose.id] then
				table.insert(missing, pose.id)
			end
		end
		if #missing > 0 then
			fault(
				REASONS.SHORT,
				missing[1],
				#captures,
				("bracket %s was offered %d of its %d poses and is missing %s"):format(
					bracket.id,
					#captures,
					#bracket.poses,
					table.concat(missing, ", ")
				)
			)
		end
	end

	local reasons: { string } = {}
	for _, entry in faults do
		table.insert(reasons, entry.detail)
	end
	return {
		bracketId = bracket.id,
		status = if #faults > 0 then "refused" else "bound",
		digests = requirement,
		entries = if #faults > 0 then {} else entries,
		ordered = if #faults > 0 then {} else ordered,
		faults = faults,
		reasons = reasons,
	}
end

local function manifest(report: EvidenceBracketReport): { EvidenceManifestEntry }
	if report.status ~= "bound" then
		error(
			("Generate evidence bracket %s has no manifest: %s"):format(
				report.bracketId,
				table.concat(report.reasons, "; ")
			),
			2
		)
	end
	return report.entries
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	REASONS = REASONS,
	plan = plan,
	poseFor = poseFor,
	bind = bind,
	manifest = manifest,
}
