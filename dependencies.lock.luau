--!strict

return table.freeze {
	schemaVersion = 1,
	dependencies = {
		table.freeze {
			name = "verify",
			repository = "https://github.com/voidmeld/verify.git",
			commit = "4d6fe22a7b5261c4925889b3449fcf9e60d36f28",
			tree = "ee0a7007acbf7b4942eb785d3a2d703946848674",
			rights = "MIT",
			surfaces = {
				{ root = "src", role = "verification" },
			},
		},
	},
}
