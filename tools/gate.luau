--!strict

local fs = require "@std/fs"
local process = require "@std/process"

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

local function discover(root: string, pattern: string): { string }
	local found = Lute.corpus.discover {
		listDir = fs.listDirectory,
		rules = { { root = root, pattern = pattern } },
	}
	assert(#found > 0, "corpus is empty: " .. root)
	return found
end

local specs = discover("tests", "%.verify%.luau$")
local examples = discover("examples", "%.luau$")

local function check(id: string, argv: { string }, tier: string): Gate.ProducerDraft
	return { id = id, kind = "command", argv = argv, tier = tier }
end

local format: { string } = { "stylua", "--check", "lint.config.luau" }
local lint: { string } = { "lute", "lint", "-c", "lint.config.luau" }
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
	check("dependency-sync", { "lute", "run", "tools/sync-dependencies.luau" }, "static"),
	check("type-policy", { "lute", "run", "tools/check-no-any.luau" }, "static"),
	check("format", format, "static"),
	check("lint", lint, "static"),
	check("types", types, "static"),
	{
		id = "tests",
		kind = "tests",
		worker = "tools/test-worker.luau",
		locators = specs,
		tier = "behavior",
		why = "the test corpus in tests, run as Verify cases",
		deadlineSeconds = 1800,
	},
	check("consumer-lints", { "lute", "run", "tools/generate-check.luau", "examples" }, "static"),
	check("boundary", { "lute", "run", "tools/check-boundary.luau" }, "static"),
	check("api-docs", { "lute", "run", "tools/check-api-docs.luau" }, "static"),
	check("provenance", { "lute", "run", "tools/check-provenance.luau" }, "static"),
}
for _, example in examples do
	local name = string.gsub(string.gsub(string.sub(example, #"examples/" + 1), "%.luau$", ""), "[^%w]+", "-")
	table.insert(producers, check("example-" .. name, { "lute", "run", example }, "behavior"))
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
