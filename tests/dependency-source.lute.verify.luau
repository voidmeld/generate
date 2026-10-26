--!strict

local Test = require "./harness"
local fs = require "@std/fs"
local process = require "@lute/process"

local describe, it, expect = Test.describe, Test.it, Test.expect

local STAGE = "build/dependency-source-spec"
local REPOSITORY = "https://github.com/voidmeld/verify.git"
local DISGUISED_REPOSITORY = "https://mirror.invalid/verify.git"

local function trim(value: string): string
	return string.match(value, "^%s*(.-)%s*$") or ""
end

local function isolatedEnvironment(): { [string]: string }
	local out: { [string]: string } = {}
	for name, value in process.env do
		if
			name ~= "GIT_CONFIG_COUNT"
			and string.match(name, "^GIT_CONFIG_KEY_%d+$") == nil
			and string.match(name, "^GIT_CONFIG_VALUE_%d+$") == nil
		then
			out[name] = value
		end
	end
	out.GIT_CONFIG_COUNT = "0"
	return out
end

local function run(argv: { string }, cwd: string, environment: { [string]: string }): (boolean, string)
	local result = process.run(argv, { cwd = cwd, env = environment })
	return result.ok, result.stdout .. result.stderr
end

local function git(path: string, environment: { [string]: string }, ...: string): string
	local argv = { "git", "-C", path }
	for index = 1, select("#", ...) do
		table.insert(argv, (select(index, ...)))
	end
	local ok, output = run(argv, process.cwd(), environment)
	if not ok then
		error("dependency source fixture: git failed: " .. output, 0)
	end
	return trim(output)
end

local function writeLock(commit: string, tree: string)
	local source = ([=[--!strict

return {
	schemaVersion = 1,
	dependencies = {
		{
			name = "verify",
			repository = %q,
			commit = %q,
			tree = %q,
			rights = "MIT",
			surfaces = { { root = "src", role = "verification" } },
		},
	},
}
]=]):format(REPOSITORY, commit, tree)
	fs.writeStringToFile(STAGE .. "/generate/dependencies.lock.luau", source)
end

local function fixture(): (string, string, string)
	process.run { "rm", "-rf", STAGE }
	fs.createDirectory(STAGE .. "/generate/tools", { makeParents = true })
	fs.createDirectory(STAGE .. "/remote/verify/src", { makeParents = true })
	fs.writeStringToFile(
		STAGE .. "/generate/tools/sync-dependencies.luau",
		fs.readFileToString "tools/sync-dependencies.luau"
	)
	fs.writeStringToFile(STAGE .. "/remote/verify/src/init.luau", "return table.freeze {}\n")

	local environment = isolatedEnvironment()
	local source = STAGE .. "/remote/verify"
	local initialized = process.run({ "git", "init", "--quiet", source }, { env = environment })
	if not initialized.ok then
		error("dependency source fixture: git init failed", 0)
	end
	git(source, environment, "config", "user.name", "voidmeld")
	git(source, environment, "config", "user.email", "158495725+voidmeld@users.noreply.github.com")
	git(source, environment, "add", "src/init.luau")
	git(source, environment, "commit", "--quiet", "-m", "Fixture")

	local commit = git(source, environment, "rev-parse", "HEAD")
	local tree = git(source, environment, "rev-parse", "HEAD^{tree}")
	writeLock(commit, tree)
	return source, commit, tree
end

local function rewriteEnvironment(source: string, disguiseStoredIdentity: boolean): { [string]: string }
	local out = isolatedEnvironment()
	out.GIT_ALLOW_PROTOCOL = "file"
	out.GIT_CONFIG_COUNT = if disguiseStoredIdentity then "2" else "1"
	out.GIT_CONFIG_KEY_0 = "url.file://" .. process.cwd() .. "/" .. source .. ".insteadOf"
	out.GIT_CONFIG_VALUE_0 = REPOSITORY
	if disguiseStoredIdentity then
		out.GIT_CONFIG_KEY_1 = "url." .. REPOSITORY .. ".insteadOf"
		out.GIT_CONFIG_VALUE_1 = DISGUISED_REPOSITORY
	end
	return out
end

local function sync(environment: { [string]: string }, checkOnly: boolean): (boolean, string)
	local argv = { "lute", "run", "tools/sync-dependencies.luau" }
	if checkOnly then
		table.insert(argv, "--check")
	end
	return run(argv, process.cwd() .. "/" .. STAGE .. "/generate", environment)
end

describe("dependency repository identity", function()
	Test.afterEach(function()
		process.run { "rm", "-rf", STAGE }
	end)

	it("stores canonical HTTPS identity while Git rewrites clone transport", function()
		local source, commit, tree = fixture()
		local environment = rewriteEnvironment(source, false)
		local ok, output = sync(environment, false)
		expect(ok):toBe(true)
		expect(output):toContain("verify at " .. commit)

		local cached = STAGE .. "/generate/.lute/dependencies/verify"
		expect(git(cached, isolatedEnvironment(), "rev-parse", "HEAD")):toBe(commit)
		expect(git(cached, isolatedEnvironment(), "rev-parse", "HEAD^{tree}")):toBe(tree)
		expect(git(cached, isolatedEnvironment(), "config", "--local", "--get", "remote.origin.url")):toBe(REPOSITORY)
		expect(git(cached, environment, "remote", "get-url", "origin")):toBe(
			"file://" .. process.cwd() .. "/" .. source
		)
	end)

	it("rejects a noncanonical stored identity even when a rewrite disguises it", function()
		local source = fixture()
		local initialEnvironment = rewriteEnvironment(source, false)
		expect((sync(initialEnvironment, false))):toBe(true)

		local cached = STAGE .. "/generate/.lute/dependencies/verify"
		local disguisedEnvironment = rewriteEnvironment(source, true)
		git(cached, isolatedEnvironment(), "remote", "set-url", "origin", DISGUISED_REPOSITORY)
		expect(git(cached, disguisedEnvironment, "remote", "get-url", "origin")):toBe(REPOSITORY)
		expect(git(cached, isolatedEnvironment(), "config", "--local", "--get", "remote.origin.url")):toBe(
			DISGUISED_REPOSITORY
		)

		local ok, output = sync(disguisedEnvironment, true)
		expect(ok):toBe(false)
		expect(output):toContain "cache is absent or does not match the lock"
	end)
end)

return nil
