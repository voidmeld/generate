--!strict

return {
	lute = {
		lint = {
			ignores = { "build/**", ".lute/**", "vendor/**" },
			globals = {},
			rulepaths = {
				".lute/dependencies/verify/src/checks/lint-rules/global_table_usage.luau",
			},
			ruleconfigs = {
				global_table_usage = { options = { allow = { "tests/harness/init.luau" } } },
				global_function_in_scope = { off = true },
				unused_variable = { off = true },
			},
		},
	},
}
