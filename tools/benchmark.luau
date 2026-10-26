--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local Benchmark = require "../.lute/dependencies/verify/src/benchmark"
local Lute = require "../.lute/dependencies/verify/src/lute"
local Verify = require "../.lute/dependencies/verify/src/core"

local spec = require "../bench/simple-path"

local USAGE = "usage: lute run tools/benchmark.luau [--out file] | --compare baseline.json candidate.json"
local RULE = { ratio = 1.25, floor = 20 }

local function load(path: string): Benchmark.Stored
	return Benchmark.decode(Lute.parse(fs.readFileToString(path)))
end

local args = process.args
if args[2] == "--compare" then
	if args[3] == nil or args[4] == nil or args[5] ~= nil then
		error(USAGE)
	end
	local report = Benchmark.compare(load(args[3]), load(args[4]), { rule = RULE })
	print(Verify.format(report))
	if report.failed > 0 or report.unsupported > 0 then
		process.exit(1)
	end
	return
end

local out: string? = nil
if args[2] == "--out" and args[3] ~= nil and args[4] == nil then
	out = args[3]
elseif args[2] ~= nil then
	error(USAGE)
end

local result = Benchmark.run(spec)
if result.failure ~= nil then
	print("benchmark failed: " .. result.failure)
	process.exit(1)
end
print(
	("%s: %d raw samples; p50 %.3f %s, p95 %.3f %s"):format(
		result.name,
		#result.samples,
		result.summary.p50 or 0,
		result.unit,
		result.summary.p95 or 0,
		result.unit
	)
)
if out ~= nil then
	fs.writeStringToFile(out, Lute.encode(Benchmark.store(result.name, { result })))
	print("stored " .. out)
end
