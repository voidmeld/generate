--!strict

export type Rule = {
	pattern: string,
	why: string,
	exempt: { [string]: string }?,
}

local productMaterial: { Rule } = {
	{
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
	{ pattern = "rbxthumb://", why = "product asset identifier" },

	{
		pattern = "%f[%w_]placeId%s*=%s*[1-9]%d*",
		why = "product place identifier",
		exempt = { ["tests/roblox-publication.verify.luau:placeId = 222"] = "synthetic permission destination" },
	},
	{
		pattern = "%f[%w_]universeId%s*=%s*[1-9]%d*",
		why = "product universe identifier",
		exempt = { ["tests/roblox-publication.verify.luau:universeId = 111"] = "synthetic publication destination" },
	},
}

return {
	leakage = productMaterial,
	selfPath = "tools/lib/denylist.luau",
}
