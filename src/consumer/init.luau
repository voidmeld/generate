--!strict

export type Finding = {
	code: string,
	path: string,
	message: string,
	fix: string,
}

local function contains(source: string, needle: string): boolean
	return string.find(source, needle, 1, true) ~= nil
end

export type Ruleset = "roblox"

local function robloxFindings(add: (code: string, message: string, fix: string) -> (), source: string)
	if contains(source, "GenerationService:") then
		add(
			"RBX008",
			"brief contains execution spelling GenerationService:",
			"move tool execution into an adapter supplied by the consumer"
		)
	end
	if contains(source, "rbxassetid://") then
		add(
			"RBX010",
			"brief uses a raw Roblox asset id as authored input",
			"resolve a stable semantic asset id through the consumer manifest"
		)
	end
	if contains(source, "set_active_studio") or contains(source, "list_roblox_studios") then
		add(
			"RBX011",
			"authored production source attempts to select or discover a Studio",
			"accept one brief-bound native-agent task grant and target its exact studio_id"
		)
	end
	if contains(source, "studio_id =") or contains(source, "studioId =") then
		add(
			"RBX012",
			"production source persists an ephemeral Studio identity",
			"inject the brief-bound task grant only for the native agent call and retain its task identity in the receipt"
		)
	end
	if contains(source, "maxSizeStuds =") then
		add(
			"RBX013",
			"production brief declares its size in studs",
			"declare constraints.maxSize in metres and convert it in the Roblox adapter"
		)
	end
end

local function scanSource(path: string, source: string, rulesets: { Ruleset }?): { Finding }
	local findings: { Finding } = {}
	local function add(code: string, message: string, fix: string)
		table.insert(findings, { code = code, path = path, message = message, fix = fix })
	end
	if not contains(source, "Generate.brief") then
		add("GEN001", "production brief does not construct a Generate brief", "return Generate.brief { ... }")
	end
	local required: { [string]: string } = {
		id = "GEN002",
		intent = "GEN003",
		review = "GEN004",
		delivery = "GEN005",
	}
	for field, code in required do
		if not contains(source, field .. " =") then
			add(code, "production brief omits " .. field, "declare the " .. field .. " contract explicitly")
		end
	end
	if not contains(source, "semanticId =") then
		add("GEN006", "production brief has no semantic delivery identity", "declare delivery.semanticId")
	end
	if not contains(source, "views =") then
		add("GEN007", "production brief has no canonical review views", "declare review.views")
	end
	if contains(source, "requiredApprovals") then
		add(
			"GEN014",
			"production brief counts approvals instead of binding a review",
			"bind exactly one independent reviewer to the packet"
		)
	end
	if contains(source, "review =") and not contains(source, "rubricFingerprint =") then
		add(
			"GEN015",
			"review contract names a rubric without pinning its fingerprint",
			"declare review.rubricFingerprint so rubric drift invalidates a decision"
		)
	end
	if contains(source, "Generate.brief") and not contains(source, "provenance =") then
		add(
			"GEN017",
			"production brief declares no provenance contract",
			"declare provenance.requireParentLineage and provenance.requiredRightsFacts"
		)
	end
	for _, forbidden in { "rightsPolicy", "rightsCleared", "licenseGranted", "rightsApproved" } do
		if contains(source, forbidden) then
			add(
				"GEN018",
				"production source decides rights policy inside Generate through " .. forbidden,
				"record known/unknown rights facts on the derivation and keep the rights decision in the consuming product"
			)
		end
	end
	if contains(source, 'state = "known"') and not contains(source, "value =") then
		add(
			"GEN019",
			"rights fact claims knowledge without recording the fact",
			'give every known rights fact an exact value, or record state = "unknown"'
		)
	end
	for _, forbidden in { "API_KEY", "apiKey =", "token =", "Authorization =", "process.run", "http.request" } do
		if contains(source, forbidden) then
			add(
				"GEN008",
				"brief contains authority or execution spelling " .. forbidden,
				"move credentials and tool execution into an adapter supplied by the consumer"
			)
		end
	end
	if contains(source, 'operation = "publish"') and not contains(source, 'rollback = "required"') then
		add(
			"GEN009",
			"publication lacks an explicit rollback contract",
			'declare mutation = true and rollback = "required"'
		)
	end
	if
		(
			contains(source, 'kind = "rigid-mesh"')
			or contains(source, 'kind = "modular-mesh"')
			or contains(source, 'kind = "skinned-mesh"')
		) and not contains(source, "maxSize =")
	then
		add(
			"GEN013",
			"spatial production brief has no maximum bounds with an explicit unit",
			'declare constraints.maxSize = { x = ..., y = ..., z = ..., unit = "m" }'
		)
	end
	local selected: { Ruleset } = rulesets or {}
	for _, ruleset in selected do
		if ruleset == "roblox" then
			robloxFindings(add, source)
		else
			error("Generate consumer scanSource does not know ruleset " .. tostring(ruleset), 2)
		end
	end
	return findings
end

return {
	RULESETS = { "roblox" } :: { Ruleset },
	scanSource = scanSource,
}
