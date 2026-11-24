--!strict

local Generate = require "../core"

export type Creator = {
	type: "group" | "user",
	id: string,
}

export type Visibility = "private" | "restricted"

export type DestinationDraft = {
	creator: Creator,
	assetType: string,
	displayName: string?,
	description: string?,
	visibility: Visibility?,
	credentialName: string,
	assetId: string?,
	grantUniverses: { number }?,
	verifyDependencies: boolean?,
}

export type DestinationFields = {
	creator: Creator,
	assetType: string,
	displayName: string?,
	description: string?,
	visibility: Visibility,
	credentialName: string,
	assetId: string?,
	grantUniverses: { number }?,
	verifyDependencies: boolean,
}

local ADAPTER = "roblox"

local DESTINATION_KEYS: { [string]: boolean } = {
	creator = true,
	assetType = true,
	displayName = true,
	description = true,
	visibility = true,
	credentialName = true,
	assetId = true,
	grantUniverses = true,
	verifyDependencies = true,
}

local CREATOR_KEYS: { [string]: boolean } = {
	type = true,
	id = true,
}

local function field(value: unknown, name: string): unknown
	assert(type(value) == "table")
	for key, item in value do
		if key == name then
			return item
		end
	end
	return nil
end

local function exactKeys(value: unknown, allowed: { [string]: boolean }, label: string)
	assert(type(value) == "table")
	for key in value do
		if type(key) ~= "string" or not allowed[key] then
			error(("Generate Roblox destination %s carries unknown field %s"):format(label, tostring(key)), 4)
		end
	end
end

local function grantUniverses(draft: unknown): { number }?
	if draft == nil then
		return nil
	end
	if type(draft) ~= "table" then
		error("Generate Roblox destination grantUniverses must be an array of universe ids", 3)
	end
	local ids: { number } = {}
	local seen: { [number]: boolean } = {}
	local index = 0
	for key, value in draft do
		index += 1
		if type(key) ~= "number" or key ~= index or type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then
			error(
				"Generate Roblox destination grantUniverses must be a dense array of distinct positive universe ids",
				3
			)
		end
		local id = value
		if seen[id] then
			error("Generate Roblox destination grantUniverses must not repeat a universe id", 3)
		end
		seen[id] = true
		table.insert(ids, id)
	end
	if #ids == 0 then
		error("Generate Roblox destination grantUniverses must be non-empty when declared", 3)
	end
	return ids
end

local function normalize(input: unknown): DestinationFields
	if type(input) ~= "table" then
		error("Generate Roblox destination must be a table", 3)
	end
	exactKeys(input, DESTINATION_KEYS, "destination")
	local creator = field(input, "creator")
	if type(creator) ~= "table" then
		error("Generate Roblox destination creator must name the asset owner", 3)
	end
	exactKeys(creator, CREATOR_KEYS, "destination.creator")
	local creatorType, creatorId = field(creator, "type"), field(creator, "id")
	if (creatorType ~= "group" and creatorType ~= "user") or type(creatorId) ~= "string" or creatorId == "" then
		error("Generate Roblox destination creator must be { type = group | user, id = <non-empty id> }", 3)
	end
	local assetType = field(input, "assetType")
	if type(assetType) ~= "string" or string.match(assetType, "^[A-Za-z][A-Za-z0-9]*$") == nil then
		error("Generate Roblox destination assetType must be one platform asset type name", 3)
	end
	local displayName, description = field(input, "displayName"), field(input, "description")
	if
		(displayName ~= nil or description ~= nil)
		and (type(displayName) ~= "string" or displayName == "" or type(description) ~= "string" or description == "")
	then
		error("Generate Roblox destination displayName and description must both be non-empty when configured", 3)
	end
	local visibility = field(input, "visibility") or "private"
	if visibility ~= "private" and visibility ~= "restricted" then
		error("Generate Roblox destination visibility may be only private or restricted", 3)
	end
	local credentialName = field(input, "credentialName")
	if
		type(credentialName) ~= "string"
		or #credentialName > 64
		or string.match(credentialName, "^[A-Z][A-Z0-9_]*$") == nil
	then
		error(
			"Generate Roblox destination credentialName must name an environment variable (for example ASSETS_PUBLISH_KEY), never carry a credential value",
			3
		)
	end
	local assetId = field(input, "assetId")
	if assetId ~= nil and (type(assetId) ~= "string" or assetId == "") then
		error("Generate Roblox destination assetId must be a non-empty existing asset id when declared", 3)
	end
	local universes = grantUniverses(field(input, "grantUniverses"))
	local verifyDependencies = field(input, "verifyDependencies")
	if verifyDependencies ~= nil and type(verifyDependencies) ~= "boolean" then
		error("Generate Roblox destination verifyDependencies must be a boolean when declared", 3)
	end
	if verifyDependencies == true and universes == nil then
		error(
			"Generate Roblox destination verifyDependencies requires grantUniverses; a dependency is verified against the universes that must load it",
			3
		)
	end
	return {
		creator = { type = creatorType, id = creatorId },
		assetType = assetType,
		displayName = displayName,
		description = description,
		visibility = visibility,
		credentialName = credentialName,
		assetId = assetId,
		grantUniverses = universes,
		verifyDependencies = verifyDependencies == true,
	}
end

local function descriptorOf(fields: DestinationFields): { [string]: unknown }
	return {
		creator = { type = fields.creator.type, id = fields.creator.id },
		assetType = fields.assetType,
		displayName = fields.displayName,
		description = fields.description,
		visibility = fields.visibility,
		credentialName = fields.credentialName,
		assetId = fields.assetId,
		grantUniverses = fields.grantUniverses,
		verifyDependencies = fields.verifyDependencies,
	}
end

local function destination(draft: unknown): Generate.Destination
	return { adapter = ADAPTER, descriptor = descriptorOf(normalize(draft)) }
end

local function readDestination(value: Generate.Destination): DestinationFields
	if type(value) ~= "table" or value.adapter ~= ADAPTER then
		error("Generate Roblox destination requires the roblox adapter", 2)
	end
	local fields = normalize(value.descriptor)
	if Generate.fingerprint(value.descriptor) ~= Generate.fingerprint(descriptorOf(fields)) then
		error("Generate Roblox destination descriptor must be the normalized descriptor", 2)
	end
	return fields
end

return { create = destination, read = readDestination }
