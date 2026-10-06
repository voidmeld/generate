--!strict

local SENSITIVE: { [string]: boolean } = {
	apikey = true,
	accesstoken = true,
	authtoken = true,
	authorization = true,
	clientsecret = true,
	cookie = true,
	credential = true,
	credentials = true,
	password = true,
	privatekey = true,
	refreshtoken = true,
	secret = true,
	token = true,
}

local function normalized(key: string): string
	return string.lower((string.gsub(key, "[^%w]", "")))
end

local function validate(value: unknown, label: string)
	local visiting: { [unknown]: boolean } = {}
	local function visit(current: unknown, path: string)
		local kind = type(current)
		if kind == "number" then
			local number = current :: number
			if number ~= number or number == math.huge or number == -math.huge then
				error(("%s contains a non-finite number at %s"):format(label, path), 3)
			end
			return
		end
		if kind == "nil" or kind == "boolean" or kind == "string" then
			return
		end
		if kind ~= "table" then
			error(("%s contains executable or host value at %s"):format(label, path), 3)
		end
		local object = current :: { [unknown]: unknown }
		if visiting[object] then
			error(("%s contains a cycle at %s"):format(label, path), 3)
		end
		visiting[object] = true
		for key, child in object do
			if type(key) == "string" and SENSITIVE[normalized(key)] then
				error(("%s contains secret-shaped key %q at %s"):format(label, key, path), 3)
			end
			visit(child, path .. "." .. tostring(key))
		end
		visiting[object] = nil
	end
	visit(value, label)
end

return { validate = validate }
