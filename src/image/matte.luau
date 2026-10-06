--!strict

local Codec = require "./codec"

export type Parameters = { interiorDistance: number, boundaryDistance: number, featherRadius: number }

export type Success = { ok: true, bytes: string, parameters: Parameters }
export type Result = Success | { ok: false, reason: string }

local function distance(image: Codec.Image, source: (number, number) -> boolean): { number }
	local total = image.width * image.height
	local out = table.create(total, 65535)
	for index = 0, total - 1 do
		if source(index, buffer.readu8(image.pixels, index * 4 + 3)) then
			out[index + 1] = 0
		end
	end
	for y = 0, image.height - 1 do
		for x = 0, image.width - 1 do
			local index = y * image.width + x + 1
			local value = out[index]
			if x > 0 then
				value = math.min(value, out[index - 1] + 1)
			end
			if y > 0 then
				value = math.min(value, out[index - image.width] + 1)
			end
			out[index] = value
		end
	end
	for y = image.height - 1, 0, -1 do
		for x = image.width - 1, 0, -1 do
			local index = y * image.width + x + 1
			local value = out[index]
			if x < image.width - 1 then
				value = math.min(value, out[index + 1] + 1)
			end
			if y < image.height - 1 then
				value = math.min(value, out[index + image.width] + 1)
			end
			out[index] = value
		end
	end
	return out
end

local function nearest(image: Codec.Image, distances: { number }, target: number): (number?, number?, number?)
	local width = image.width
	local best = distances[target]
	if best == 65535 or best == 0 then
		return nil
	end
	local index = target
	while best > 0 do
		local x = (index - 1) % width
		local nextIndex: number? = nil
		if x > 0 and distances[index - 1] == best - 1 then
			nextIndex = index - 1
		elseif x < width - 1 and distances[index + 1] == best - 1 then
			nextIndex = index + 1
		elseif index > width and distances[index - width] == best - 1 then
			nextIndex = index - width
		elseif index <= #distances - width and distances[index + width] == best - 1 then
			nextIndex = index + width
		end
		if nextIndex == nil then
			return nil
		end
		index = nextIndex
		best -= 1
	end
	local base = (index - 1) * 4
	return buffer.readu8(image.pixels, base),
		buffer.readu8(image.pixels, base + 1),
		buffer.readu8(image.pixels, base + 2)
end

local function oneBit(image: Codec.Image): boolean
	local sawClear, sawOpaque = false, false
	for index = 0, image.width * image.height - 1 do
		local opacity = buffer.readu8(image.pixels, index * 4 + 3)
		if opacity == 0 then
			sawClear = true
		elseif opacity == 255 then
			sawOpaque = true
		else
			return false
		end
	end
	return sawClear and sawOpaque
end

local function apply(image: Codec.Image, parameters: Parameters): Codec.Image
	local width, height = image.width, image.height
	local pixels = buffer.create(width * height * 4)
	buffer.copy(pixels, 0, image.pixels)
	local output: Codec.Image = { width = width, height = height, channels = 4, pixels = pixels }
	local opaqueDistance = distance(image, function(_index: number, opacity: number): boolean
		return opacity == 255
	end)
	local transparentDistance = distance(image, function(_index: number, opacity: number): boolean
		return opacity == 0
	end)
	for index = 0, width * height - 1 do
		local base = index * 4
		if buffer.readu8(image.pixels, base + 3) == 0 then
			local r, g, b = nearest(image, opaqueDistance, index + 1)
			if r ~= nil then
				buffer.writeu8(pixels, base, r)
				buffer.writeu8(pixels, base + 1, g :: number)
				buffer.writeu8(pixels, base + 2, b :: number)
			end
		end
	end
	local interiorDistance = distance(image, function(index: number, opacity: number): boolean
		return opacity == 255 and transparentDistance[index + 1] >= parameters.interiorDistance
	end)
	for index = 0, width * height - 1 do
		local base = index * 4
		local opacity = buffer.readu8(image.pixels, base + 3)
		if
			(opacity > 0 and opacity < 255)
			or (opacity == 255 and transparentDistance[index + 1] <= parameters.boundaryDistance)
		then
			local r, g, b = nearest(image, interiorDistance, index + 1)
			if r ~= nil then
				buffer.writeu8(pixels, base, r)
				buffer.writeu8(pixels, base + 1, g :: number)
				buffer.writeu8(pixels, base + 2, b :: number)
			end
		end
	end
	if oneBit(image) then
		for index = 0, width * height - 1 do
			local base = index * 4
			local opacity = buffer.readu8(image.pixels, base + 3)
			local signed = if opacity == 255
				then transparentDistance[index + 1] - 0.5
				else -(opaqueDistance[index + 1] - 0.5)
			local feathered = math.clamp(math.floor((0.5 + signed / parameters.featherRadius) * 255 + 0.5), 0, 255)
			buffer.writeu8(pixels, base + 3, feathered)
		end
	end
	return output
end

local function run(codec: Codec.Codec, bytes: string, parameters: Parameters): Result
	local decoded = codec.decode(bytes)
	if not decoded.ok then
		return { ok = false, reason = decoded.reason }
	end
	local image = decoded.image :: Codec.Image
	if image.channels ~= 4 then
		return { ok = false, reason = "matte requires an RGBA PNG" }
	end
	local output = apply(image, parameters)
	return {
		ok = true,
		bytes = Codec.encode(codec, output),
		parameters = parameters,
	}
end

return {
	distance = distance,
	nearest = nearest,
	oneBit = oneBit,
	apply = apply,
	run = run,
}
