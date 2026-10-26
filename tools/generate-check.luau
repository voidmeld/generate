--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local Consumer = require "../src/consumer"

local function collect(root: string): ({ string }?, string?)
	if not fs.exists(root) then
		return nil, "source path does not exist: " .. root
	end
	if fs.metadata(root).type == "file" then
		if string.match(root, "%.generate%.luau$") == nil then
			return nil, "source file must end in .generate.luau: " .. root
		end
		return { root }, nil
	end
	local paths: { string } = {}
	local function walk(path: string)
		for _, entry in fs.listDirectory(path) do
			local child = path .. "/" .. entry.name
			if entry.type == "dir" then
				walk(child)
			elseif string.match(entry.name, "%.generate%.luau$") then
				table.insert(paths, child)
			end
		end
	end
	walk(root)
	table.sort(paths)
	return paths, nil
end

local function main(): number
	local root = "examples"
	local rulesets: { Consumer.Ruleset } = {}
	for index = 2, #process.args do
		local argument = process.args[index]
		local name = string.match(argument, "^%-%-ruleset=(.+)$")
		if name == nil then
			root = argument
		elseif name == "roblox" then
			rulesets[#rulesets + 1] = "roblox"
		else
			print("generate-check: unknown ruleset " .. name)
			return 1
		end
	end
	local findings: { Consumer.Finding } = {}
	local paths, problem = collect(root)
	if paths == nil then
		print("generate-check: " .. (problem :: string))
		return 1
	end
	for _, path in paths do
		for _, finding in Consumer.scanSource(path, fs.readFileToString(path), rulesets) do
			table.insert(findings, finding)
		end
	end
	if #findings == 0 then
		print "generate-check: clean"
		return 0
	end
	print(("generate-check: %d finding(s)"):format(#findings))
	for _, finding in findings do
		print(("%s:%s: %s; fix: %s"):format(finding.path, finding.code, finding.message, finding.fix))
	end
	return 1
end

local code = main()
if code ~= 0 then
	process.exit(code)
end
