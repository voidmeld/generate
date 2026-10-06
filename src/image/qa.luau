--!strict

local Codec = require "./codec"
local Register = require "./register"

local EDGE_BAND = 32
local EDGE_MATCH_BAND = 8
local EDGE_MIRROR_BAND = 16

export type Thresholds = {
	opaqueAlpha: number,
	transparentAlpha: number,
	keyResidueSaturation: number,
	gutterLumaRange: number,
	brightMaximaLuma: number,
	chromaSaturationFloor: number,
	maxWrapSeamRatio: number,
	maxInteriorSeamRatio: number,
	maxFractionalSeamRatio: number,
	maxUnlitVignetteRatio: number,
	maxUnlitLightingGradient: number,
	maxBrightMaximaFraction: number,
	minEdgeBlurRatio: number,
	maxHfScreenPatternPeakRatio: number,
	maxEdgeMirrorCorrelation: number,
	minMedianLuma: number,
	minPairedLuminanceRatio: number,
	maxPairedLuminanceRatio: number,
	minPairedRegistrationCorrelation: number,
	minSemiTransparentFraction: number,
	maxKeyResidueFraction: number,
	maxHaloRatio: number,
	maxPanels: number,
	minGutterBand: number,
	warnVignetteRatio: number,
	warnLightingGradient: number,
	warnLumaSpread: number,
}

export type Config = { schema: string, codec: Codec.Codec, thresholds: Thresholds }

local THRESHOLD_NAMES: { string } = {
	"opaqueAlpha",
	"transparentAlpha",
	"keyResidueSaturation",
	"gutterLumaRange",
	"brightMaximaLuma",
	"chromaSaturationFloor",
	"maxWrapSeamRatio",
	"maxInteriorSeamRatio",
	"maxFractionalSeamRatio",
	"maxUnlitVignetteRatio",
	"maxUnlitLightingGradient",
	"maxBrightMaximaFraction",
	"minEdgeBlurRatio",
	"maxHfScreenPatternPeakRatio",
	"maxEdgeMirrorCorrelation",
	"minMedianLuma",
	"minPairedLuminanceRatio",
	"maxPairedLuminanceRatio",
	"minPairedRegistrationCorrelation",
	"minSemiTransparentFraction",
	"maxKeyResidueFraction",
	"maxHaloRatio",
	"maxPanels",
	"minGutterBand",
	"warnVignetteRatio",
	"warnLightingGradient",
	"warnLumaSpread",
}

local function requireThresholds(config: Config)
	local limits: unknown = if type(config) == "table" then config.thresholds else nil
	if type(limits) ~= "table" then
		error("Generate image QA requires the consumer to declare its thresholds table", 3)
	end
	for _, name in THRESHOLD_NAMES do
		local value = (limits :: { [string]: unknown })[name]
		if type(value) ~= "number" or value ~= value then
			error(("Generate image QA requires the consumer to declare threshold %s as a number"):format(name), 3)
		end
	end
end

local luma = Codec.luma
local rounded = Codec.rounded

export type HueBand = { fromDegrees: number, toDegrees: number, maxFraction: number }

export type Declaration = {
	id: string,
	role: string,
	tiles: boolean,
	transparentBackground: boolean,
	singleSubject: boolean,
	unlit: boolean?,
	pairedGroup: string?,
	hueBand: HueBand?,
	limitBrightMaxima: boolean?,
	declaredWidth: number?,
	declaredHeight: number?,
	dark: boolean?,
	registerTarget: Register.DeclarationTarget?,
}

export type Refusal = {
	fact: string,
	detail: string,
	measured: number,
	threshold: number,
}

export type Assessment = {
	artifactId: string,
	path: string,
	facts: { [string]: string | number | boolean | nil },
	refusals: { Refusal },
	warnings: { string },
}

local function refusal(fact: string, detail: string, measured: number, threshold: number): Refusal
	return { fact = fact, detail = detail, measured = measured, threshold = threshold }
end

local function tileability(image: Codec.Image): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local function lumaAt(x: number, y: number): number
		local base = (y * width + x) * channels
		return luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
	end
	local seamX, interiorX = 0, 0
	for y = 0, height - 1 do
		seamX += math.abs(lumaAt(0, y) - lumaAt(width - 1, y))
		local previous = lumaAt(0, y)
		for x = 1, width - 1 do
			local current = lumaAt(x, y)
			interiorX += math.abs(current - previous)
			previous = current
		end
	end
	local seamY, interiorY = 0, 0
	for x = 0, width - 1 do
		seamY += math.abs(lumaAt(x, 0) - lumaAt(x, height - 1))
	end
	for y = 1, height - 1 do
		for x = 0, width - 1 do
			interiorY += math.abs(lumaAt(x, y) - lumaAt(x, y - 1))
		end
	end
	seamX /= height
	seamY /= width
	interiorX /= height * math.max(width - 1, 1)
	interiorY /= width * math.max(height - 1, 1)
	local ratioX = seamX / math.max(interiorX, 0.0001)
	local ratioY = seamY / math.max(interiorY, 0.0001)
	return {
		wrapSeamDeltaX = rounded(seamX),
		wrapSeamDeltaY = rounded(seamY),
		interiorAdjacentDeltaX = rounded(interiorX),
		interiorAdjacentDeltaY = rounded(interiorY),
		wrapSeamRatioX = rounded(ratioX),
		wrapSeamRatioY = rounded(ratioY),
		wrapSeamRatio = rounded(math.max(ratioX, ratioY)),
	}
