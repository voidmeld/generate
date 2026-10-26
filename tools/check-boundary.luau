--!strict

local process = require "@std/process"
local walk = require "./lib/walk"

local FORBIDDEN = {
	"Roblox",
	"roblox",
	"Studio",
	"studs",
	"Studs",
	"universe",
	"Universe",
	"witness",
	"Witness",
	"mint",
	"Mint",
	"GenerationService",
	"Compose",
	"Verify",
	"@std/",
	"@lute/",
	"game.",
	"workspace",
	"os.clock",
	"process.run",
	"task.spawn",
}

local findings: { string } = {}
local files = walk.files("src/core", { ".luau" })
assert(#files > 0, "check-boundary: no core source found")
for _, file in files do
	for _, needle in FORBIDDEN do
		if string.find(file.contents, needle, 1, true) then
			table.insert(findings, ("%s names forbidden host/domain spelling %q"):format(file.path, needle))
		end
	end
end
if #findings > 0 then
	for _, finding in findings do
		print(finding)
	end
	process.exit(1)
end
print "check-boundary: clean"
