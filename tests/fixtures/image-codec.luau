--!strict

local Image = require "../../src/image"

local SIGNATURE = "\137PNG\r\n\26\n"

local CRC_TABLE: { number } = {}
do
	for n = 0, 255 do
		local c = n
		for _ = 1, 8 do
			if c % 2 == 1 then
				c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
			else
				c = bit32.rshift(c, 1)
			end
		end
		CRC_TABLE[n] = c
	end
end

local function crc32(bytes: string): number
	local c = 0xFFFFFFFF
	for i = 1, #bytes do
		c = bit32.bxor(CRC_TABLE[bit32.band(bit32.bxor(c, string.byte(bytes, i)), 0xFF)], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function adler32(bytes: string): number
	local a, b = 1, 0
	for i = 1, #bytes do
		a = (a + string.byte(bytes, i)) % 65521
		b = (b + a) % 65521
	end
	return b * 65536 + a
end

local function be32(n: number): string
	return string.pack(">I4", n)
end

local function chunk(kind: string, payload: string): string
	local body = kind .. payload
	return be32(#payload) .. body .. be32(crc32(body))
end

local function stored(raw: string): string
	local out = { "\x78\x01" }
	local position, total = 1, #raw
	repeat
		local take = math.min(65535, total - position + 1)
		local final = if position + take > total then 1 else 0
		out[#out + 1] = string.pack("<BI2I2", final, take, bit32.band(bit32.bnot(take), 0xFFFF))
		out[#out + 1] = string.sub(raw, position, position + take - 1)
		position += take
	until position > total
	out[#out + 1] = be32(adler32(raw))
	return table.concat(out)
end

local function encodeRgba(width: number, height: number, sample: (x: number, y: number) -> Image.Rgba): string
	local rows = table.create(height)
	for y = 0, height - 1 do
		local row = table.create(width * 4 + 1)
		row[1] = "\0"
		for x = 0, width - 1 do
			local pixel = sample(x, y)
			row[#row + 1] = string.char(pixel.r, pixel.g, pixel.b, pixel.a)
		end
		rows[y + 1] = table.concat(row)
	end
	local raw = table.concat(rows)
	local header = string.pack(">I4I4BBBBB", width, height, 8, 6, 0, 0, 0)
	return SIGNATURE .. chunk("IHDR", header) .. chunk("IDAT", stored(raw)) .. chunk("IEND", "")
end

local function inflateStored(bytes: string, expected: number): (buffer?, string?)
	local out = buffer.create(expected)
	local written = 0
	local position = 3
	while position <= #bytes do
		local flags = string.byte(bytes, position)
		if flags > 1 then
			return nil, "this fixture codec reads stored deflate blocks only"
		end
		local length = string.unpack("<I2", bytes, position + 1)
		position += 5
		for offset = 0, length - 1 do
			if written >= expected then
				return nil, "the stream carries more bytes than the header declares"
			end
			buffer.writeu8(out, written, string.byte(bytes, position + offset))
			written += 1
		end
		position += length
		if flags == 1 then
			break
		end
	end
	if written ~= expected then
		return nil, ("the stream produced %d bytes where the header declares %d"):format(written, expected)
	end
	return out, nil
end

local function unfilter(raw: buffer, width: number, height: number, channels: number): Image.Decoded
	local stride = width * channels
	local pixels = buffer.create(stride * height)
	local offset = 0
	for y = 0, height - 1 do
		local filter = buffer.readu8(raw, offset)
		offset += 1
		if filter ~= 0 then
			return { ok = false, reason = ("row %d carries filter type %d"):format(y, filter) }
		end
		local rowStart = y * stride
		for index = 0, stride - 1 do
			buffer.writeu8(pixels, rowStart + index, buffer.readu8(raw, offset + index))
		end
		offset += stride
	end
	return { ok = true, image = { width = width, height = height, channels = channels, pixels = pixels } }
end

local function decode(bytes: string): Image.Decoded
	if #bytes < 8 or string.sub(bytes, 1, 8) ~= SIGNATURE then
		return { ok = false, reason = "the file does not carry a PNG signature" }
	end
	local position = 9
	local width, height, channels = 0, 0, 0
	local compressed: { string } = {}
	local sawHeader = false
	while position + 7 <= #bytes do
		local length = string.unpack(">I4", bytes, position)
		local kind = string.sub(bytes, position + 4, position + 7)
		local payloadStart = position + 8
		if payloadStart + length - 1 > #bytes then
			return { ok = false, reason = ("chunk %s declares bytes the file does not carry"):format(kind) }
		end
		if kind == "IHDR" then
			local depth, colorType
			width, height, depth, colorType = string.unpack(">I4I4BB", bytes, payloadStart)
			if depth ~= 8 or (colorType ~= 2 and colorType ~= 6) then
				return { ok = false, reason = "this fixture codec reads 8-bit RGB and RGBA only" }
			end
			channels = if colorType == 6 then 4 else 3
			sawHeader = true
		elseif kind == "IDAT" then
			table.insert(compressed, string.sub(bytes, payloadStart, payloadStart + length - 1))
		elseif kind == "IEND" then
			break
		end
		position = payloadStart + length + 4
	end
	if not sawHeader then
		return { ok = false, reason = "the PNG carries no IHDR chunk" }
	end
	if #compressed == 0 then
		return { ok = false, reason = "the PNG carries no IDAT chunk" }
	end
	local raw, diagnostic = inflateStored(table.concat(compressed), height * (1 + width * channels))
	if raw == nil then
		return { ok = false, reason = diagnostic :: string }
	end
	return unfilter(raw :: buffer, width, height, channels)
end

local function digest(bytes: string): string
	local low, high = 2166136261, 4294967291
	for index = 1, #bytes do
		low = bit32.bxor(low * 16777619 % 4294967296, string.byte(bytes, index))
		high = (high * 31 + string.byte(bytes, index)) % 4294967296
	end
	return string.format("%08x%08x%08x%08x", low, high, bit32.bxor(low, high), (low + high) % 4294967296)
end

local codec: Image.Codec = { decode = decode, encodeRgba = encodeRgba }

local function solid(width: number, height: number, pixel: (x: number, y: number) -> Image.Rgba): string
	return encodeRgba(width, height, pixel)
end

return {
	codec = codec,
	digest = digest,
	solid = solid,
	crc32 = crc32,
	adler32 = adler32,
}
