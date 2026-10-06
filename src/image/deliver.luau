--!strict

local Codec = require "./codec"
local Qa = require "./qa"

local LANCZOS_WINDOW = 3

export type Config = { codec: Codec.Codec, digest: Codec.Digest }

export type Facts = {
	width: number,
	height: number,
	hfScreenPatternPeakRatio: number,
}

export type Parameters = {
	filterWidth: string,
	filterHeight: string,
	declaredWidth: number,
	declaredHeight: number,
}

export type Success = {
	ok: true,
	bytes: string,
	resampled: boolean,
	preFacts: Facts,
	postFacts: Facts,
	sha256: { pre: string, post: string },
	parameters: Parameters,
}

export type Result = Success | { ok: false, reason: string }

local function sinc(x: number): number
	if x == 0 then
		return 1
	end
	local scaled = math.pi * x
	return math.sin(scaled) / scaled
end

local function lanczos(x: number): number
	if x == 0 then
		return 1
	end
	if x <= -LANCZOS_WINDOW or x >= LANCZOS_WINDOW then
		return 0
	end
	return sinc(x) * sinc(x / LANCZOS_WINDOW)
end

export type Contribution = { index: number, weight: number }

local function axisWeights(srcSize: number, dstSize: number): ({ { Contribution } }, string)
	local weights = table.create(dstSize)
	if dstSize == srcSize then
		for index = 0, dstSize - 1 do
			weights[index + 1] = { { index = index, weight = 1 } }
		end
		return weights, "identity"
	end
	local scale = srcSize / dstSize
	if dstSize < srcSize then
		for index = 0, dstSize - 1 do
			local lo, hi = index * scale, (index + 1) * scale
			local contributions: { Contribution } = {}
			local first, last = math.floor(lo), math.min(srcSize - 1, math.ceil(hi) - 1)
			local total = 0
			for source = first, last do
				local overlap = math.min(hi, source + 1) - math.max(lo, source)
				if overlap > 0 then
					local clamped = math.clamp(source, 0, srcSize - 1)
					table.insert(contributions, { index = clamped, weight = overlap })
					total += overlap
				end
			end
			if total == 0 then
				contributions = { { index = math.clamp(first, 0, srcSize - 1), weight = 1 } }
			else
				for _, contribution in contributions do
					contribution.weight /= total
				end
			end
			weights[index + 1] = contributions
		end
		return weights, "area"
	end
	for index = 0, dstSize - 1 do
		local center = (index + 0.5) * scale - 0.5
		local first, last = math.floor(center - LANCZOS_WINDOW) + 1, math.floor(center + LANCZOS_WINDOW)
		local contributions: { Contribution } = {}
		local total = 0
		for source = first, last do
			local weight = lanczos(source - center)
			if weight ~= 0 then
				local clamped = math.clamp(source, 0, srcSize - 1)
				table.insert(contributions, { index = clamped, weight = weight })
				total += weight
			end
		end
		if total == 0 then
			contributions = { { index = math.clamp(math.floor(center + 0.5), 0, srcSize - 1), weight = 1 } }
		else
			for _, contribution in contributions do
				contribution.weight /= total
			end
		end
		weights[index + 1] = contributions
	end
	return weights, "lanczos3"
end

local function resize(image: Codec.Image, dstWidth: number, dstHeight: number): (Codec.Image, string, string)
	local srcWidth, srcHeight = image.width, image.height
	local columnWeights, widthFilter = axisWeights(srcWidth, dstWidth)
	local rowWeights, heightFilter = axisWeights(srcHeight, dstHeight)
	local horizontal = table.create(dstWidth * srcHeight * 4, 0)
	for y = 0, srcHeight - 1 do
		for outX = 0, dstWidth - 1 do
			local r, g, b, a = 0, 0, 0, 0
			for _, contribution in columnWeights[outX + 1] do
				local base = (y * srcWidth + contribution.index) * 4
				r += buffer.readu8(image.pixels, base) * contribution.weight
				g += buffer.readu8(image.pixels, base + 1) * contribution.weight
				b += buffer.readu8(image.pixels, base + 2) * contribution.weight
				a += buffer.readu8(image.pixels, base + 3) * contribution.weight
			end
			local out = (y * dstWidth + outX) * 4
			horizontal[out + 1] = r
			horizontal[out + 2] = g
			horizontal[out + 3] = b
			horizontal[out + 4] = a
		end
	end
	local pixels = buffer.create(dstWidth * dstHeight * 4)
	for outY = 0, dstHeight - 1 do
		for outX = 0, dstWidth - 1 do
			local r, g, b, a = 0, 0, 0, 0
			for _, contribution in rowWeights[outY + 1] do
				local base = (contribution.index * dstWidth + outX) * 4
				r += horizontal[base + 1] * contribution.weight
				g += horizontal[base + 2] * contribution.weight
				b += horizontal[base + 3] * contribution.weight
				a += horizontal[base + 4] * contribution.weight
			end
			local out = (outY * dstWidth + outX) * 4
			buffer.writeu8(pixels, out, math.clamp(math.floor(r + 0.5), 0, 255))
			buffer.writeu8(pixels, out + 1, math.clamp(math.floor(g + 0.5), 0, 255))
			buffer.writeu8(pixels, out + 2, math.clamp(math.floor(b + 0.5), 0, 255))
			buffer.writeu8(pixels, out + 3, math.clamp(math.floor(a + 0.5), 0, 255))
		end
	end
	return { width = dstWidth, height = dstHeight, channels = 4, pixels = pixels }, widthFilter, heightFilter
end

local function facts(image: Codec.Image): Facts
	local screen = Qa.highFrequencyScreen(image)
	return {
		width = image.width,
		height = image.height,
		hfScreenPatternPeakRatio = screen.hfScreenPatternPeakRatio,
	}
end

local function run(config: Config, bytes: string, declaredWidth: number, declaredHeight: number): Result
	if
		type(declaredWidth) ~= "number"
		or type(declaredHeight) ~= "number"
		or declaredWidth < 1
		or declaredHeight < 1
		or declaredWidth % 1 ~= 0
		or declaredHeight % 1 ~= 0
	then
		return { ok = false, reason = "deliver requires whole positive declared width and height" }
	end
	local decoded = config.codec.decode(bytes)
	if not decoded.ok then
		return { ok = false, reason = decoded.reason }
	end
	local image = decoded.image :: Codec.Image
	if image.channels ~= 3 and image.channels ~= 4 then
		return { ok = false, reason = "deliver requires an RGB or RGBA PNG" }
	end
	local source = Codec.rgba(image)
	local resampled, widthFilter, heightFilter = resize(source, declaredWidth, declaredHeight)
	local output = Codec.encode(config.codec, resampled)
	local post = config.codec.decode(output)
	if not post.ok then
		return { ok = false, reason = "deliver could not decode its own output" }
	end
	return {
		ok = true,
		bytes = output,
		resampled = source.width ~= declaredWidth or source.height ~= declaredHeight,
		preFacts = facts(source),
		postFacts = facts(post.image),
		sha256 = { pre = config.digest(bytes), post = config.digest(output) },
		parameters = {
			filterWidth = widthFilter,
			filterHeight = heightFilter,
			declaredWidth = declaredWidth,
			declaredHeight = declaredHeight,
		},
	}
end

return {
	sinc = sinc,
	lanczos = lanczos,
	axisWeights = axisWeights,
	resize = resize,
	facts = facts,
	run = run,
}
