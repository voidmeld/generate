--!strict

local Denylist = require "../.lute/dependencies/verify/src/checks/denylist"
export type Rule = Denylist.Rule

local boundary: { Rule } = {}
for _, name in
	{
		"Roblox",
		"roblox",
		"Studio",
		"studs",
		"Studs",
		"universe",
		"Universe",
		"witness",
		"Witness",
		"mint",
		"Mint",
		"GenerationService",
		"Compose",
		"Verify",
		"@std/",
		"@lute/",
		"game.",
		"workspace",
		"os.clock",
		"process.run",
		"task.spawn",
	}
do
	table.insert(boundary, { allMatches = true, pattern = name, plain = true, why = "forbidden host/domain spelling" })
end

local productMaterial: { Rule } = {
	{
		allMatches = true,
		pattern = "rbxassetid://%d+",
		why = "product asset identifier",
		exempt = {
			["tests/asset-lane.lute.verify.luau:rbxassetid://909"] = "synthetic fixture content identifier",
			["tests/asset-lane.lute.verify.luau:rbxassetid://4242"] = "synthetic model reference fixture",
			["tests/asset-lane.lute.verify.luau:rbxassetid://777"] = "synthetic unexpected model reference",
			["tests/consumer.verify.luau:rbxassetid://1"] = "consumer diagnostic refusal fixture",
			["tests/roblox-publication.verify.luau:rbxassetid://9"] = "synthetic publication readback",
		},
	},
	{ allMatches = true, pattern = "rbxthumb://", why = "product asset identifier" },

	{
		allMatches = true,
		pattern = "%f[%w_]placeId%s*=%s*[1-9]%d*",
		why = "product place identifier",
		exempt = { ["tests/roblox-publication.verify.luau:placeId = 222"] = "synthetic permission destination" },
	},
	{
		allMatches = true,
		pattern = "%f[%w_]universeId%s*=%s*[1-9]%d*",
		why = "product universe identifier",
		exempt = { ["tests/roblox-publication.verify.luau:universeId = 111"] = "synthetic publication destination" },
	},
}

return {
	boundary = boundary,
	leakage = productMaterial,
	selfPath = "tools/checks-policy.luau",
}
