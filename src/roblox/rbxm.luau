--!strict

local MAGIC = "<roblox!\137\255\r\n\26\n"
local HEADER_SIZE = 32
local ZSTD_MAGIC = "\40\181\47\253"

export type Reference = {
	assetId: number,
	className: string,
	property: string,
	kind: "content" | "string" | "shared",
	uri: string,
}

export type Class = {
	classId: number,
	className: string,
	instanceCount: number,
}

export type Document = {
	ok: boolean,
	classes: { Class },
	references: { Reference },
	assetIds: { number },
	diagnostics: { string },
}

export type Instance = {
	referent: number,
	className: string,
	name: string,
	parent: number,
	content: { [string]: string },
}

export type Tree = {
	ok: boolean,
	instances: { Instance },
	diagnostics: { string },
}

local TYPE_STRING = 1
local TYPE_SHARED_STRING = 28
local TYPE_CONTENT = 34
local CONTENT_SOURCE_URI = 2

local CONTENT_PROPERTY_NAMES: { [string]: boolean } = {
	MeshId = true,
	MeshContent = true,
	TextureID = true,
	TextureContent = true,
	CageMeshId = true,
	CageMeshContent = true,
	ReferenceMeshId = true,
	ReferenceMeshContent = true,
	TemporaryCageMeshId = true,
	HSRAssetId = true,
	ColorMap = true,
	ColorMapContent = true,
	NormalMap = true,
	NormalMapContent = true,
	MetalnessMap = true,
	MetalnessMapContent = true,
	RoughnessMap = true,
	RoughnessMapContent = true,
	EmissiveMask = true,
	EmissiveMaskContent = true,
	TexturePack = true,
	SoundId = true,
	AnimationId = true,
	Image = true,
	Texture = true,
	Graphic = true,
	Face = true,
}

local function decompressLz4(source: buffer, outLength: number): buffer
	local out = buffer.create(outLength)
	local sourceLength = buffer.len(source)
	local read = 0
	local written = 0
	while written < outLength do
		if read >= sourceLength then
			error "rbxm: truncated lz4 block"
		end
		local token = buffer.readu8(source, read)
		read += 1
		local literalLength = bit32.rshift(token, 4)
		if literalLength == 15 then
			while true do
				local extra = buffer.readu8(source, read)
				read += 1
				literalLength += extra
				if extra ~= 255 then
					break
				end
			end
		end
		if literalLength > 0 then
			buffer.copy(out, written, source, read, literalLength)
			read += literalLength
			written += literalLength
		end
		if written >= outLength then
			break
		end
		local offset = buffer.readu16(source, read)
		read += 2
		if offset == 0 or offset > written then
			error "rbxm: lz4 match offset out of range"
		end
		local matchLength = bit32.band(token, 15) + 4
		if bit32.band(token, 15) == 15 then
			while true do
				local extra = buffer.readu8(source, read)
				read += 1
				matchLength += extra
				if extra ~= 255 then
					break
				end
			end
		end
		local from = written - offset
		for index = 0, matchLength - 1 do
			buffer.writeu8(out, written + index, buffer.readu8(out, from + index))
		end
		written += matchLength
	end
	return out
end

type Cursor = { data: buffer, at: number }

local function cursor(data: buffer): Cursor
	return { data = data, at = 0 }
end

local function readU8(state: Cursor): number
	local value = buffer.readu8(state.data, state.at)
	state.at += 1
	return value
end

local function readU32(state: Cursor): number
	local value = buffer.readu32(state.data, state.at)
	state.at += 4
	return value
end

local function readI32(state: Cursor): number
	local value = buffer.readi32(state.data, state.at)
	state.at += 4
	return value
end

local function readString(state: Cursor): string
	local length = readU32(state)
	local value = buffer.readstring(state.data, state.at, length)
	state.at += length
	return value
end

