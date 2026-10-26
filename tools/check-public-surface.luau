--!strict

local fs = require "@std/fs"
local process = require "@lute/process"

local ROOTS: { { prefix: string, module: unknown } } = {
	{ prefix = "Generate", module = require "../src/core" },
	{ prefix = "Agent", module = require "../src/agent" },
	{ prefix = "Roblox", module = require "../src/roblox" },
	{ prefix = "Media", module = require "../src/media" },
	{ prefix = "Image", module = require "../src/image" },
	{ prefix = "Content", module = require "../src/content" },
	{ prefix = "Lute", module = require "../src/lute" },
	{ prefix = "Host", module = require "../src/host" },
	{ prefix = "Consumer", module = require "../src/consumer" },
}

local UNDOCUMENTED_BY_DESIGN: { [string]: string } = {}

local function exportsOf(value: unknown, prefix: string): { string }
	local names: { string } = {}
	if type(value) == "table" then
		for key, child in value :: { [string]: unknown } do
			local qualified = prefix .. "." .. key
			table.insert(names, qualified)
			if type(child) == "table" and string.match(key, "^[%u_]+$") == nil then
				for _, name in exportsOf(child, qualified) do
					table.insert(names, name)
				end
			end
		end
	end
	table.sort(names)
	return names
end

local function documented(): { [string]: true }
	local text = fs.readFileToString "docs/api.md"
	local found: { [string]: true } = {}
	local prefixes: { [string]: true } = {}
	for _, root in ROOTS do
		prefixes[root.prefix] = true
	end
	for entry in string.gmatch(text, "`([%w_]+%.[%w_%.]+)") do
		local prefix = string.match(entry, "^([%w_]+)%.")
		if prefix ~= nil and prefixes[prefix] then
			found[entry] = true
			local parent = string.match(entry, "^(.*)%.[%w_]+$")
			while parent ~= nil and string.find(parent, ".", 1, true) ~= nil do
				found[parent] = true
				parent = string.match(parent, "^(.*)%.[%w_]+$")
			end
		end
	end
	return found
end

local function main(): number
	if not fs.exists "docs/api.md" then
		print "check-public-surface: required docs/api.md is absent"
		return 1
	end

	local problems: { string } = {}
	local docs = documented()
	local checked = 0

	local seenInDocs: { [string]: true } = {}
	local typeExports: { [string]: true } = {}
	local directories = { "core", "agent", "roblox", "media", "image", "content", "lute", "host", "consumer" }
	for index, root in ROOTS do
		local source = fs.readFileToString("src/" .. directories[index] .. "/init.luau")
		for name in string.gmatch(source, "export%s+type%s+([%w_]+)") do
			typeExports[root.prefix .. "." .. name] = true
		end
	end

	for _, root in ROOTS do
		for _, qualified in exportsOf(root.module, root.prefix) do
			seenInDocs[qualified] = true
			checked += 1
			if docs[qualified] == nil and UNDOCUMENTED_BY_DESIGN[qualified] == nil then
				table.insert(problems, qualified .. " is exported but docs/api.md has no code entry")
			end
		end
	end

	for entry in docs do
		if not seenInDocs[entry] and not typeExports[entry] then
			table.insert(problems, ("docs/api.md documents %s but no package exports it"):format(entry))
		end
	end

	if #problems > 0 then
		table.sort(problems)
		print(("check-public-surface: %d problem(s)"):format(#problems))
		for _, problem in problems do
			print("  " .. problem)
		end
		return 1
	end

	print(("check-public-surface: ok (%d exports, all documented)"):format(checked))
	return 0
end

local code = main()
if code ~= 0 then
	process.exit(code)
end
return nil
