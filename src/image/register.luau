--!strict

local Codec = require "./codec"

export type Config = { codec: Codec.Codec, digest: Codec.Digest }

export type Values = { p5: number, p50: number, p95: number }
export type Target = { hue: number, saturationCeiling: number, values: Values }
export type PercentileBounds = { min: number, max: number, target: number }
export type DeclarationTarget = {
	hue: number,
	saturationCeiling: number,
	value: { p5: PercentileBounds, p50: PercentileBounds, p95: PercentileBounds },
}
export type Facts = {
	width: number,
	height: number,
	opaquePixels: number,
	p5: number,
	p50: number,
	p95: number,
	meanHue: number,
	meanSaturation: number,
	meanLuma: number,
	plateauPixels: number,
}
export type Success = {
	ok: true,
	bytes: string,
	preFacts: Facts,
	postFacts: Facts,
	sha256: { pre: string, post: string },
	parameters: Target,
}

export type Result = Success | { ok: false, reason: string }

local function percentile(histogram: { number }, count: number, fraction: number): number
	local target = math.max(1, math.floor(count * fraction + 0.5))
	local seen = 0
	for value = 0, 255 do
		seen += histogram[value + 1]
		if seen >= target then
			return value
		end
	end
	return 255
end

local function facts(image: Codec.Image): Facts
	local histogram = table.create(256, 0)
	local count, lumaSum = 0, 0
	local hueX, hueY, saturationSum = 0, 0, 0
	for index = 0, image.width * image.height - 1 do
		local base = index * 4
		if buffer.readu8(image.pixels, base + 3) > 5 then
			local red, green, blue =
				buffer.readu8(image.pixels, base),
				buffer.readu8(image.pixels, base + 1),
				buffer.readu8(image.pixels, base + 2)
			local value = Codec.luma(red, green, blue)
			histogram[math.clamp(math.floor(value + 0.5), 0, 255) + 1] += 1
			local hue, saturation = Codec.hueSaturation(red, green, blue)
			local radians = math.rad(hue)
			hueX += math.cos(radians) * saturation
			hueY += math.sin(radians) * saturation
			saturationSum += saturation
			lumaSum += value
			count += 1
		end
	end
	local largest = 0
	for _, seen in histogram do
		largest = math.max(largest, seen)
	end
	local hue = if hueX == 0 and hueY == 0 then 0 else (math.deg(math.atan2(hueY, hueX)) + 360) % 360
	return {
		width = image.width,
		height = image.height,
		opaquePixels = count,
		p5 = percentile(histogram, count, 0.05),
		p50 = percentile(histogram, count, 0.50),
		p95 = percentile(histogram, count, 0.95),
		meanHue = Codec.rounded(hue),
		meanSaturation = Codec.rounded(if count == 0 then 0 else saturationSum / count),
		meanLuma = Codec.rounded(if count == 0 then 0 else lumaSum / count),
		plateauPixels = largest,
	}
end

local function valid(target: Target): string?
	if target.hue < 0 or target.hue >= 360 then
		return "register target hue must be in [0, 360)"
	end
	if target.saturationCeiling < 0 or target.saturationCeiling > 1 then
		return "register saturation ceiling must be in [0, 1]"
	end
	local values = target.values
	if values.p5 < 0 or values.p95 > 255 or values.p5 > values.p50 or values.p50 > values.p95 then
		return "register value targets must be ordered in [0, 255]"
	end
	return nil
end

local function pullColour(image: Codec.Image, target: Target)
	local before = facts(image)
	local shift = (target.hue - before.meanHue + 540) % 360 - 180
	for index = 0, image.width * image.height - 1 do
		local base = index * 4
		if buffer.readu8(image.pixels, base + 3) > 5 then
			local hue, saturation, lightness = Codec.hueSaturation(
				buffer.readu8(image.pixels, base),
				buffer.readu8(image.pixels, base + 1),
				buffer.readu8(image.pixels, base + 2)
			)
			local red, green, blue = Codec.fromHueSaturation(
				(hue + shift + 360) % 360,
				math.min(saturation, target.saturationCeiling),
				lightness
			)
			buffer.writeu8(image.pixels, base, red)
			buffer.writeu8(image.pixels, base + 1, green)
			buffer.writeu8(image.pixels, base + 2, blue)
		end
	end
end