local function readInterleavedU32(state: Cursor, count: number): { number }
	local values: { number } = table.create(count)
	local base = state.at
	for index = 0, count - 1 do
		local value = bit32.bor(
			bit32.lshift(buffer.readu8(state.data, base + index), 24),
			bit32.lshift(buffer.readu8(state.data, base + count + index), 16),
			bit32.lshift(buffer.readu8(state.data, base + 2 * count + index), 8),
			buffer.readu8(state.data, base + 3 * count + index)
		)
		table.insert(values, value)
	end
	state.at = base + 4 * count
	return values
end

local function readReferents(state: Cursor, count: number): { number }
	local values = readInterleavedU32(state, count)
	local accumulated = 0
	for index, raw in values do
		local delta = bit32.rshift(raw, 1)
		if bit32.band(raw, 1) == 1 then
			delta = -delta - 1
		end
		accumulated += delta
		values[index] = accumulated
	end
	return values
end

type Chunk = { name: string, payload: buffer }

local function chunks(bytes: string): { Chunk }
	local data = buffer.fromstring(bytes)
	local total = buffer.len(data)
	local out: { Chunk } = {}
	local at = HEADER_SIZE
	while at + 16 <= total do
		local name = string.gsub(buffer.readstring(data, at, 4), "%z", "")
		local compressedLength = buffer.readu32(data, at + 4)
		local uncompressedLength = buffer.readu32(data, at + 8)
		at += 16
		local stored = if compressedLength == 0 then uncompressedLength else compressedLength
		if at + stored > total then
			error("rbxm: truncated chunk " .. name)
		end
		local payload
		if compressedLength == 0 then
			payload = buffer.create(uncompressedLength)
			buffer.copy(payload, 0, data, at, uncompressedLength)
		elseif buffer.readstring(data, at, 4) == ZSTD_MAGIC then
			error("rbxm: zstd-compressed chunk " .. name .. " is unsupported")
		else
			local slice = buffer.create(compressedLength)
			buffer.copy(slice, 0, data, at, compressedLength)
			payload = decompressLz4(slice, uncompressedLength)
		end
		at += stored
		table.insert(out, { name = name, payload = payload })
		if name == "END" then
			break
		end
	end
	return out
end