end

local function median(values: { number }): number
	table.sort(values)
	local count = #values
	if count == 0 then
		return 0
	end
	if count % 2 == 1 then
		return values[(count + 1) // 2]
	end
	return (values[count // 2] + values[count // 2 + 1]) / 2
end

local function rgbToHueSaturation(r: number, g: number, b: number): (number, number)
	local high, low = math.max(r, g, b) / 255, math.min(r, g, b) / 255
	local delta = high - low
	if delta == 0 then
		return 0, 0
	end
	local hue: number
	if high == r / 255 then
		hue = 60 * (((g - b) / 255 / delta) % 6)
	elseif high == g / 255 then
		hue = 60 * ((b - r) / 255 / delta + 2)
	else
		hue = 60 * ((r - g) / 255 / delta + 4)
	end
	return hue, delta / math.max(high, 0.0001)
end

local function brightMaxima(image: Codec.Image, limits: Thresholds): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local count = 0
	for y = 1, height - 2 do
		for x = 1, width - 2 do
			local base = (y * width + x) * channels
			local value =
				luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
			if value > limits.brightMaximaLuma then
				local maximum, strict = true, false
				for dy = -1, 1 do
					for dx = -1, 1 do
						if dx ~= 0 or dy ~= 0 then
							local neighborBase = ((y + dy) * width + x + dx) * channels
							local neighbor = luma(
								buffer.readu8(pixels, neighborBase),
								buffer.readu8(pixels, neighborBase + 1),
								buffer.readu8(pixels, neighborBase + 2)
							)
							if neighbor > value then
								maximum = false
							elseif neighbor < value then
								strict = true
							end
						end
					end
				end
				if maximum and strict then
					count += 1
				end
			end
		end
	end
	return {
		brightMaximaTexels = count,
		brightMaximaFraction = rounded(count / math.max(width * height, 1)),
	}
end

local function inHueBand(hue: number, band: HueBand): boolean
	if band.fromDegrees <= band.toDegrees then
		return hue >= band.fromDegrees and hue <= band.toDegrees
	end
	return hue >= band.fromDegrees or hue <= band.toDegrees
end

local function chroma(image: Codec.Image, limits: Thresholds, band: HueBand?): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local inside, counted, hueX, hueY, saturation = 0, 0, 0, 0, 0
	for index = 0, width * height - 1 do
		local base = index * channels
		if channels < 4 or buffer.readu8(pixels, base + 3) > limits.transparentAlpha then
			local hue, sat = rgbToHueSaturation(
				buffer.readu8(pixels, base),
				buffer.readu8(pixels, base + 1),
				buffer.readu8(pixels, base + 2)
			)
			if sat > limits.chromaSaturationFloor then
				local angle = math.rad(hue)
				hueX += math.cos(angle) * sat
				hueY += math.sin(angle) * sat
				if band ~= nil and inHueBand(hue, band) then
					inside += 1
				end
			end
			saturation += sat
			counted += 1
		end
	end
	local meanHue = if hueX == 0 and hueY == 0 then 0 else (math.deg(math.atan2(hueY, hueX)) + 360) % 360
	local facts: { [string]: number } = {
		meanHue = rounded(meanHue),
		meanSaturation = rounded(saturation / math.max(counted, 1)),
	}
	if band ~= nil then
		facts.hueBandFraction = rounded(inside / math.max(counted, 1))
	end
	return facts
end

local function edgeBlur(image: Codec.Image): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local band = math.min(EDGE_BAND, math.max(1, math.min(width, height) // 4))
	local outerSum, outerCount, interiorSum, interiorCount = 0, 0, 0, 0
	local function valueAt(x: number, y: number): number
		local base = (y * width + x) * channels
		return luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
	end
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local sum, sumSquares, samples = 0, 0, 0
			for dy = -1, 1 do
				for dx = -1, 1 do
					local sample = valueAt(math.clamp(x + dx, 0, width - 1), math.clamp(y + dy, 0, height - 1))
					sum += sample
					sumSquares += sample * sample
					samples += 1
				end
			end
			local variance = math.max(0, sumSquares / samples - (sum / samples) ^ 2)
			local deviation = math.sqrt(variance)
			if x < band or y < band or x >= width - band or y >= height - band then
				outerSum += deviation
				outerCount += 1
			else
				interiorSum += deviation
				interiorCount += 1
			end
		end
	end
	local outer = outerSum / math.max(outerCount, 1)
	local interior = interiorSum / math.max(interiorCount, 1)
	return {
		edgeBlurBand = band,
		edgeLocalStd = rounded(outer),
		interiorLocalStd = rounded(interior),
		edgeBlurRatio = rounded(outer / math.max(interior, 0.0001)),
	}
end

local function edgeCopies(image: Codec.Image): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local band = math.min(EDGE_MATCH_BAND, math.max(1, math.min(width, height) // 2))
	local function same(xA: number, yA: number, xB: number, yB: number): boolean
		local a, b = (yA * width + xA) * channels, (yB * width + xB) * channels
		for channel = 0, channels - 1 do
			if buffer.readu8(pixels, a + channel) ~= buffer.readu8(pixels, b + channel) then
				return false
			end
		end
		return true
	end
	local duplicateRows, mirroredRows, duplicateColumns, mirroredColumns = true, true, true, true
	for depth = 0, band - 1 do
		for x = 0, width - 1 do
			duplicateRows = duplicateRows and same(x, depth, x, height - 1 - depth)
			mirroredRows = mirroredRows and same(x, depth, width - 1 - x, height - 1 - depth)
		end
		for y = 0, height - 1 do
			duplicateColumns = duplicateColumns and same(depth, y, width - 1 - depth, y)
			mirroredColumns = mirroredColumns and same(depth, y, width - 1 - depth, height - 1 - y)
		end
	end
	return {
		edgeMatchBand = band,
		duplicatedEdgeRows = if duplicateRows then 1 else 0,
		mirroredEdgeRows = if mirroredRows then 1 else 0,
		duplicatedEdgeColumns = if duplicateColumns then 1 else 0,
		mirroredEdgeColumns = if mirroredColumns then 1 else 0,
	}
end

local function correlation(first: { number }, second: { number }): number
	local sumA, sumB, sumAA, sumBB, sumAB = 0, 0, 0, 0, 0
	for index, value in first do
		local other = second[index]
		sumA += value
		sumB += other
		sumAA += value * value
		sumBB += other * other
		sumAB += value * other
	end
	local count = #first
	return (sumAB - sumA * sumB / count)
		/ math.max(math.sqrt((sumAA - sumA * sumA / count) * (sumBB - sumB * sumB / count)), 0.0001)
end

local function edgeMirror(image: Codec.Image): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local band = math.min(EDGE_MIRROR_BAND, math.max(1, math.min(width, height) // 2))
	local rowsA: { number }, rowsDirect: { number }, rowsSpatial: { number } = {}, {}, {}
	local columnsA: { number }, columnsDirect: { number }, columnsSpatial: { number } = {}, {}, {}
	local function valueAt(x: number, y: number): number
		local base = (y * width + x) * channels
		return luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
	end
	for depth = 0, band - 1 do
		for x = 0, width - 1 do
			table.insert(rowsA, valueAt(x, depth))
			table.insert(rowsDirect, valueAt(x, height - 1 - depth))
			table.insert(rowsSpatial, valueAt(width - 1 - x, height - 1 - depth))
		end
		for y = 0, height - 1 do
			table.insert(columnsA, valueAt(depth, y))
			table.insert(columnsDirect, valueAt(width - 1 - depth, y))
			table.insert(columnsSpatial, valueAt(width - 1 - depth, height - 1 - y))
		end
	end
	local rowCorrelation, rowSpatialCorrelation = correlation(rowsA, rowsDirect), correlation(rowsA, rowsSpatial)
	local columnCorrelation, columnSpatialCorrelation =
		correlation(columnsA, columnsDirect), correlation(columnsA, columnsSpatial)
	return {
		edgeMirrorBand = band,
		edgeMirrorRowsCorrelation = rounded(rowCorrelation),
		edgeMirrorColumnsCorrelation = rounded(columnCorrelation),
		edgeMirrorRowsSpatialCorrelation = rounded(rowSpatialCorrelation),
		edgeMirrorColumnsSpatialCorrelation = rounded(columnSpatialCorrelation),
		edgeMirrorCorrelation = rounded(
			math.max(rowCorrelation, rowSpatialCorrelation, columnCorrelation, columnSpatialCorrelation)
		),
	}
end

local function highFrequencyScreen(image: Codec.Image): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local periods = { 2, 3, 4, 5, 6, 8, 10, 12, 16 }
	local powers: { number } = {}
	local function valueAt(x: number, y: number): number
		local base = (y * width + x) * channels
		return luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
	end
	local function scan(length: number, sample: (number) -> number)
		for _, period in periods do
			local real, imaginary = 0, 0
			for index = 0, length - 1 do
				local phase = 2 * math.pi * index / period
				local value = sample(index)
				real += value * math.cos(phase)
				imaginary += value * math.sin(phase)
			end
			table.insert(powers, (real * real + imaginary * imaginary) / math.max(length, 1))
		end
	end
	local rows, columns = math.min(8, height), math.min(8, width)
	for sample = 0, rows - 1 do
		local y = math.floor((sample + 0.5) * height / rows)
		scan(width, function(x: number): number
			return valueAt(x, y) - (valueAt(math.max(x - 1, 0), y) + valueAt(math.min(x + 1, width - 1), y)) / 2
		end)
	end
	for sample = 0, columns - 1 do
		local x = math.floor((sample + 0.5) * width / columns)
		scan(height, function(y: number): number
			return valueAt(x, y) - (valueAt(x, math.max(y - 1, 0)) + valueAt(x, math.min(y + 1, height - 1))) / 2
		end)
	end
	local peak = 0
	for _, power in powers do
		peak = math.max(peak, power)
	end
	return {
		hfScreenPatternPeak = rounded(peak),
		hfScreenPatternMedian = rounded(median(powers)),
		hfScreenPatternPeakRatio = rounded(peak / math.max(median(powers), 0.0001)),
	}
end

local function interiorSeams(image: Codec.Image): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local function at(x: number, y: number): number
		local base = (y * width + x) * channels
		return luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
	end
	local columns: { number } = {}
	local rows: { number } = {}
	local maxColumn, maxColumnX = 0, 0
	local maxRow, maxRowY = 0, 0
	for x = 1, width - 1 do
		local delta = 0
		for y = 0, height - 1 do
			delta += math.abs(at(x, y) - at(x - 1, y))
		end
		delta /= height
		table.insert(columns, delta)
		if delta > maxColumn then
			maxColumn, maxColumnX = delta, x
		end
	end
	for y = 1, height - 1 do
		local delta = 0
		for x = 0, width - 1 do
			delta += math.abs(at(x, y) - at(x, y - 1))
		end
		delta /= width
		table.insert(rows, delta)
		if delta > maxRow then
			maxRow, maxRowY = delta, y
		end
	end
	local columnMedian, rowMedian = median(columns), median(rows)
	local function fractionalHit(values: { number }, length: number): (number, number)
		local worst, position = 0, 0
		for _, fraction in { 0.25, 1 / 3, 0.5, 2 / 3, 0.75 } do
			local target = math.floor(length * fraction + 0.5)
			for coordinate = math.max(1, target - 3), math.min(length - 1, target + 3) do
				local value = values[coordinate]
				if value > worst then
					worst, position = value, coordinate
				end
			end
		end
		return worst, position
	end
	local fractionalColumn, fractionalColumnX = fractionalHit(columns, width)
	local fractionalRow, fractionalRowY = fractionalHit(rows, height)
	return {
		maxInteriorColumnDelta = rounded(maxColumn),
		medianInteriorColumnDelta = rounded(columnMedian),
		maxInteriorColumnRatio = rounded(maxColumn / math.max(columnMedian, 0.0001)),
		maxInteriorColumnX = maxColumnX,
		maxInteriorRowDelta = rounded(maxRow),
		medianInteriorRowDelta = rounded(rowMedian),
		maxInteriorRowRatio = rounded(maxRow / math.max(rowMedian, 0.0001)),
		maxInteriorRowY = maxRowY,
		fractionalColumnRatio = rounded(fractionalColumn / math.max(columnMedian, 0.0001)),
		fractionalColumnX = fractionalColumnX,
		fractionalRowRatio = rounded(fractionalRow / math.max(rowMedian, 0.0001)),
		fractionalRowY = fractionalRowY,
	}
end

local function opacityCensus(
	image: Codec.Image,
	limits: Thresholds
): {
	[string]: number | boolean | nil,
	hasOpacityChannel: boolean,
	opaqueFraction: number,
	transparentFraction: number,
	semiTransparentFraction: number,
	keyResidueFraction: number,
	haloRatio: number,
	keyResidueTexels: number?,
	boundaryLuminance: number?,
	interiorLuminance: number?,
}
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local total = width * height
	if channels < 4 then
		return {
			hasOpacityChannel = false,
			opaqueFraction = 1,
			transparentFraction = 0,
			semiTransparentFraction = 0,
			keyResidueFraction = 0,
			haloRatio = 1,
		}
	end
	local opaque, transparent, semi = 0, 0, 0
	local residue = 0
	for index = 0, total - 1 do
		local base = index * 4
		local opacity = buffer.readu8(pixels, base + 3)
		if opacity >= limits.opaqueAlpha then
			opaque += 1
		elseif opacity <= limits.transparentAlpha then
			transparent += 1
			local r = buffer.readu8(pixels, base)
			local g = buffer.readu8(pixels, base + 1)
			local b = buffer.readu8(pixels, base + 2)
			if math.max(r, g, b) - math.min(r, g, b) >= limits.keyResidueSaturation then
				residue += 1
			end
		else
			semi += 1
		end
	end
	local boundarySum, boundaryCount = 0, 0
	local interiorSum, interiorCount = 0, 0
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local base = (y * width + x) * 4
			if buffer.readu8(pixels, base + 3) < limits.opaqueAlpha then
				continue
			end
			local edge = x == 0 or y == 0 or x == width - 1 or y == height - 1
			if not edge then
				edge = buffer.readu8(pixels, base - 4 + 3) < limits.opaqueAlpha
					or buffer.readu8(pixels, base + 4 + 3) < limits.opaqueAlpha
					or buffer.readu8(pixels, base - width * 4 + 3) < limits.opaqueAlpha
					or buffer.readu8(pixels, base + width * 4 + 3) < limits.opaqueAlpha
			end
			local value =
				luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
			if edge then
				boundarySum += value
				boundaryCount += 1
			else
				interiorSum += value
				interiorCount += 1
			end
		end
	end
	local boundary = if boundaryCount > 0 then boundarySum / boundaryCount else 0
	local interior = if interiorCount > 0 then interiorSum / interiorCount else 0
	return {
		hasOpacityChannel = opaque < total,
		opaqueFraction = rounded(opaque / total),
		transparentFraction = rounded(transparent / total),
		semiTransparentFraction = rounded(semi / total),
		keyResidueFraction = rounded(residue / total),
		keyResidueTexels = residue,
		boundaryLuminance = rounded(boundary),
		interiorLuminance = rounded(interior),
		haloRatio = rounded(if interior > 0 then boundary / interior else 1),
	}
end

local function layout(image: Codec.Image, limits: Thresholds): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels

	local function flatBands(count: number, span: number, valueAt: (number, number) -> (number, number))
		local flat: { boolean } = {}
		for line = 0, count - 1 do
			local low, high = 255, 0
			local clear = true
			for step = 0, span - 1 do
				local value, opacity = valueAt(line, step)
				if opacity > limits.transparentAlpha then
					clear = false
					low = math.min(low, value)
					high = math.max(high, value)
				end
			end
			flat[line] = clear or (high - low) <= limits.gutterLumaRange
		end
		local border, panels = 0, 0
		local line = 0
		while line < count and flat[line] do
			border += 1
			line += 1
		end
		local trailing = count - 1
		while trailing >= 0 and flat[trailing] do
			trailing -= 1
		end
		border += count - 1 - trailing
		local inRegion = false
		local run = 0
		for index = line, trailing do
			if flat[index] then
				run += 1
			else
				if inRegion and run >= limits.minGutterBand then
					panels += 1
					inRegion = false
				end
				run = 0
				inRegion = true
			end
		end
		if inRegion then
			panels += 1
		end
		return math.max(panels, 1), border
	end

	local function rowValue(y: number, x: number): (number, number)
		local base = (y * width + x) * channels
		local opacity = if channels == 4 then buffer.readu8(pixels, base + 3) else 255
		return luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2)),
			opacity
	end
	local function columnValue(x: number, y: number): (number, number)
		return rowValue(y, x)
	end

	local rowPanels, rowBorder = flatBands(height, width, rowValue)
	local columnPanels, columnBorder = flatBands(width, height, columnValue)
	return {
		rowPanels = rowPanels,
		columnPanels = columnPanels,
		panelCount = rowPanels * columnPanels,
		borderBandRows = rowBorder,
		borderBandColumns = columnBorder,
	}
end

local function register(image: Codec.Image, limits: Thresholds): { [string]: number }
	local width, height, channels = image.width, image.height, image.channels
	local pixels = image.pixels
	local histogram = table.create(256, 0)
	local counted = 0
	local left, right, top, bottom = 0, 0, 0, 0
	local leftCount, rightCount, topCount, bottomCount = 0, 0, 0, 0
	local centre, centreCount, ring, ringCount = 0, 0, 0, 0
	local insetX, insetY = width // 4, height // 4
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local base = (y * width + x) * channels
			if channels == 4 and buffer.readu8(pixels, base + 3) <= limits.transparentAlpha then
				continue
			end
			local value =
				luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
			local bucket = math.floor(value)
			histogram[bucket + 1] += 1
			counted += 1
			if x < width // 2 then
				left += value
				leftCount += 1
			else
				right += value
				rightCount += 1
			end
			if y < height // 2 then
				top += value
				topCount += 1
			else
				bottom += value
				bottomCount += 1
			end
			if x >= insetX and x < width - insetX and y >= insetY and y < height - insetY then
				centre += value
				centreCount += 1
			else
				ring += value
				ringCount += 1
			end
		end
	end
	if counted == 0 then
		return { vignetteRatio = 1, lightingGradient = 0, lumaSpread = 0, luma5 = 0, luma50 = 0, luma95 = 0 }
	end
	local function percentile(fraction: number): number
		local target = math.max(1, math.floor(counted * fraction))
		local seen = 0
		for bucket = 1, 256 do
			seen += histogram[bucket]
			if seen >= target then
				return bucket - 1
			end
		end
		return 255
	end
	local low, middle, high = percentile(0.05), percentile(0.5), percentile(0.95)
	local horizontal = if leftCount > 0 and rightCount > 0 then math.abs(left / leftCount - right / rightCount) else 0
	local vertical = if topCount > 0 and bottomCount > 0 then math.abs(top / topCount - bottom / bottomCount) else 0
	return {
		vignetteRatio = rounded(
			if ringCount > 0 and centreCount > 0 and ring > 0 then (centre / centreCount) / (ring / ringCount) else 1
		),
		lightingGradient = rounded(math.max(horizontal, vertical)),
		luma5 = low,
		luma50 = middle,
		luma95 = high,
		lumaSpread = high - low,
	}
end

local function assess(config: Config, bytes: string, declaration: Declaration, path: string): Assessment
	requireThresholds(config)
	local limits = config.thresholds
	local refusals: { Refusal } = {}
	local warnings: { string } = {}
	local decoded = config.codec.decode(bytes)
	if not decoded.ok then
		table.insert(refusals, refusal("decode", decoded.reason, 0, 0))
		return {
			artifactId = declaration.id,
			path = path,
			facts = { schema = config.schema, decoded = false },
			refusals = refusals,
			warnings = warnings,
		}
	end
	local image = decoded.image :: Codec.Image

	local tiles = tileability(image)
	local interior = interiorSeams(image)
	local opacity = opacityCensus(image, limits)
	local panels = layout(image, limits)
	local hints = register(image, limits)
	local pips = brightMaxima(image, limits)
	local colors = chroma(image, limits, declaration.hueBand)
	local blur = edgeBlur(image)
	local copies = edgeCopies(image)
	local mirror = edgeMirror(image)
	local screen = highFrequencyScreen(image)

	local facts: { [string]: string | number | boolean | nil } = {
		schema = config.schema,
		decoded = true,
		width = image.width,
		height = image.height,
		channels = image.channels,
	}
	for key, value in tiles do
		facts[key] = value
	end
	for key, value in interior do
		facts[key] = value
	end
	for key, value in opacity do
		facts[key] = value
	end
	for key, value in panels do
		facts[key] = value
	end
	for key, value in hints do
		facts[key] = value
	end
	for key, value in pips do
		facts[key] = value
	end
	for key, value in colors do
		facts[key] = value
	end
	for key, value in blur do
		facts[key] = value
	end
	for key, value in copies do
		facts[key] = value
	end
	for key, value in mirror do
		facts[key] = value
	end
	for key, value in screen do
		facts[key] = value
	end

	if declaration.tiles and tiles.wrapSeamRatio > limits.maxWrapSeamRatio then
		table.insert(
			refusals,
			refusal(
				"tileability",
				("the wrap join measures %.2fx this surface's own interior adjacent-pixel gradient (x %.2fx, y %.2fx); a tile at that ratio shows its grid"):format(
					tiles.wrapSeamRatio,
					tiles.wrapSeamRatioX,
					tiles.wrapSeamRatioY
				),
				tiles.wrapSeamRatio,
				limits.maxWrapSeamRatio
			)
		)
	end
	if
		declaration.tiles
		and (
			interior.maxInteriorColumnRatio > limits.maxInteriorSeamRatio
			or interior.maxInteriorRowRatio > limits.maxInteriorSeamRatio
		)
	then
		local axis = if interior.maxInteriorColumnRatio >= interior.maxInteriorRowRatio then "column" else "row"
		local ratio = if axis == "column" then interior.maxInteriorColumnRatio else interior.maxInteriorRowRatio
		local coordinate = if axis == "column" then interior.maxInteriorColumnX else interior.maxInteriorRowY
		table.insert(
			refusals,
			refusal(
				"interior-seam",
				("the largest interior adjacent-%s delta is %.2fx its median at %s %d; an offset composite exposes this cut through the tile centre"):format(
					axis,
					ratio,
					if axis == "column" then "x" else "y",
					coordinate
				),
				ratio,
				limits.maxInteriorSeamRatio
			)
		)
	end
	if
		declaration.tiles
		and (
			interior.fractionalColumnRatio > limits.maxFractionalSeamRatio
			or interior.fractionalRowRatio > limits.maxFractionalSeamRatio
		)
	then
		local axis = if interior.fractionalColumnRatio >= interior.fractionalRowRatio then "column" else "row"
		local ratio = if axis == "column" then interior.fractionalColumnRatio else interior.fractionalRowRatio
		local coordinate = if axis == "column" then interior.fractionalColumnX else interior.fractionalRowY
		table.insert(
			refusals,
			refusal(
				"fractional-interior-seam",
				("an interior adjacent-%s delta within 3 px of a half, third or quarter is %.2fx its median at %s %d"):format(
					axis,
					ratio,
					if axis == "column" then "x" else "y",
					coordinate
				),
				ratio,
				limits.maxFractionalSeamRatio
			)
		)
	end
	if declaration.unlit and hints.vignetteRatio > limits.maxUnlitVignetteRatio then
		table.insert(
			refusals,
			refusal(
				"unlit-vignette",
				("the centre-to-ring luminance ratio is %.2f; an unlit image must be at most %.2f"):format(
					hints.vignetteRatio,
					limits.maxUnlitVignetteRatio
				),
				hints.vignetteRatio,
				limits.maxUnlitVignetteRatio
			)
		)
	end
	if declaration.unlit and hints.lightingGradient > limits.maxUnlitLightingGradient then
		table.insert(
			refusals,
			refusal(
				"unlit-gradient",
				("the strongest half-frame luminance difference is %.2f; an unlit image permits at most %.2f"):format(
					hints.lightingGradient,
					limits.maxUnlitLightingGradient
				),
				hints.lightingGradient,
				limits.maxUnlitLightingGradient
			)
		)
	end
	if declaration.hueBand ~= nil then
		local band = declaration.hueBand
		if colors.hueBandFraction > band.maxFraction then
			table.insert(
				refusals,
				refusal(
					"hue-band",
					("%.2f%% of the pixels are chromatic with a hue in the declared %.0f-%.0f degree band; at most %.2f%% are permitted"):format(
						colors.hueBandFraction * 100,
						band.fromDegrees,
						band.toDegrees,
						band.maxFraction * 100
					),
					colors.hueBandFraction,
					band.maxFraction
				)
			)
		end
	end
	if declaration.limitBrightMaxima and pips.brightMaximaFraction > limits.maxBrightMaximaFraction then
		table.insert(
			refusals,
			refusal(
				"bright-maxima",
				("%.2f%% of texels are local luminance maxima above L%d; at most %.2f%% are permitted"):format(
					pips.brightMaximaFraction * 100,
					limits.brightMaximaLuma,
					limits.maxBrightMaximaFraction * 100
				),
				pips.brightMaximaFraction,
				limits.maxBrightMaximaFraction
			)
		)
	end
	if declaration.declaredWidth ~= nil and image.width ~= declaration.declaredWidth then
		table.insert(
			refusals,
			refusal(
				"declared-width",
				("the brief declares %d px width and the delivered PNG is %d px wide"):format(
					declaration.declaredWidth,
					image.width
				),
				image.width,
				declaration.declaredWidth
			)
		)
	end
	if declaration.declaredHeight ~= nil and image.height ~= declaration.declaredHeight then
		table.insert(
			refusals,
			refusal(
				"declared-height",
				("the brief declares %d px height and the delivered PNG is %d px high"):format(
					declaration.declaredHeight,
					image.height
				),
				image.height,
				declaration.declaredHeight
			)
		)
	end
	if declaration.tiles then
		if blur.edgeBlurRatio < limits.minEdgeBlurRatio then
			table.insert(
				refusals,
				refusal(
					"edge-blur-band",
					("the outer %d px local standard deviation is %.2fx the interior; a wrapping tile needs at least %.2fx"):format(
						blur.edgeBlurBand,
						blur.edgeBlurRatio,
						limits.minEdgeBlurRatio
					),
					blur.edgeBlurRatio,
					limits.minEdgeBlurRatio
				)
			)
		end
		if
			copies.duplicatedEdgeRows == 1
			or copies.mirroredEdgeRows == 1
			or copies.duplicatedEdgeColumns == 1
			or copies.mirroredEdgeColumns == 1
		then
			table.insert(
				refusals,
				refusal(
					"duplicate-edge",
					("one opposing outer-%d-px edge band is byte-identical or mirrored; this is padding, not a wrap"):format(
						copies.edgeMatchBand
					),
					1,
					0
				)
			)
		end
		if screen.hfScreenPatternPeakRatio > limits.maxHfScreenPatternPeakRatio then
			table.insert(
				refusals,
				refusal(
					"hf-screen-pattern",
					("the high-frequency periodic peak is %.1fx its median spectral sample; the screen-pattern ceiling is %.1fx"):format(
						screen.hfScreenPatternPeakRatio,
						limits.maxHfScreenPatternPeakRatio
					),
					screen.hfScreenPatternPeakRatio,
					limits.maxHfScreenPatternPeakRatio
				)
			)
		end
		if mirror.edgeMirrorCorrelation > limits.maxEdgeMirrorCorrelation then
			table.insert(
				refusals,
				refusal(
					"edge-mirror-symmetry",
					("the outer %d px correlate %.3f with their opposing mirror; a wrapping tile permits at most %.2f"):format(
						mirror.edgeMirrorBand,
						mirror.edgeMirrorCorrelation,
						limits.maxEdgeMirrorCorrelation
					),
					mirror.edgeMirrorCorrelation,
					limits.maxEdgeMirrorCorrelation
				)
			)
		end
		if not declaration.dark and hints.luma50 < limits.minMedianLuma then
			table.insert(
				refusals,
				refusal(
					"median-luma-floor",
					("the median luminance is L%d; a tile not declared dark needs at least L%d"):format(
						hints.luma50,
						limits.minMedianLuma
					),
					hints.luma50,
					limits.minMedianLuma
				)
			)
		end
	end
	if declaration.registerTarget ~= nil then
		local ceiling = declaration.registerTarget.saturationCeiling
		if colors.meanSaturation > ceiling then
			table.insert(
				refusals,
				refusal(
					"register-saturation",
					("the mean saturation is %.3f and the declared register ceiling is %.3f"):format(
						colors.meanSaturation,
						ceiling
					),
					colors.meanSaturation,
					ceiling
				)
			)
		end
		local bands: { { key: string, min: number, max: number } } = {
			{
				key = "p5",
				min = declaration.registerTarget.value.p5.min,
				max = declaration.registerTarget.value.p5.max,
			},
			{
				key = "p50",
				min = declaration.registerTarget.value.p50.min,
				max = declaration.registerTarget.value.p50.max,
			},
			{
				key = "p95",
				min = declaration.registerTarget.value.p95.min,
				max = declaration.registerTarget.value.p95.max,
			},
		}
		for _, value in bands do
			local factKey = if value.key == "p5" then "luma5" elseif value.key == "p50" then "luma50" else "luma95"
			local measured = hints[factKey] :: number
			if measured < value.min or measured > value.max then
				table.insert(
					refusals,
					refusal(
						"register-value-" .. value.key,
						("the declared %s register band is L%d-L%d and the delivered value is L%d"):format(
							value.key,
							value.min,
							value.max,
							measured
						),
						measured,
						if measured < value.min then value.min else value.max
					)
				)
			end
		end
	end

	if declaration.transparentBackground then
		if image.channels < 4 or not opacity.hasOpacityChannel then
			table.insert(
				refusals,
				refusal(
					"opacity-channel",
					"the brief declares a transparent background and the delivered PNG carries no transparency at all",
					0,
					1
				)
			)
		else
			if opacity.semiTransparentFraction < limits.minSemiTransparentFraction then
				table.insert(
					refusals,
					refusal(
						"opacity-census",
						("%.2f%% of texels carry a partial opacity; this is a hard one-bit key and every silhouette edge will staircase"):format(
							opacity.semiTransparentFraction * 100
						),
						opacity.semiTransparentFraction,
						limits.minSemiTransparentFraction
					)
				)
			end
			if opacity.keyResidueFraction > limits.maxKeyResidueFraction then
				table.insert(
					refusals,
					refusal(
						"key-residue",
						("%d transparent texels hold saturated RGB; every mip level averages that colour back into the visible edge"):format(
							opacity.keyResidueTexels :: number
						),
						opacity.keyResidueFraction,
						limits.maxKeyResidueFraction
					)
				)
			end
			if opacity.haloRatio > limits.maxHaloRatio then
				table.insert(
					refusals,
					refusal(
						"halo",
						("boundary texels are %.2fx the interior luminance; the rim is brighter than the interior"):format(
							opacity.haloRatio
						),
						opacity.haloRatio,
						limits.maxHaloRatio
					)
				)
			end
		end
	end

	if declaration.singleSubject and panels.panelCount > limits.maxPanels then
		table.insert(
			refusals,
			refusal(
				"layout",
				("the delivered bytes carry %d disconnected subject regions (%d rows by %d columns) separated by gutter bands; the brief declares one artifact"):format(
					panels.panelCount,
					panels.rowPanels,
					panels.columnPanels
				),
				panels.panelCount,
				limits.maxPanels
			)
		)
	end

	if hints.vignetteRatio > limits.warnVignetteRatio then
		table.insert(
			warnings,
			("register: the centre is %.2fx the outer ring, which reads as a vignette rather than an even surface"):format(
				hints.vignetteRatio
			)
		)
	end
	if hints.lightingGradient > limits.warnLightingGradient then
		table.insert(
			warnings,
			("register: one half of the frame is %.1f luminance brighter than the other, which reads as a directional gradient"):format(
				hints.lightingGradient
			)
		)
	end
	if hints.lumaSpread < limits.warnLumaSpread then
		table.insert(
			warnings,
			("register: the 5th to 95th percentile luminance spans only %d levels, so the surface may collapse into one flat band at distance"):format(
				hints.lumaSpread
			)
		)
	end

	return { artifactId = declaration.id, path = path, facts = facts, refusals = refusals, warnings = warnings }
end

export type Deps = {
	exists: (string) -> boolean,
	read: (string) -> string,
}

export type Pair = { artifactIds: { string }, meanLuminanceRatio: number, registrationCorrelation: number }

export type Gate = {
	schema: string,
	status: string,
	thresholds: Thresholds,
	artifacts: { Assessment },
	refusals: { string },
	pairs: { [string]: Pair },
}

local function gate(config: Config, deps: Deps, declarations: { Declaration }, located: { [string]: string }): Gate
	requireThresholds(config)
	local limits = config.thresholds
	local assessments: { Assessment } = {}
	local reasons: { string } = {}
	local delivered = 0
	for _ in located do
		delivered += 1
	end
	if delivered ~= #declarations then
		table.insert(
			reasons,
			("the request declares %d artifact%s and the run delivered %d; a brief that declares N artifacts emits N files, never one sheet"):format(
				#declarations,
				if #declarations == 1 then "" else "s",
				delivered
			)
		)
	end
	local paired: { [string]: { { id: string, path: string } } } = {}
	for _, declaration in declarations do
		local path = located[declaration.id]
		if path == nil then
			table.insert(reasons, ("declared artifact %s was not delivered by the run"):format(declaration.id))
			continue
		end
		if not deps.exists(path) then
			table.insert(reasons, ("declared artifact %s names %s, which does not exist"):format(declaration.id, path))
			continue
		end
		local assessment = assess(config, deps.read(path), declaration, path)
		table.insert(assessments, assessment)
		for _, entry in assessment.refusals do
			table.insert(reasons, ("%s: %s -- %s"):format(declaration.id, entry.fact, entry.detail))
		end
		if declaration.pairedGroup ~= nil then
			if paired[declaration.pairedGroup] == nil then
				paired[declaration.pairedGroup] = {}
			end
			table.insert(paired[declaration.pairedGroup], { id = declaration.id, path = path })
		end
	end
	local pairs: { [string]: Pair } = {}
	for group, entries in paired do
		if #entries ~= 2 then
			table.insert(
				reasons,
				("paired group %s declares %d artifacts; a paired image gate requires exactly two"):format(
					group,
					#entries
				)
			)
			continue
		end
		local first, second =
			config.codec.decode(deps.read(entries[1].path)), config.codec.decode(deps.read(entries[2].path))
		if not first.ok or not second.ok then
			table.insert(reasons, ("paired group %s could not decode both images"):format(group))
			continue
		end
		local a, b = first.image :: Codec.Image, second.image :: Codec.Image
		if a.width ~= b.width or a.height ~= b.height then
			table.insert(reasons, ("paired group %s has mismatched dimensions"):format(group))
			continue
		end
		local sumA, sumB, sumAA, sumBB, sumAB, count = 0, 0, 0, 0, 0, a.width * a.height
		for index = 0, count - 1 do
			local baseA, baseB = index * a.channels, index * b.channels
			local valueA = luma(
				buffer.readu8(a.pixels, baseA),
				buffer.readu8(a.pixels, baseA + 1),
				buffer.readu8(a.pixels, baseA + 2)
			)
			local valueB = luma(
				buffer.readu8(b.pixels, baseB),
				buffer.readu8(b.pixels, baseB + 1),
				buffer.readu8(b.pixels, baseB + 2)
			)
			sumA += valueA
			sumB += valueB
			sumAA += valueA * valueA
			sumBB += valueB * valueB
			sumAB += valueA * valueB
		end
		local meanA, meanB = sumA / count, sumB / count
		local correlation = (sumAB - count * meanA * meanB)
			/ math.max(math.sqrt((sumAA - count * meanA * meanA) * (sumBB - count * meanB * meanB)), 0.0001)
		local ratio = meanA / math.max(meanB, 0.0001)
		pairs[group] = {
			artifactIds = { entries[1].id, entries[2].id },
			meanLuminanceRatio = rounded(ratio),
			registrationCorrelation = rounded(correlation),
		}
		if ratio < limits.minPairedLuminanceRatio or ratio > limits.maxPairedLuminanceRatio then
			table.insert(
				reasons,
				("paired group %s: mean-luminance ratio %.3f is outside %.2f-%.2f"):format(
					group,
					ratio,
					limits.minPairedLuminanceRatio,
					limits.maxPairedLuminanceRatio
				)
			)
		end
		if correlation < limits.minPairedRegistrationCorrelation then
			table.insert(
				reasons,
				("paired group %s: registration correlation %.3f is below %.2f"):format(
					group,
					correlation,
					limits.minPairedRegistrationCorrelation
				)
			)
		end
	end
	return {
		schema = config.schema,
		status = if #reasons > 0 then "refused" else "produced",
		thresholds = limits,
		artifacts = assessments,
		refusals = reasons,
		pairs = pairs,
	}
end

return {
	highFrequencyScreen = highFrequencyScreen,
	assess = assess,
	gate = gate,
}
