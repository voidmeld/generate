--!strict

local fs = require "@std/fs"
local process = require "@std/process"

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

local documented = fs.readFileToString "docs/api.md"

local function mentions(name: string): boolean
	local start = 1
	while true do
		local found, finish = string.find(documented, name, start, true)
		if found == nil then
			return false
		end
		local before = if found > 1 then string.sub(documented, found - 1, found - 1) else " "
		local after = string.sub(documented, (finish :: number) + 1, (finish :: number) + 1)
		if string.match(before, "[%w_]") == nil and string.match(after, "[%w_]") == nil then
			return true
		end
		start = found + 1
	end
end

local function names(value: unknown): { string }
	local result: { string } = {}
	if type(value) == "table" then
		for key, child in value :: { [unknown]: unknown } do
			if type(key) == "string" and type(child) ~= "string" and type(child) ~= "number" then
				table.insert(result, key)
			end
		end
	end
	table.sort(result)
	return result
end

local missing: { string } = {}

local function check(path: string, value: unknown)
	if not mentions(path) then
		table.insert(missing, path)
		return
	end
	if type(value) == "table" and string.match(path, "[%.]([%u_]+)$") == nil then
		for _, member in names(value) do
			check(path .. "." .. member, (value :: { [string]: unknown })[member])
		end
	end
end

for _, root in ROOTS do
	for _, key in names(root.module) do
		check(root.prefix .. "." .. key, (root.module :: { [string]: unknown })[key])
	end
end
if #missing > 0 then
	for _, path in missing do
		print(("docs/api.md has no entry for %s"):format(path))
	end
	process.exit(1)
end
print "check-api-docs: every public export has an entry"
