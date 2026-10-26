--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local output = process.args[2]
if output == nil then
	error "dcc-worker requires an output path"
end
fs.writeStringToFile(output, "canonical-fixture-v1")
