--!strict

local fs = require "@std/fs"
local process = require "@lute/process"

if not fs.exists ".lute/dependencies/verify" then
	local synced = process.run { "lute", "run", "tools/sync-dependencies.luau" }
	assert(synced.ok, "gate: the dependency cache could not be created")
end

local Gate = require "../.lute/dependencies/verify/src/gate"
local Lute = require "../.lute/dependencies/verify/src/lute"

local USAGE =
	"usage: lute run tools/gate.luau [--benchmark] [--only producer]... [--tier name]... [--case id]... [--file spec]... [--name text] [--rerun] [--explain id] [--list]"
local DIRECTORY = ".lute/tmp/generate-gate"
local SOURCES = { "src", "tests", "tools", "bench", "examples", "dependencies.lock.luau" }

local benchmark = false
local flags: { string } = {}
for index = 2, #process.args do
	if process.args[index] == "--benchmark" then
		benchmark = true
	else
		table.insert(flags, process.args[index])
	end
end

if #flags == 0 then
	local status = process.run { "git", "status", "--porcelain" }
	if not status.ok or string.match(status.stdout, "%S") ~= nil then
		print "gate: full candidate requires a clean committed HEAD; use focused checks while editing, then commit before the full gate"
		process.exit(1)
	end
end

local function discover(root: string, pattern: string): { string }
	local found = Lute.corpus.discover {
		listDir = fs.listDirectory,
		rules = { { root = root, pattern = pattern } },
	}
	assert(#found > 0, "corpus is empty: " .. root)
	return found
end

local specs = require "./test-manifest"
assert(#specs > 0, "the test manifest names no specification")
local examples = discover("examples", "%.luau$")

local function check(id: string, argv: { string }, tier: string): Gate.ProducerDraft
	return { id = id, kind = "command", argv = argv, tier = tier }
end

local format: { string } = { "stylua", "--check", "lint.config.luau" }
local lint: { string } = { "lute", "lint", "--verbose", "-c", "lint.config.luau" }
local types: { string } = {
	"luau-lsp",
	"analyze",
	"--platform=standard",
	"--base-luaurc=.luaurc",
	"--ignore=**/.lute/**",
	"--ignore=**/build/**",
	"lint.config.luau",
}
for _, source in SOURCES do
	table.insert(format, source)
	table.insert(lint, source)
	table.insert(types, source)
end

local producers: { Gate.ProducerDraft } = {
	check("comments", { "lute", "run", "tools/check-code-comments.luau" }, "fast"),
	check("leakage", { "lute", "run", "tools/check-leakage.luau" }, "fast"),
	check("test-manifest", { "lute", "run", "tools/check-test-manifest.luau" }, "fast"),
	check("verify-check", {
		"lute",
		"run",
		".lute/dependencies/verify/tools/verify-check.luau",
		"--ruleset",
		"generic",
		"tests",
	}, "fast"),
	{
		id = "clean-clone",
		exclusive = true,
		kind = "command",
		argv = { "lute", "run", "tools/check-clean-clone.luau" },
		tier = "slow",
		deadlineSeconds = 1800,
		why = "a fresh clone of committed HEAD passes the fast gate without working-tree state",
	},
	check("dependency-sync", { "lute", "run", "tools/sync-dependencies.luau" }, "fast"),
	check("type-policy", { "lute", "run", "tools/check-no-any.luau" }, "fast"),
	check("format", format, "fast"),
	check("lint", lint, "fast"),
	check("types", types, "fast"),
	{
		id = "tests",
		kind = "tests",
		worker = "tools/test-worker.luau",
		locators = specs,
		tier = "fast",
		why = "the test corpus in tests, run as Verify cases",
		deadlineSeconds = 1800,
	},
	check("consumer-lints", { "lute", "run", "tools/generate-check.luau", "examples" }, "fast"),
	check("boundary", { "lute", "run", "tools/check-boundary.luau" }, "fast"),
	check("public-surface", { "lute", "run", "tools/check-public-surface.luau" }, "fast"),
	check("provenance", { "lute", "run", "tools/check-provenance.luau" }, "fast"),
}
for _, example in examples do
	local name = string.gsub(string.gsub(string.sub(example, #"examples/" + 1), "%.luau$", ""), "[^%w]+", "-")
	table.insert(producers, check("example-" .. name, { "lute", "run", example }, "fast"))
end
if benchmark then
	table.insert(producers, {
		id = "benchmark",
		kind = "benchmark",
		benchmark = require "../bench/simple-path",
		tier = "benchmark",
		why = "measures one execution stage; records raw samples and applies no budget",
	})
end

local exitCode = Lute.gate.cli({
	id = "generate-gate",
	producers = producers,
	policy = { commandDeadlineSeconds = 900, deadlineSeconds = 3600 },
}, flags, { usage = USAGE, options = { directory = DIRECTORY } })
if exitCode ~= 0 then
	process.exit(exitCode)
end
