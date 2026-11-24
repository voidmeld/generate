--!strict

return {
	package = {
		name = "voidmeld/generate",
		version = "0.1.1",
		files = {
			"src/**",
			"docs/**",
			"/.agents/skills/generate/**",
			"/README.md",
			"/CHANGELOG.md",
			"/LICENSE",
			"/PROVENANCE.md",
		},
		metadata = {
			description = "Deterministic asset records, image preparation and Roblox delivery for Luau.",
			license = "MIT",
			repository = "https://github.com/voidmeld/generate",
			exports = {
				Generate = "src/core",
				Image = "src/image",
				Roblox = "src/roblox",
			},
		},
		dependencies = {},
		dev_dependencies = {
			verify = {
				sourceKind = "github",
				source = "https://github.com/voidmeld/verify",
				rev = "2e8cedeb260dd61d29b6f4be51a5fc250254e80b",
			},
		},
	},
}
