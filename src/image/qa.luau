--!strict

local Codec = require "./codec"
local Register = require "./register"

local Metrics = require "./qa-metrics"

export type Thresholds = Metrics.Thresholds

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

export type HueBand = Metrics.HueBand

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

	local tiles = Metrics.tileability(image)
	local interior = Metrics.interiorSeams(image)
	local opacity = Metrics.opacityCensus(image, limits)
	local panels = Metrics.layout(image, limits)
	local hints = Metrics.register(image, limits)
	local pips = Metrics.brightMaxima(image, limits)
	local colors = Metrics.chroma(image, limits, declaration.hueBand)
	local blur = Metrics.edgeBlur(image)
	local copies = Metrics.edgeCopies(image)
	local mirror = Metrics.edgeMirror(image)
	local screen = Metrics.highFrequencyScreen(image)

	local facts: { [string]: string | number | boolean | nil } = {
		schema = config.schema,
		decoded = true,
		width = image.width,
		height = image.height,
		channels = image.channels,
	}
	for _, measurements in { tiles, interior, panels, hints, pips, colors, blur, copies, mirror, screen } do
		for key, value in measurements do
			facts[key] = value
		end
	end

	for key, value in opacity do
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
	highFrequencyScreen = Metrics.highFrequencyScreen,
	assess = assess,
	gate = gate,
}
