--!strict

export type Config = { indent: string, serialize: (value: unknown) -> string }

local function encodeValue(config: Config, input: unknown, indent: string): string
	if type(input) ~= "table" then
		return config.serialize(input)
	end
	local value = input
	local nested = indent .. config.indent
	if #value > 0 then
		local items: { string } = {}
		for _, entry in value do
			table.insert(items, nested .. encodeValue(config, entry, nested))
		end
		return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
	end
	local keys: { string } = {}
	local fields: { [string]: unknown } = {}
	for key, entry in value do
		assert(type(key) == "string", "image request object keys must be strings")
		table.insert(keys, key)
		fields[key] = entry
	end
	if #keys == 0 then
		return "{}"
	end
	table.sort(keys)
	local items: { string } = {}
	for _, key in keys do
		table.insert(items, nested .. config.serialize(key) .. ": " .. encodeValue(config, fields[key], nested))
	end
	return "{\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "}"
end

local function encode(config: Config, document: unknown): string
	return encodeValue(config, document, "") .. "\n"
end

return {
	encodeValue = encodeValue,
	encode = encode,
}
