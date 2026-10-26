--!strict

return table.freeze {
	schemaVersion = 1,
	dependencies = {
		table.freeze {
			name = "verify",
			repository = "https://github.com/voidmeld/verify.git",
			commit = "6aa3cab153f84e94c30370aee45158cff29c2959",
			tree = "eb137e511dfacb875f4777a1eee4713f4135255b",
			rights = "MIT",
			surfaces = {
				{ root = "src", role = "verification" },
			},
		},
	},
}
