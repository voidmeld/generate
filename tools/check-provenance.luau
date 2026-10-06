--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local findings: { string } = {}
if not fs.exists "LICENSE" then
	table.insert(findings, "LICENSE is missing")
else
	local license = fs.readFileToString "LICENSE"
	if
		not string.find(license, "MIT License", 1, true)
		or not string.find(license, "Copyright (c) 2026 voidmeld", 1, true)
		or not string.find(license, "Permission is hereby granted, free of charge", 1, true)
	then
		table.insert(findings, "LICENSE is not the expected MIT grant for Copyright (c) 2026 voidmeld")
	end
end
for _, grant in { "LICENCE", "COPYING", "LICENSE.md", "LICENCE.md" } do
	if fs.exists(grant) then
		table.insert(findings, grant .. " is an ungoverned additional licence file")
	end
end
for _, directory in { "vendor", "third_party", "third-party", "node_modules", "Packages" } do
	if fs.exists(directory) then
		table.insert(findings, directory .. " is a committed dependency or unadmitted source tree")
	end
end

local function walk(path: string)
	for _, entry in fs.listDirectory(path) do
		local child = path .. "/" .. entry.name
		if entry.type == "dir" and entry.name ~= ".git" and entry.name ~= ".lute" and entry.name ~= "build" then
			walk(child)
		elseif entry.name ~= ".git" and entry.type == "file" then
			if string.match(entry.name, "%.py$") then
				table.insert(findings, child .. ": maintained Python requires a documented adapter exception")
			end
		end
	end
end
walk "."

if not fs.exists "dependencies.lock.luau" then
	table.insert(findings, "dependencies.lock.luau is missing")
else
	local resolved = process.run { "lute", "run", "tools/sync-dependencies.luau", "--check" }
	if not resolved.ok then
		table.insert(findings, "the ignored dependency cache does not match the committed lock: " .. resolved.stdout)
	end
end

if #findings > 0 then
	for _, finding in findings do
		print(finding)
	end
	process.exit(1)
end
print "check-provenance: MIT-licensed first-party source, exact MIT dependency, product-neutral tree"
