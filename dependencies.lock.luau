--!strict

return table.freeze {
	schemaVersion = 1,
	dependencies = {
		table.freeze {
			name = "verify",
			repository = "https://github.com/voidmeld/verify.git",
			commit = "266e8ee2b51277e0109ee0002f8e6c27f0bb7e01",
			tree = "7ad4b39ad4496f946c517500bffbcc9b6c6cc013",
			rights = "MIT",
			surfaces = {
				{ root = "src", role = "verification" },
			},
		},
	},
}