local function relievePlateaus(image: Codec.Image)
	local width, height = image.width, image.height
	local values = table.create(width * height, -1)
	local histogram = table.create(256, 0)
	local opaque = 0
	for index = 0, width * height - 1 do
		local base = index * 4
		if buffer.readu8(image.pixels, base + 3) > 5 then
			local value = math.clamp(
				math.floor(
					Codec.luma(
						buffer.readu8(image.pixels, base),
						buffer.readu8(image.pixels, base + 1),
						buffer.readu8(image.pixels, base + 2)
					) + 0.5
				),
				0,
				255
			)
			values[index + 1] = value
			histogram[value + 1] += 1
			opaque += 1
		end
	end
	local plateau = table.create(256, false)
	local minimum = math.max(16, math.floor(opaque * 0.005))
	for value = 1, 254 do
		if
			histogram[value + 1] >= minimum
			and histogram[value + 1] >= histogram[value]
			and histogram[value + 1] >= histogram[value + 2]
		then
			plateau[value + 1] = true
		end
	end
	local residuals = table.create(width * height, 0)
	local sums, counts = table.create(256, 0), table.create(256, 0)
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local index = y * width + x + 1
			local value = values[index]
			if value >= 0 and plateau[value + 1] then
				local sum, neighbours = 0, 0
				for _, point in { { x - 1, y }, { x + 1, y }, { x, y - 1 }, { x, y + 1 } } do
					local nx, ny = point[1], point[2]
					if nx >= 0 and nx < width and ny >= 0 and ny < height then
						local adjacent = values[ny * width + nx + 1]
						if adjacent >= 0 then
							sum += adjacent - value
							neighbours += 1
						end
					end
				end
				if neighbours > 0 then
					local residual = sum / neighbours
					residuals[index] = residual
					sums[value + 1] += residual
					counts[value + 1] += 1
				end
			end
		end
	end
	for index = 0, width * height - 1 do
		local value = values[index + 1]
		if value >= 0 and plateau[value + 1] and counts[value + 1] > 0 then
			local adjustment = math.clamp((residuals[index + 1] - sums[value + 1] / counts[value + 1]) * 0.75, -8, 8)
			Codec.setLuma(image.pixels, index * 4, value + adjustment)
		end
	end
end

local function remapValues(image: Codec.Image, target: Values)
	local input = facts(image)
	local source = { input.p5, input.p50, input.p95 }
	local destination = { target.p5, target.p50, target.p95 }
	for index = 0, image.width * image.height - 1 do
		local base = index * 4
		if buffer.readu8(image.pixels, base + 3) > 5 then
			local value = Codec.luma(
				buffer.readu8(image.pixels, base),
				buffer.readu8(image.pixels, base + 1),
				buffer.readu8(image.pixels, base + 2)
			)
			local segment = if value <= source[1]
				then 1
				elseif value <= source[2] then 2
				elseif value <= source[3] then 3
				else 4
			local lowSource, highSource, lowDestination, highDestination: number
			if segment == 1 then
				lowSource, highSource, lowDestination, highDestination = 0, source[1], 0, destination[1]
			elseif segment == 2 then
				lowSource, highSource, lowDestination, highDestination =
					source[1], source[2], destination[1], destination[2]
			elseif segment == 3 then
				lowSource, highSource, lowDestination, highDestination =
					source[2], source[3], destination[2], destination[3]
			else
				lowSource, highSource, lowDestination, highDestination = source[3], 255, destination[3], 255
			end
			local wanted = if highSource == lowSource
				then lowDestination
				else lowDestination
					+ (value - lowSource) * (highDestination - lowDestination) / (highSource - lowSource)
			Codec.setLuma(image.pixels, base, wanted)
		end
	end
end

local function apply(image: Codec.Image, target: Target): Codec.Image
	local output = Codec.rgba(image)
	pullColour(output, target)
	relievePlateaus(output)
	remapValues(output, target.values)
	pullColour(output, target)
	return output
end

local function run(config: Config, bytes: string, target: Target): Result
	local invalid = valid(target)
	if invalid ~= nil then
		return { ok = false, reason = invalid }
	end
	local decoded = config.codec.decode(bytes)
	if not decoded.ok then
		return { ok = false, reason = decoded.reason }
	end
	local image = decoded.image :: Codec.Image
	if image.channels ~= 3 and image.channels ~= 4 then
		return { ok = false, reason = "register requires an RGB or RGBA PNG" }
	end
	local source = Codec.rgba(image)
	local output = Codec.encode(config.codec, apply(source, target))
	local post = config.codec.decode(output)
	if not post.ok then
		return { ok = false, reason = "register could not decode its own output" }
	end
	return {
		ok = true,
		bytes = output,
		preFacts = facts(source),
		postFacts = facts(post.image),
		sha256 = { pre = config.digest(bytes), post = config.digest(output) },
		parameters = target,
	}
end

return {
	facts = facts,
	valid = valid,
	apply = apply,
	run = run,
}
