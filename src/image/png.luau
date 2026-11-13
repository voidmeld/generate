--!strict

local Codec = require "./codec"

export type Rgba = Codec.Rgba
export type Image = Codec.Image
export type Decoded = Codec.Decoded

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

local function unpackNumber(format: string, bytes: string, position: number): number
	local value = string.unpack(format, bytes, position)
	assert(type(value) == "number", "PNG integer format returned a non-number")
	return value
end

local function chunk(kind: string, payload: string): string
	local body = kind .. payload
	return be32(#payload) .. body .. be32(crc32(body))
end

local function zlibStored(raw: string): string
	local out = { "\x78\x01" }
	local pos, n = 1, #raw
	repeat
		local take = math.min(65535, n - pos + 1)
		local final = if pos + take > n then 1 else 0
		out[#out + 1] = string.pack("<BI2I2", final, take, bit32.band(bit32.bnot(take), 0xFFFF))
		out[#out + 1] = string.sub(raw, pos, pos + take - 1)
		pos += take
	until pos > n
	out[#out + 1] = be32(adler32(raw))
	return table.concat(out)
end

local function encodeRgba(width: number, height: number, pixel: (x: number, y: number) -> Rgba): string
	local rows = table.create(height)
	for y = 0, height - 1 do
		local row = table.create(width * 4 + 1)
		row[1] = "\0"
		for x = 0, width - 1 do
			local c = pixel(x, y)
			row[#row + 1] = string.char(c.r, c.g, c.b, c.a)
		end
		rows[y + 1] = table.concat(row)
	end
	local raw = table.concat(rows)
	local ihdr = string.pack(">I4I4BBBBB", width, height, 8, 6, 0, 0, 0)
	return "\137PNG\r\n\26\n" .. chunk("IHDR", ihdr) .. chunk("IDAT", zlibStored(raw)) .. chunk("IEND", "")
end

local MAX_BITS = 15

local LENGTH_BASE: { number } = {
	3,
	4,
	5,
	6,
	7,
	8,
	9,
	10,
	11,
	13,
	15,
	17,
	19,
	23,
	27,
	31,
	35,
	43,
	51,
	59,
	67,
	83,
	99,
	115,
	131,
	163,
	195,
	227,
	258,
}
local LENGTH_EXTRA: { number } =
	{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE: { number } = {
	1,
	2,
	3,
	4,
	5,
	7,
	9,
	13,
	17,
	25,
	33,
	49,
	65,
	97,
	129,
	193,
	257,
	385,
	513,
	769,
	1025,
	1537,
	2049,
	3073,
	4097,
	6145,
	8193,
	12289,
	16385,
	24577,
}
local DIST_EXTRA: { number } =
	{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_LENGTH_ORDER: { number } = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

export type Huffman = { counts: { [number]: number }, symbols: { [number]: number } }

local function huffman(lengths: { [number]: number }, count: number): Huffman
	local counts: { [number]: number } = {}
	for length = 0, MAX_BITS do
		counts[length] = 0
	end
	for index = 0, count - 1 do
		counts[lengths[index]] += 1
	end
	counts[0] = 0
	local offsets: { [number]: number } = { [1] = 0 }
	for length = 1, MAX_BITS - 1 do
		offsets[length + 1] = offsets[length] + counts[length]
	end
	local symbols: { [number]: number } = {}
	for index = 0, count - 1 do
		local length = lengths[index]
		if length ~= 0 then
			symbols[offsets[length]] = index
			offsets[length] += 1
		end
	end
	return { counts = counts, symbols = symbols }
end

export type Inflated = { ok: true, bytes: buffer } | { ok: false, reason: string }

local function inflate(bytes: string, expected: number): Inflated
	if #bytes < 2 then
		return { ok = false, reason = "the compressed stream is too short to carry a zlib header" }
	end
	local cmf = string.byte(bytes, 1)
	local flg = string.byte(bytes, 2)
	if cmf % 16 ~= 8 then
		return { ok = false, reason = "the compressed stream is not zlib deflate" }
	end
	if (cmf * 256 + flg) % 31 ~= 0 then
		return { ok = false, reason = "the zlib header check bits do not agree" }
	end
	if flg % 64 >= 32 then
		return { ok = false, reason = "the zlib stream needs a preset dictionary, which this decoder has none of" }
	end

	local out = buffer.create(expected)
	local written = 0
	local position = 3
	local bitBuffer, bitCount = 0, 0

	local function readBit(): number
		if bitCount == 0 then
			if position > #bytes then
				error("the deflate stream ended inside a code", 0)
			end
			bitBuffer = string.byte(bytes, position)
			position += 1
			bitCount = 8
		end
		local bit = bitBuffer % 2
		bitBuffer = (bitBuffer - bit) // 2
		bitCount -= 1
		return bit
	end

	local function readBits(width: number): number
		local value, weight = 0, 1
		for _ = 1, width do
			value += readBit() * weight
			weight *= 2
		end
		return value
	end

	local function put(byte: number)
		if written >= expected then
			error("the deflate stream produced more bytes than the image header declares", 0)
		end
		buffer.writeu8(out, written, byte)
		written += 1
	end

	local function decodeSymbol(table_: Huffman): number
		local code, first, index = 0, 0, 0
		for length = 1, MAX_BITS do
			code += readBit()
			local count = table_.counts[length]
			if code - first < count then
				return table_.symbols[index + code - first]
			end
			index += count
			first = (first + count) * 2
			code *= 2
		end
		error("the deflate stream carries a Huffman code no table decodes", 0)
	end

	local fixedLiterals: Huffman? = nil
	local fixedDistances: Huffman? = nil
	local function fixedTables(): (Huffman, Huffman)
		if fixedLiterals == nil then
			local literals: { [number]: number } = {}
			for symbol = 0, 143 do
				literals[symbol] = 8
			end
			for symbol = 144, 255 do
				literals[symbol] = 9
			end
			for symbol = 256, 279 do
				literals[symbol] = 7
			end
			for symbol = 280, 287 do
				literals[symbol] = 8
			end
			local distances: { [number]: number } = {}
			for symbol = 0, 29 do
				distances[symbol] = 5
			end
			fixedLiterals = huffman(literals, 288)
			fixedDistances = huffman(distances, 30)
		end
		return assert(fixedLiterals), assert(fixedDistances)
	end

	local function dynamicTables(): (Huffman, Huffman)
		local literalCount = readBits(5) + 257
		local distanceCount = readBits(5) + 1
		local codeCount = readBits(4) + 4
		if literalCount > 286 or distanceCount > 30 then
			error("the deflate stream declares more codes than RFC 1951 allows", 0)
		end
		local codeLengths: { [number]: number } = {}
		for symbol = 0, 18 do
			codeLengths[symbol] = 0
		end
		for index = 1, codeCount do
			codeLengths[CODE_LENGTH_ORDER[index]] = readBits(3)
		end
		local codeTable = huffman(codeLengths, 19)
		local lengths: { [number]: number } = {}
		local index = 0
		while index < literalCount + distanceCount do
			local symbol = decodeSymbol(codeTable)
			if symbol < 16 then
				lengths[index] = symbol
				index += 1
			else
				local repeated, times
				if symbol == 16 then
					if index == 0 then
						error("the deflate stream repeats a code length before declaring one", 0)
					end
					repeated = lengths[index - 1]
					times = 3 + readBits(2)
				elseif symbol == 17 then
					repeated = 0
					times = 3 + readBits(3)
				else
					repeated = 0
					times = 11 + readBits(7)
				end
				for _ = 1, times do
					if index >= literalCount + distanceCount then
						error("the deflate stream repeats past its own code count", 0)
					end
					lengths[index] = repeated
					index += 1
				end
			end
		end
		local literalLengths: { [number]: number } = {}
		for symbol = 0, literalCount - 1 do
			literalLengths[symbol] = lengths[symbol]
		end
		local distanceLengths: { [number]: number } = {}
		for symbol = 0, distanceCount - 1 do
			distanceLengths[symbol] = lengths[literalCount + symbol]
		end
		return huffman(literalLengths, literalCount), huffman(distanceLengths, distanceCount)
	end

	local ok, failure = pcall(function()
		repeat
			local final = readBit()
			local kind = readBits(2)
			if kind == 0 then
				bitCount = 0
				if position + 3 > #bytes then
					error("the deflate stream ended inside a stored block header", 0)
				end
				local length = unpackNumber("<I2", bytes, position)
				position += 4
				for offset = 0, length - 1 do
					if position + offset > #bytes then
						error("the deflate stream ended inside a stored block", 0)
					end
					put(string.byte(bytes, position + offset))
				end
				position += length
			elseif kind == 1 or kind == 2 then
				local literals, distances
				if kind == 1 then
					literals, distances = fixedTables()
				else
					literals, distances = dynamicTables()
				end
				while true do
					local symbol = decodeSymbol(literals)
					if symbol < 256 then
						put(symbol)
					elseif symbol == 256 then
						break
					else
						local lengthSymbol = symbol - 256
						if lengthSymbol > 29 then
							error("the deflate stream carries a reserved length symbol", 0)
						end
						local length = LENGTH_BASE[lengthSymbol] + readBits(LENGTH_EXTRA[lengthSymbol])
						local distanceSymbol = decodeSymbol(distances) + 1
						if distanceSymbol < 1 or distanceSymbol > 30 then
							error("the deflate stream carries a reserved distance symbol", 0)
						end
						local distance = DIST_BASE[distanceSymbol] + readBits(DIST_EXTRA[distanceSymbol])
						if distance > written then
							error("the deflate stream refers behind the start of its own output", 0)
						end
						for _ = 1, length do
							put(buffer.readu8(out, written - distance))
						end
					end
				end
			else
				error("the deflate stream carries a reserved block type", 0)
			end
		until final == 1
	end)
	if not ok then
		return { ok = false, reason = tostring(failure) }
	end
	if written ~= expected then
		return {
			ok = false,
			reason = ("the deflate stream produced %d bytes where the image header declares %d"):format(
				written,
				expected
			),
		}
	end
	return { ok = true, bytes = out }
end

local function refuse(reason: string): Decoded
	return { ok = false, reason = reason }
end

local function unfilter(raw: buffer, width: number, height: number, channels: number): Decoded
	local stride = width * channels
	local pixels = buffer.create(stride * height)
	local offset = 0
	for y = 0, height - 1 do
		local filter = buffer.readu8(raw, offset)
		offset += 1
		local rowStart = y * stride
		local priorStart = rowStart - stride
		for index = 0, stride - 1 do
			local x = buffer.readu8(raw, offset + index)
			local left = if index >= channels then buffer.readu8(pixels, rowStart + index - channels) else 0
			local up = if y > 0 then buffer.readu8(pixels, priorStart + index) else 0
			local corner = if y > 0 and index >= channels
				then buffer.readu8(pixels, priorStart + index - channels)
				else 0
			local value: number
			if filter == 0 then
				value = x
			elseif filter == 1 then
				value = x + left
			elseif filter == 2 then
				value = x + up
			elseif filter == 3 then
				value = x + (left + up) // 2
			elseif filter == 4 then
				local predicted = left + up - corner
				local toLeft = math.abs(predicted - left)
				local toUp = math.abs(predicted - up)
				local toCorner = math.abs(predicted - corner)
				if toLeft <= toUp and toLeft <= toCorner then
					value = x + left
				elseif toUp <= toCorner then
					value = x + up
				else
					value = x + corner
				end
			else
				return refuse(("row %d carries filter type %d, which PNG does not define"):format(y, filter))
			end
			buffer.writeu8(pixels, rowStart + index, value % 256)
		end
		offset += stride
	end
	return { ok = true, image = { width = width, height = height, channels = channels, pixels = pixels } }
end

local function decode(bytes: string): Decoded
	if #bytes < 8 or string.sub(bytes, 1, 8) ~= "\137PNG\r\n\26\n" then
		return refuse "the file does not carry a PNG signature"
	end
	local position = 9
	local width, height, channels = 0, 0, 0
	local compressed: { string } = {}
	local sawHeader = false
	while position + 7 <= #bytes do
		local length = unpackNumber(">I4", bytes, position)
		local kind = string.sub(bytes, position + 4, position + 7)
		local payloadStart = position + 8
		if payloadStart + length - 1 > #bytes then
			return refuse(("chunk %s declares %d bytes the file does not carry"):format(kind, length))
		end
		if kind == "IHDR" then
			if length < 13 then
				return refuse "the IHDR chunk is shorter than PNG defines"
			end
			width = unpackNumber(">I4", bytes, payloadStart)
			height = unpackNumber(">I4", bytes, payloadStart + 4)
			local depth, colorType, compression, filter, interlace =
				string.byte(bytes, payloadStart + 8, payloadStart + 12)
			if width == 0 or height == 0 then
				return refuse "the PNG declares a zero dimension"
			end
			if depth ~= 8 then
				return refuse(("the PNG carries %d-bit samples; this decoder reads 8-bit only"):format(depth))
			end
			if colorType == 2 then
				channels = 3
			elseif colorType == 6 then
				channels = 4
			else
				return refuse(
					("the PNG carries colour type %d; this decoder reads RGB (2) and RGBA (6) only"):format(colorType)
				)
			end
			if compression ~= 0 or filter ~= 0 then
				return refuse "the PNG declares a compression or filter method PNG does not define"
			end
			if interlace ~= 0 then
				return refuse "the PNG is interlaced; this decoder reads non-interlaced only"
			end
			sawHeader = true
		elseif kind == "IDAT" then
			table.insert(compressed, string.sub(bytes, payloadStart, payloadStart + length - 1))
		elseif kind == "IEND" then
			break
		end
		position = payloadStart + length + 4
	end
	if not sawHeader then
		return refuse "the PNG carries no IHDR chunk"
	end
	if #compressed == 0 then
		return refuse "the PNG carries no IDAT chunk"
	end
	local expected = height * (1 + width * channels)
	local inflated = inflate(table.concat(compressed), expected)
	if inflated.ok == false then
		return refuse(inflated.reason)
	end
	return unfilter(inflated.bytes, width, height, channels)
end

local function sample(image: Image, x: number, y: number, channel: number): number
	return buffer.readu8(image.pixels, (y * image.width + x) * image.channels + channel)
end

return {
	decode = decode,
	encodeRgba = encodeRgba,
	sample = sample,
}
