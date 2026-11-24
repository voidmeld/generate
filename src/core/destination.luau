--!strict

local Canonical = require "./canonical"
local Secret = require "./secret"
local Types = require "./types"

type Destination = Types.Destination

local function destination(draft: unknown, hostVerification: unknown): (Destination?, boolean?)
	if draft == nil then
		if hostVerification ~= nil and hostVerification ~= false then
			error("Generate brief delivery.hostVerification requires delivery.destination", 3)
		end
		return nil, nil
	end
	if type(draft) ~= "table" then
		error("Generate brief delivery.destination must be a table", 3)
	end
	local adapter: unknown = nil
	local descriptor: unknown = nil
	for key, value in draft do
		if key == "adapter" then
			adapter = value
		elseif key == "descriptor" then
			descriptor = value
		else
			error(("Generate brief delivery.destination carries unknown field %s"):format(tostring(key)), 3)
		end
	end
	if type(adapter) ~= "string" or adapter == "" or string.match(adapter, "^[a-z][a-z0-9%-]*$") == nil then
		error("Generate brief delivery.destination.adapter must name one adapter in lowercase", 3)
	end
	if type(descriptor) ~= "table" then
		error("Generate brief delivery.destination.descriptor must be a data table", 3)
	end
	Secret.validate(descriptor, "Generate brief delivery.destination.descriptor")
	local data: { [string]: unknown } = {}
	for key, value in descriptor do
		if type(key) ~= "string" then
			error("Generate brief delivery.destination.descriptor requires string keys", 3)
		end
		data[key] = value
	end
	if hostVerification ~= nil and type(hostVerification) ~= "boolean" then
		error("Generate brief delivery.hostVerification must be a boolean when declared", 3)
	end
	return {
		adapter = adapter,
		descriptor = Canonical.copy(data),
	}, hostVerification == true
end

return { normalize = destination }
