--!strict

export type Rgba = { r: number, g: number, b: number, a: number }

export type Image = { width: number, height: number, channels: number, pixels: buffer }

export type Decoded = { ok: true, image: Image } | { ok: false, reason: string }

export type Codec = {
	decode: (bytes: string) -> Decoded,
	encodeRgba: (width: number, height: number, sample: (x: number, y: number) -> Rgba) -> string,
}

export type Digest = (bytes: string) -> string

local function luma(r: number, g: number, b: number): number
	return (299 * r + 587 * g + 114 * b) / 1000
end

local function rounded(value: number): number
	return math.floor(value * 10000 + 0.5) / 10000
end

local function hueSaturation(r: number, g: number, b: number): (number, number, number)
	local red, green, blue = r / 255, g / 255, b / 255
	local maximum, minimum = math.max(red, green, blue), math.min(red, green, blue)
	local lightness = (maximum + minimum) / 2
	local delta = maximum - minimum
	if delta == 0 then
		return 0, 0, lightness
	end
	local saturation = delta / (1 - math.abs(2 * lightness - 1))
	local hue: number
	if maximum == red then
		hue = 60 * (((green - blue) / delta) % 6)
	elseif maximum == green then
		hue = 60 * (((blue - red) / delta) + 2)
	else
		hue = 60 * (((red - green) / delta) + 4)
	end
	return hue, saturation, lightness
end

local function fromHueSaturation(hue: number, saturation: number, lightness: number): (number, number, number)
	local chroma = (1 - math.abs(2 * lightness - 1)) * saturation
	local segment = hue / 60
	local second = chroma * (1 - math.abs((segment % 2) - 1))
	local red, green, blue = 0, 0, 0
	if segment < 1 then
		red, green = chroma, second
	elseif segment < 2 then
		red, green = second, chroma
	elseif segment < 3 then
		green, blue = chroma, second
	elseif segment < 4 then
		green, blue = second, chroma
	elseif segment < 5 then
		red, blue = second, chroma
	else
		red, blue = chroma, second
	end
	local offset = lightness - chroma / 2
	return math.clamp(math.floor((red + offset) * 255 + 0.5), 0, 255),
		math.clamp(math.floor((green + offset) * 255 + 0.5), 0, 255),
		math.clamp(math.floor((blue + offset) * 255 + 0.5), 0, 255)
end

local function copy(image: Image): Image
	local pixels = buffer.create(image.width * image.height * 4)
	buffer.copy(pixels, 0, image.pixels)
	return { width = image.width, height = image.height, channels = 4, pixels = pixels }
end

local function rgba(image: Image): Image
	if image.channels == 4 then
		return copy(image)
	end
	if image.channels ~= 3 then
		error("Generate image codec: an image lane transform requires RGB or RGBA pixels", 2)
	end
	local pixels = buffer.create(image.width * image.height * 4)
	for index = 0, image.width * image.height - 1 do
		local source, target = index * 3, index * 4
		buffer.writeu8(pixels, target, buffer.readu8(image.pixels, source))
		buffer.writeu8(pixels, target + 1, buffer.readu8(image.pixels, source + 1))
		buffer.writeu8(pixels, target + 2, buffer.readu8(image.pixels, source + 2))
		buffer.writeu8(pixels, target + 3, 255)
	end
	return { width = image.width, height = image.height, channels = 4, pixels = pixels }
end

local function encode(codec: Codec, image: Image): string
	return codec.encodeRgba(image.width, image.height, function(x: number, y: number): Rgba
		local base = (y * image.width + x) * 4
		return {
			r = buffer.readu8(image.pixels, base),
			g = buffer.readu8(image.pixels, base + 1),
			b = buffer.readu8(image.pixels, base + 2),
			a = buffer.readu8(image.pixels, base + 3),
		}
	end)
end

local function setLuma(pixels: buffer, base: number, wanted: number)
	local red, green, blue =
		buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2)
	local current = luma(red, green, blue)
	local delta = wanted - current
	buffer.writeu8(pixels, base, math.clamp(math.floor(red + delta + 0.5), 0, 255))
	buffer.writeu8(pixels, base + 1, math.clamp(math.floor(green + delta + 0.5), 0, 255))
	buffer.writeu8(pixels, base + 2, math.clamp(math.floor(blue + delta + 0.5), 0, 255))
end

return {
	luma = luma,
	rounded = rounded,
	hueSaturation = hueSaturation,
	fromHueSaturation = fromHueSaturation,
	copy = copy,
	rgba = rgba,
	encode = encode,
	setLuma = setLuma,
}
