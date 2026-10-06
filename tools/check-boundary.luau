--!strict

local fs = require "@std/fs"
local process = require "@std/process"

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
for _, entry in fs.listDirectory "src/core" do
	if entry.type == "file" and string.match(entry.name, "%.luau$") then
		local source = fs.readFileToString("src/core/" .. entry.name)
		for _, needle in FORBIDDEN do
			if string.find(source, needle, 1, true) then
				table.insert(
					findings,
					("src/core/%s names forbidden host/domain spelling %q"):format(entry.name, needle)
				)
			end
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
