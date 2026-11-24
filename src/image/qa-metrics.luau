--!strict

local Codec = require "./codec"

local luma = Codec.luma
local rounded = Codec.rounded
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

export type HueBand = { fromDegrees: number, toDegrees: number, maxFraction: number }

local function luminanceReader(image: Codec.Image): (number, number) -> number
	local width, channels, pixels = image.width, image.channels, image.pixels
	return function(x: number, y: number): number
		local base = (y * width + x) * channels
		return luma(buffer.readu8(pixels, base), buffer.readu8(pixels, base + 1), buffer.readu8(pixels, base + 2))
	end
end

local function tileability(image: Codec.Image): { [string]: number }
	local width, height = image.width, image.height
	local lumaAt = luminanceReader(image)
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
	local width, height = image.width, image.height
	local band = math.min(EDGE_BAND, math.max(1, math.min(width, height) // 4))
	local outerSum, outerCount, interiorSum, interiorCount = 0, 0, 0, 0
	local valueAt = luminanceReader(image)
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
	local width, height = image.width, image.height
	local band = math.min(EDGE_MIRROR_BAND, math.max(1, math.min(width, height) // 2))
	local rowsA: { number }, rowsDirect: { number }, rowsSpatial: { number } = {}, {}, {}
	local columnsA: { number }, columnsDirect: { number }, columnsSpatial: { number } = {}, {}, {}
	local valueAt = luminanceReader(image)
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
	local width, height = image.width, image.height
	local periods = { 2, 3, 4, 5, 6, 8, 10, 12, 16 }
	local powers: { number } = {}
	local valueAt = luminanceReader(image)
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
	local width, height = image.width, image.height
	local at = luminanceReader(image)
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

return {
	tileability = tileability,
	interiorSeams = interiorSeams,
	opacityCensus = opacityCensus,
	layout = layout,
	register = register,
	brightMaxima = brightMaxima,
	chroma = chroma,
	edgeBlur = edgeBlur,
	edgeCopies = edgeCopies,
	edgeMirror = edgeMirror,
	highFrequencyScreen = highFrequencyScreen,
}
