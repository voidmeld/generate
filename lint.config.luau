--!strict

return {
	lute = {
		lint = {
			ignores = { "build/**", ".lute/**", ".lpm/**", "vendor/**" },
			globals = {},
			rulepaths = {
				".lpm/verify@35c5590efa9fdb9fc12319a7bc9455a81c2d1970/src/checks/lint-rules/global_table_usage.luau",
			},
			ruleconfigs = {
				global_table_usage = { options = { allow = { "tests/harness/init.luau" } } },
				global_function_in_scope = { off = true },
				unused_variable = { off = true },
			},
		},
	},
}
