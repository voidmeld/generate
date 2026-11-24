--!strict

return {
	package = {
		name = "voidmeld/generate",
		version = "0.1.0",
		files = {
			"src/**",
			"docs/**",
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
				rev = "35c5590efa9fdb9fc12319a7bc9455a81c2d1970",
			},
		},
	},
}
