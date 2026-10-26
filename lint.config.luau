--!strict

return {
	lute = {
		lint = {
			ignores = { "build/**", ".lute/**", "vendor/**" },
			globals = {},
			rulepaths = {
				"tools/lint-rules/global_table_usage.luau",
			},
			ruleconfigs = {
				global_function_in_scope = { off = true },
				unused_variable = { off = true },
			},
		},
	},
}
