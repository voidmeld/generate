--!strict

local function sortedStrings(values: { string }): { string }
	local copy = table.clone(values)
	table.sort(copy)
	return copy
end

local function copy(value: unknown): unknown
	local visiting: { [unknown]: boolean } = {}
	local function clone(current: unknown): unknown
		if type(current) ~= "table" then
			return current
		end
		local source = current :: { [unknown]: unknown }
		if visiting[source] then
			error("Generate canonical values may not contain cycles", 3)
		end
		visiting[source] = true
		local result: { [unknown]: unknown } = {}
		for key, nested in source do
			result[key] = clone(nested)
		end
		visiting[source] = nil
		return result
	end
	return clone(value)
end

local function stableValue(value: unknown): string
	local visiting: { [unknown]: boolean } = {}
	local function encode(current: unknown): string
		local kind = type(current)
		if kind == "nil" then
			return "null"
		elseif kind == "boolean" then
			return tostring(current)
		elseif kind == "number" then
			local number = current :: number
			if number ~= number or number == math.huge or number == -math.huge then
				error("Generate canonical numbers must be finite", 3)
			end
			return if number == 0 then "0" else tostring(number)
		elseif kind == "string" then
			return string.format("%q", current :: string)
		elseif kind ~= "table" then
			error("Generate canonical values may contain only data, got " .. kind, 3)
		end

		local object = current :: { [unknown]: unknown }
		if visiting[object] then
			error("Generate canonical values may not contain cycles", 3)
		end
		visiting[object] = true
		local array = true
		local count = 0
		for key in object do
			count += 1
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				array = false
			end
		end
		if array then
			for index = 1, count do
				if object[index] == nil then
					array = false
					break
				end
			end
		end
		if array then
			local pieces: { string } = {}
			for index = 1, count do
				table.insert(pieces, encode(object[index]))
			end
			visiting[object] = nil
			return "[" .. table.concat(pieces, ",") .. "]"
		end

		local keys: { string } = {}
		for key in object do
			if type(key) ~= "string" then
				error("Generate canonical objects require string keys", 3)
			end
			table.insert(keys, key)
		end
		table.sort(keys)
		local pieces: { string } = {}
		for _, key in keys do
			table.insert(pieces, string.format("%q", key) .. ":" .. encode(object[key]))
		end
		visiting[object] = nil
		return "{" .. table.concat(pieces, ",") .. "}"
	end
	return encode(value)
end

local function fingerprint(value: unknown): string
	local bytes = stableValue(value)

	local first, second, third, fourth = 2166136261, 2246822519, 3266489917, 668265263
	for index = 1, #bytes do
		local byte = string.byte(bytes, index) :: number
		first = (first * 65599 + byte + 1) % 4294967296
		second = (second * 131071 + byte + 2) % 4294967296
		third = (third * 524287 + byte + 3) % 4294967296
		fourth = (fourth * 1048573 + byte + 4) % 4294967296
	end
	return string.format("gen-fp2-%08x%08x%08x%08x", first, second, third, fourth)
end

return {
	encode = stableValue,
	copy = copy,
	fingerprint = fingerprint,
	sortedStrings = sortedStrings,
}
