--!strict

export type Quota = {
	name: string,
	value: number,
	quota: number,
}

export type QuotaKind = {
	name: string,
	kind: string,
	allowedKinds: { string },
}

export type QuotaDraft = {
	subject: string,
	quotas: { Quota },
	kind: QuotaKind?,
}

export type QuotaOutcome = {
	name: string,
	value: number,
	quota: number,
	over: boolean,
}

export type QuotaKindOutcome = {
	name: string,
	kind: string,
	allowed: boolean,
}

export type QuotaStatus = "within" | "over"

export type QuotaReport = {
	subject: string,
	outcomes: { QuotaOutcome },
	kind: QuotaKindOutcome?,
	status: QuotaStatus,
	overruns: { string },
}

local function measure(name: string, value: number, quota: number): QuotaOutcome
	if name == "" then
		error("Generate quota requires a named measure", 2)
	end
	if value ~= value or quota ~= quota then
		error(("Generate quota %q refuses a value or quota that is not a number"):format(name), 2)
	end
	if quota < 0 then
		error(("Generate quota %q declares a negative ceiling"):format(name), 2)
	end
	return {
		name = name,
		value = value,
		quota = quota,
		over = value > quota,
	}
end

local function kindAllowed(kind: string, allowedKinds: { string }): boolean
	for _, permitted in allowedKinds do
		if permitted == kind then
			return true
		end
	end
	return false
end

local function evaluate(draft: QuotaDraft): QuotaReport
	if draft.subject == "" then
		error("Generate quota requires an explicit subject", 2)
	end
	if #draft.quotas == 0 and draft.kind == nil then
		error(("Generate quota subject %q declares nothing to evaluate"):format(draft.subject), 2)
	end
	local seen: { [string]: boolean } = {}
	local outcomes: { QuotaOutcome } = {}
	local overruns: { string } = {}
	for _, entry in draft.quotas do
		if seen[entry.name] then
			error(("Generate quota subject %q declares measure %q twice"):format(draft.subject, entry.name), 2)
		end
		seen[entry.name] = true
		local outcome = measure(entry.name, entry.value, entry.quota)
		table.insert(outcomes, outcome)
		if outcome.over then
			table.insert(overruns, outcome.name)
		end
	end
	local kindOutcome: QuotaKindOutcome? = nil
	if draft.kind ~= nil then
		local declared = draft.kind :: QuotaKind
		if declared.name == "" then
			error(("Generate quota subject %q declares an unnamed kind"):format(draft.subject), 2)
		end
		if seen[declared.name] then
			error(("Generate quota subject %q declares measure %q twice"):format(draft.subject, declared.name), 2)
		end
		if #declared.allowedKinds == 0 then
			error(("Generate quota subject %q allows no value for kind %q"):format(draft.subject, declared.name), 2)
		end
		local allowed = kindAllowed(declared.kind, declared.allowedKinds)
		kindOutcome = {
			name = declared.name,
			kind = declared.kind,
			allowed = allowed,
		}
		if not allowed then
			table.insert(overruns, declared.name .. ":" .. declared.kind)
		end
	end
	table.sort(overruns)
	return {
		subject = draft.subject,
		outcomes = outcomes,
		kind = kindOutcome,
		status = if #overruns == 0 then "within" else "over",
		overruns = overruns,
	}
end

return {
	measure = measure,
	kindAllowed = kindAllowed,
	evaluate = evaluate,
}
