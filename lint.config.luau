--!strict

return {
	lute = {
		lint = {
			ignores = { "build/**", ".lute/**", ".lpm/**", "vendor/**" },
			globals = {},
			rulepaths = {
				".lpm/verify@2e8cedeb260dd61d29b6f4be51a5fc250254e80b/src/checks/lint-rules/global_table_usage.luau",
			},
			ruleconfigs = {
				global_table_usage = { options = { allow = { "tests/harness/init.luau" } } },
				global_function_in_scope = { off = true },
				unused_variable = { off = true },
			},
		},
	},
}