local function isBinary(bytes: string): boolean
	return string.sub(bytes, 1, #MAGIC) == MAGIC
end

local function idsInUri(uri: string, property: string): { number }
	local ids: { number } = {}
	local seen: { [number]: boolean } = {}
	local function push(raw: string?)
		local assetId = if raw == nil then nil else tonumber(raw)
		if assetId ~= nil and assetId > 0 and assetId == math.floor(assetId) and not seen[assetId] then
			seen[assetId] = true
			table.insert(ids, assetId)
		end
	end
	for raw in string.gmatch(uri, "rbxassetid://(%d+)") do
		push(raw)
	end
	for raw in string.gmatch(uri, "[Aa]sset/?%?[Ii][Dd]=(%d+)") do
		push(raw)
	end
	if #ids == 0 and CONTENT_PROPERTY_NAMES[property] == true and string.match(uri, "^%d+$") ~= nil then
		push(uri)
	end
	return ids
end

local function read(bytes: string): Document
	local diagnostics: { string } = {}
	if not isBinary(bytes) then
		return {
			ok = false,
			classes = {},
			references = {},
			assetIds = {},
			diagnostics = { "rbxm: missing binary signature" },
		}
	end
	local decoded, parsed = pcall(chunks, bytes)
	if not decoded then
		return { ok = false, classes = {}, references = {}, assetIds = {}, diagnostics = { tostring(parsed) } }
	end
	local shared: { string } = {}
	local classes: { [number]: Class } = {}
	local order: { Class } = {}
	for _, chunk in parsed :: { Chunk } do
		if chunk.name == "SSTR" then
			local state = cursor(chunk.payload)
			readU32(state)
			local count = readU32(state)
			for _ = 1, count do
				state.at += 16
				table.insert(shared, readString(state))
			end
		elseif chunk.name == "INST" then
			local state = cursor(chunk.payload)
			local classId = readI32(state)
			local className = readString(state)
			readU8(state)
			local instanceCount = readI32(state)
			local class: Class = { classId = classId, className = className, instanceCount = instanceCount }
			classes[classId] = class
			table.insert(order, class)
		end
	end
	local references: { Reference } = {}
	local seenReference: { [string]: boolean } = {}
	local function push(
		assetId: number,
		className: string,
		property: string,
		kind: "content" | "shared" | "string",
		uri: string
	)
		local key = table.concat({ tostring(assetId), className, property, kind }, "\0")
		if seenReference[key] then
			return
		end
		seenReference[key] = true
		table.insert(references, {
			assetId = assetId,
			className = className,
			property = property,
			kind = kind,
			uri = uri,
		})
	end
	for _, chunk in parsed :: { Chunk } do
		if chunk.name ~= "PROP" then
			continue
		end
		local state = cursor(chunk.payload)
		local classId = readI32(state)
		local property = readString(state)
		local valueType = readU8(state)
		local class = classes[classId]
		if class == nil then
			table.insert(diagnostics, ("rbxm: property %s references unknown class %d"):format(property, classId))
			continue
		end
		local count = class.instanceCount
		local ok, failure = pcall(function()
			if valueType == TYPE_STRING then
				for _ = 1, count do
					local value = readString(state)
					for _, assetId in idsInUri(value, property) do
						push(assetId, class.className, property, "string", value)
					end
				end
			elseif valueType == TYPE_SHARED_STRING then
				for _, index in readInterleavedU32(state, count) do
					local value = shared[index + 1]
					if value ~= nil then
						for _, assetId in idsInUri(value, property) do
							push(assetId, class.className, property, "shared", value)
						end
					end
				end
			elseif valueType == TYPE_CONTENT then
				local sources = readInterleavedU32(state, count)
				local uriCount = readU32(state)
				local uris: { string } = table.create(uriCount)
				for _ = 1, uriCount do
					table.insert(uris, readString(state))
				end
				local consumed = 0
				for _, source in sources do
					if source ~= CONTENT_SOURCE_URI then
						continue
					end
					consumed += 1
					local uri = uris[consumed]
					if uri == nil then
						continue
					end
					for _, assetId in idsInUri(uri, property) do
						push(assetId, class.className, property, "content", uri)
					end
				end
			end
		end)
		if not ok then
			table.insert(
				diagnostics,
				("rbxm: %s.%s (type %d) refused: %s"):format(class.className, property, valueType, tostring(failure))
			)
		end
	end
	table.sort(order, function(a: Class, b: Class): boolean
		return a.className < b.className
	end)
	table.sort(references, function(a: Reference, b: Reference): boolean
		if a.assetId ~= b.assetId then
			return a.assetId < b.assetId
		end
		if a.className ~= b.className then
			return a.className < b.className
		end
		return a.property < b.property
	end)
	local assetIds: { number } = {}
	local seenId: { [number]: boolean } = {}
	for _, reference in references do
		if not seenId[reference.assetId] then
			seenId[reference.assetId] = true
			table.insert(assetIds, reference.assetId)
		end
	end
	table.sort(diagnostics)
	return {
		ok = #diagnostics == 0,
		classes = order,
		references = references,
		assetIds = assetIds,
		diagnostics = diagnostics,
	}
end

local function instances(bytes: string): Tree
	if not isBinary(bytes) then
		return { ok = false, instances = {}, diagnostics = { "rbxm: missing binary signature" } }
	end
	local decoded, parsed = pcall(chunks, bytes)
	if not decoded then
		return { ok = false, instances = {}, diagnostics = { tostring(parsed) } }
	end
	local diagnostics: { string } = {}
	local shared: { string } = {}
	local referentsByClass: { [number]: { number } } = {}
	local byReferent: { [number]: Instance } = {}
	local order: { Instance } = {}
	for _, chunk in parsed :: { Chunk } do
		if chunk.name == "SSTR" then
			local state = cursor(chunk.payload)
			readU32(state)
			local count = readU32(state)
			for _ = 1, count do
				state.at += 16
				table.insert(shared, readString(state))
			end
		elseif chunk.name == "INST" then
			local state = cursor(chunk.payload)
			local classId = readI32(state)
			local className = readString(state)
			readU8(state)
			local count = readI32(state)
			local referents = readReferents(state, count)
			referentsByClass[classId] = referents
			for _, referent in referents do
				local instance: Instance =
					{ referent = referent, className = className, name = "", parent = -1, content = {} }
				byReferent[referent] = instance
				table.insert(order, instance)
			end
		end
	end
	for _, chunk in parsed :: { Chunk } do
		if chunk.name == "PRNT" then
			local state = cursor(chunk.payload)
			readU8(state)
			local count = readU32(state)
			local children = readReferents(state, count)
			local parents = readReferents(state, count)
			for index = 1, count do
				local child = byReferent[children[index]]
				if child ~= nil then
					child.parent = parents[index]
				end
			end
		elseif chunk.name == "PROP" then
			local state = cursor(chunk.payload)
			local classId = readI32(state)
			local property = readString(state)
			local valueType = readU8(state)
			local referents = referentsByClass[classId]
			if referents == nil then
				table.insert(diagnostics, ("rbxm: property %s references unknown class %d"):format(property, classId))
				continue
			end
			local wanted = property == "Name" or CONTENT_PROPERTY_NAMES[property] == true
			if not wanted then
				continue
			end
			local ok, failure = pcall(function()
				if valueType == TYPE_STRING then
					for _, referent in referents do
						local value = readString(state)
						if property == "Name" then
							byReferent[referent].name = value
						else
							byReferent[referent].content[property] = value
						end
					end
				elseif valueType == TYPE_SHARED_STRING then
					for index, sharedIndex in readInterleavedU32(state, #referents) do
						local value = shared[sharedIndex + 1]
						if value == nil then
							error(("shared string %d is absent"):format(sharedIndex))
						end
						byReferent[referents[index]].content[property] = value
					end
				elseif valueType == TYPE_CONTENT then
					local sources = readInterleavedU32(state, #referents)
					local uriCount = readU32(state)
					local uris: { string } = table.create(uriCount)
					for _ = 1, uriCount do
						table.insert(uris, readString(state))
					end
					local consumed = 0
					for index, source in sources do
						local value = ""
						if source == CONTENT_SOURCE_URI then
							consumed += 1
							if uris[consumed] == nil then
								error(("content uri %d is absent"):format(consumed))
							end
							value = uris[consumed]
						end
						byReferent[referents[index]].content[property] = value
					end
				end
			end)
			if not ok then
				table.insert(
					diagnostics,
					("rbxm: %s (type %d) refused: %s"):format(property, valueType, tostring(failure))
				)
			end
		end
	end
	table.sort(order, function(a: Instance, b: Instance): boolean
		return a.referent < b.referent
	end)
	table.sort(diagnostics)
	return { ok = #diagnostics == 0, instances = order, diagnostics = diagnostics }
end

local function instancePath(tree: Tree, referent: number): string
	local byReferent: { [number]: Instance } = {}
	for _, instance in tree.instances do
		byReferent[instance.referent] = instance
	end
	local names: { string } = {}
	local current = byReferent[referent]
	local guard = 0
	while current ~= nil and guard < 64 do
		table.insert(names, 1, current.name)
		current = byReferent[current.parent]
		guard += 1
	end
	return table.concat(names, ".")
end

return {
	MAGIC = MAGIC,
	CONTENT_PROPERTY_NAMES = CONTENT_PROPERTY_NAMES,
	decompressLz4 = decompressLz4,
	isBinary = isBinary,
	read = read,
	instances = instances,
	instancePath = instancePath,
}
