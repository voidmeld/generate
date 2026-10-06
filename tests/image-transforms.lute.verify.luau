--!strict

local Fixture = require "./fixtures/image-codec"
local Thresholds = require "./fixtures/image-thresholds"
local Image = require "../src/image"
local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local Codec = Fixture.codec
local Matte = Image.matte
local MATTE_PARAMETERS: Image.MatteParameters = { interiorDistance = 3, boundaryDistance = 2, featherRadius = 1.5 }
local Register = require "../src/image/register"
local Deliver = Image.deliver
local Qa = Image.qa

local TRANSFORM: Image.RegisterConfig = { codec = Codec, digest = Fixture.digest }

local QA: Image.QaConfig = { schema = "spec.image-qa.v1", codec = Codec, thresholds = Thresholds }

local LIMITS = Thresholds
local SIZE = 16

local function build(pixel: (x: number, y: number) -> Image.Rgba, size: number?): string
	return Codec.encodeRgba(size or SIZE, size or SIZE, pixel)
end

local function decoded(bytes: string): Image.Image
	local value = Codec.decode(bytes)
	expect(value.ok):toBe(true)
	assert(value.ok == true)
	return value.image
end

local function sample(image: Image.Image, x: number, y: number, channel: number): number
	return buffer.readu8(image.pixels, (y * image.width + x) * 4 + channel)
end

type DeclarationOverrides = {
	id: string?,
	role: string?,
	tiles: boolean?,
	transparentBackground: boolean?,
	singleSubject: boolean?,
	unlit: boolean?,
	pairedGroup: string?,
	hueBand: Image.QaHueBand?,
	limitBrightMaxima: boolean?,
	declaredWidth: number?,
	declaredHeight: number?,
	dark: boolean?,
	registerTarget: {
		hue: number,
		saturationCeiling: number,
		value: {
			p5: { min: number, max: number, target: number },
			p50: { min: number, max: number, target: number },
			p95: { min: number, max: number, target: number },
		},
	}?,
}

local function declaration(overrides: DeclarationOverrides): Image.QaDeclaration
	return {
		id = overrides.id or "spec.candidate.original.v1",
		role = overrides.role or "spec-surface",
		tiles = overrides.tiles or false,
		transparentBackground = overrides.transparentBackground or false,
		singleSubject = overrides.singleSubject or false,
		unlit = overrides.unlit,
		pairedGroup = overrides.pairedGroup,
		hueBand = overrides.hueBand,
		limitBrightMaxima = overrides.limitBrightMaxima,
		declaredWidth = overrides.declaredWidth,
		declaredHeight = overrides.declaredHeight,
		dark = overrides.dark,
		registerTarget = overrides.registerTarget,
	}
end

local function facts(bytes: string, overrides: DeclarationOverrides): Image.QaAssessment
	return Qa.assess(QA, bytes, declaration(overrides), "spec://candidate.png")
end

local function refusedOn(assessment: Image.QaAssessment, fact: string): boolean
	for _, entry in assessment.refusals do
		if entry.fact == fact then
			return true
		end
	end
	return false
end

local function patterned(x: number, y: number): number
	return 65 + (x * 17 + y * 29 + x * y * 3) % 70
end

local function insideDisc(x: number, y: number): boolean
	local dx, dy = x - 7.5, y - 7.5
	return dx * dx + dy * dy <= 30
end

local function triangle(value: number): number
	return if value < SIZE // 2 then value else SIZE - value
end

local function seamed(): string
	return build(function(x: number): Image.Rgba
		local value = math.floor(x * 255 / (SIZE - 1))
		return { r = value, g = value, b = value, a = 255 }
	end)
end

local function wrapping(): string
	return build(function(x: number, y: number): Image.Rgba
		local value = 20 + triangle(x) * 12 + triangle(y) * 12
		return { r = value, g = value, b = value, a = 255 }
	end)
end

local function interiorSeamed(): string
	return build(function(x: number, y: number): Image.Rgba
		local value = 90 + ((x * 11 + y * 7) % 9)
		if x >= SIZE // 2 then
			value += 35
		end
		return { r = value, g = value, b = value, a = 255 }
	end)
end

local function oneBitOpacity(): string
	return build(function(x: number, y: number): Image.Rgba
		return { r = 100, g = 100, b = 100, a = if insideDisc(x, y) then 255 else 0 }
	end)
end

local function authoredOpacity(): string
	return build(function(x: number, y: number): Image.Rgba
		local dx, dy = x - 7.5, y - 7.5
		local distance = math.sqrt(dx * dx + dy * dy)
		return { r = 100, g = 100, b = 100, a = math.clamp(math.floor((5.5 - distance) * 170), 0, 255) }
	end)
end

local function keyResidue(): string
	return build(function(x: number, y: number): Image.Rgba
		if insideDisc(x, y) then
			return { r = 100, g = 100, b = 100, a = 255 }
		end
		local dx, dy = x - 7.5, y - 7.5
		local distance = math.sqrt(dx * dx + dy * dy)
		local opacity = math.clamp(math.floor((5.7 - distance) * 200), 0, 255)
		return { r = 240, g = 12, b = 12, a = if opacity > 5 then opacity else 0 }
	end)
end

local function twoPanelSheet(): string
	return build(function(x: number, y: number): Image.Rgba
		if x >= 6 and x <= 9 then
			return { r = 126, g = 126, b = 126, a = 255 }
		end
		local value = if (x + y) % 2 == 0 then 40 else 200
		return { r = value, g = value, b = value, a = 255 }
	end)
end

local function warm(): string
	return build(function(): Image.Rgba
		return { r = 130, g = 85, b = 20, a = 255 }
	end, 64)
end

local function specularPips(): string
	return build(function(x: number, y: number): Image.Rgba
		local value = if x % 4 == 2 and y % 4 == 2 then 210 else patterned(x, y)
		return { r = value, g = value, b = value, a = 255 }
	end, 64)
end

local function duplicateEdges(): string
	return build(function(x: number, y: number): Image.Rgba
		local value = patterned(x, if y >= 56 then 63 - y else y)
		return { r = value, g = value, b = value, a = 255 }
	end, 64)
end

local function blurredEdges(): string
	return build(function(x: number, y: number): Image.Rgba
		if x < 16 or y < 16 or x >= 48 or y >= 48 then
			return { r = 90, g = 90, b = 90, a = 255 }
		end
		local value = if (x + y) % 2 == 0 then 50 else 150
		return { r = value, g = value, b = value, a = 255 }
	end, 64)
end

local function screenPattern(): string
	return build(function(x: number, y: number): Image.Rgba
		local value = if (x + y) % 2 == 0 then 40 else 180
		return { r = value, g = value, b = value, a = 255 }
	end, 64)
end

local function mirroredEdges(): string
	return build(function(x: number, y: number): Image.Rgba
		local value = patterned(if x >= 48 then 63 - x else x, if y >= 48 then 63 - y else y)
		return { r = value, g = value, b = value, a = 255 }
	end, 64)
end

describe("Image.qa produced-byte facts", function()
	it("measures the wrap join against the surface's own interior gradient", function()
		local seam = facts(seamed(), { tiles = true })
		expect(seam.facts.decoded):toBe(true)
		expect(seam.facts.wrapSeamRatioX > LIMITS.maxWrapSeamRatio):toBe(true)
		expect(refusedOn(seam, "tileability")):toBe(true)

		local tiles = facts(wrapping(), { tiles = true })
		expect(tiles.facts.wrapSeamRatio <= LIMITS.maxWrapSeamRatio):toBe(true)
		expect(refusedOn(tiles, "tileability")):toBe(false)
	end)

	it("holds a seam only for a surface that declared it tiles", function()
		expect(refusedOn(facts(seamed(), { tiles = false }), "tileability")):toBe(false)
	end)

	it("refuses a discontinuity exposed inside a half-offset composite", function()
		local assessment = facts(interiorSeamed(), { tiles = true })
		expect(assessment.facts.maxInteriorColumnX):toBe(SIZE // 2)
		expect(assessment.facts.maxInteriorColumnRatio > LIMITS.maxInteriorSeamRatio):toBe(true)
		expect(assessment.facts.fractionalColumnRatio > LIMITS.maxFractionalSeamRatio):toBe(true)
		expect(refusedOn(assessment, "interior-seam")):toBe(true)
		expect(refusedOn(assessment, "fractional-interior-seam")):toBe(true)
	end)

	it("refuses a strictly one-bit opacity and admits an authored one", function()
		local hard = facts(oneBitOpacity(), { transparentBackground = true })
		expect(hard.facts.semiTransparentFraction):toBe(0)
		expect(refusedOn(hard, "opacity-census")):toBe(true)

		local authored = facts(authoredOpacity(), { transparentBackground = true })
		expect(authored.facts.semiTransparentFraction > 0):toBe(true)
		expect(refusedOn(authored, "opacity-census")):toBe(false)
		expect(#authored.refusals):toBe(0)
	end)

	it("refuses saturated colour-key residue stored under the transparent texels", function()
		local residue = facts(keyResidue(), { transparentBackground = true })
		expect(residue.facts.keyResidueTexels > 0):toBe(true)
		expect(residue.facts.keyResidueFraction > LIMITS.maxKeyResidueFraction):toBe(true)
		expect(refusedOn(residue, "key-residue")):toBe(true)
	end)

	it("refuses a brief that declares transparency whose delivered PNG carries none", function()
		local opaque = facts(wrapping(), { transparentBackground = true })
		expect(opaque.facts.hasOpacityChannel):toBe(false)
		expect(refusedOn(opaque, "opacity-channel")):toBe(true)
	end)

	it("refuses a bright rim keyed off a pale backdrop into the boundary texels", function()
		local haloed = build(function(x: number, y: number): Image.Rgba
			if not insideDisc(x, y) then
				return { r = 250, g = 250, b = 250, a = 0 }
			end
			local dx, dy = x - 7.5, y - 7.5
			local distance = math.sqrt(dx * dx + dy * dy)
			local value = if distance > 4.2 then 230 else 60
			return { r = value, g = value, b = value, a = if distance > 4.8 then 180 else 255 }
		end)
		local assessment = facts(haloed, { transparentBackground = true })
		expect(assessment.facts.haloRatio > LIMITS.maxHaloRatio):toBe(true)
		expect(refusedOn(assessment, "halo")):toBe(true)
	end)

	it("counts panels and refuses more than one where a single subject was declared", function()
		local sheet = twoPanelSheet()
		local refused = facts(sheet, { singleSubject = true })
		expect(refused.facts.columnPanels):toBe(2)
		expect(refused.facts.panelCount):toBe(2)
		expect(refusedOn(refused, "layout")):toBe(true)
		expect(refusedOn(facts(sheet, { singleSubject = false }), "layout")):toBe(false)
	end)

	it("carries the photographic-register heuristic as a warning and never as a refusal", function()
		local vignetted = build(function(x: number, y: number): Image.Rgba
			local dx, dy = (x - 7.5) / 7.5, (y - 7.5) / 7.5
			local value = math.floor(math.clamp(230 - 170 * (dx * dx + dy * dy), 0, 255))
			return { r = value, g = value, b = value, a = 255 }
		end)
		local assessment = facts(vignetted, {})
		expect(assessment.facts.vignetteRatio > LIMITS.warnVignetteRatio):toBe(true)
		expect(#assessment.warnings > 0):toBe(true)
		expect(#assessment.refusals):toBe(0)
	end)

	it("refuses pixels inside a declared hue band and bright local maxima", function()
		local band: Image.QaHueBand = { fromDegrees = 20, toDegrees = 60, maxFraction = 0.5 }
		local inside = facts(warm(), { hueBand = band })
		expect((inside.facts.hueBandFraction :: number) > 0.99):toBe(true)
		expect(inside.facts.meanHue >= 20):toBe(true)
		expect(refusedOn(inside, "hue-band")):toBe(true)

		local outside = facts(warm(), { hueBand = { fromDegrees = 200, toDegrees = 260, maxFraction = 0.5 } })
		expect(outside.facts.hueBandFraction):toBe(0)
		expect(refusedOn(outside, "hue-band")):toBe(false)

		local wrapped = facts(warm(), { hueBand = { fromDegrees = 350, toDegrees = 70, maxFraction = 0.5 } })
		expect(refusedOn(wrapped, "hue-band")):toBe(true)

		local undeclared = facts(warm(), {})
		expect(undeclared.facts.hueBandFraction):toBe(nil)
		expect(refusedOn(undeclared, "hue-band")):toBe(false)

		local pips = facts(specularPips(), { limitBrightMaxima = true })
		expect(pips.facts.brightMaximaFraction > LIMITS.maxBrightMaximaFraction):toBe(true)
		expect(refusedOn(pips, "bright-maxima")):toBe(true)
		expect(refusedOn(facts(specularPips(), {}), "bright-maxima")):toBe(false)
	end)

	it("names a threshold the consumer did not declare", function()
		local incomplete = table.clone((LIMITS :: unknown) :: { [string]: unknown })
		incomplete.maxHaloRatio = nil
		local config = { schema = QA.schema, codec = Codec, thresholds = incomplete } :: unknown
		expect(function()
			Qa.assess(config :: Image.QaConfig, wrapping(), declaration {}, "spec://candidate.png")
		end):toThrow "threshold maxHaloRatio"
		expect(function()
			Qa.gate(config :: Image.QaConfig, {
				exists = function(): boolean
					return true
				end,
				read = function(): string
					return ""
				end,
			}, {}, {})
		end):toThrow "threshold maxHaloRatio"
		local bare = { schema = QA.schema, codec = Codec } :: unknown
		expect(function()
			Qa.assess(bare :: Image.QaConfig, wrapping(), declaration {}, "spec://candidate.png")
		end):toThrow "thresholds table"
	end)

	it("refuses declared dimensions that do not match the delivered PNG", function()
		local assessment = facts(wrapping(), { declaredWidth = SIZE + 1, declaredHeight = SIZE - 1 })
		expect(refusedOn(assessment, "declared-width")):toBe(true)
		expect(refusedOn(assessment, "declared-height")):toBe(true)
	end)

	it("refuses a blurred, duplicated, mirrored, or screened tile edge", function()
		local blurred = facts(blurredEdges(), { tiles = true })
		expect(blurred.facts.edgeBlurRatio < LIMITS.minEdgeBlurRatio):toBe(true)
		expect(refusedOn(blurred, "edge-blur-band")):toBe(true)

		local duplicate = facts(duplicateEdges(), { tiles = true })
		expect(duplicate.facts.duplicatedEdgeRows):toBe(1)
		expect(refusedOn(duplicate, "duplicate-edge")):toBe(true)

		local mirror = facts(mirroredEdges(), { tiles = true })
		expect(mirror.facts.edgeMirrorCorrelation > LIMITS.maxEdgeMirrorCorrelation):toBe(true)
		expect(refusedOn(mirror, "edge-mirror-symmetry")):toBe(true)

		local screen = facts(screenPattern(), { tiles = true })
		expect(screen.facts.hfScreenPatternPeakRatio > LIMITS.maxHfScreenPatternPeakRatio):toBe(true)
		expect(refusedOn(screen, "hf-screen-pattern")):toBe(true)
	end)

	it("refuses a register target whose declared value bands do not contain delivered facts", function()
		local assessment = facts(warm(), {
			registerTarget = {
				hue = 210,
				saturationCeiling = 0.15,
				value = {
					p5 = { min = 10, max = 20, target = 15 },
					p50 = { min = 10, max = 20, target = 15 },
					p95 = { min = 10, max = 20, target = 15 },
				},
			},
		})
		expect(assessment.facts.luma50 > 20):toBe(true)
		expect(refusedOn(assessment, "register-value-p5")):toBe(true)
		expect(refusedOn(assessment, "register-value-p50")):toBe(true)
		expect(refusedOn(assessment, "register-value-p95")):toBe(true)
	end)

	it("refuses bytes it cannot decode rather than reporting facts about them", function()
		local assessment = facts("this is not a PNG at all", {})
		expect(assessment.facts.decoded):toBe(false)
		expect(refusedOn(assessment, "decode")):toBe(true)
	end)

	it("judges against the consumer's thresholds and never against a built-in pass line", function()
		local relaxed = table.clone(LIMITS)
		relaxed.maxWrapSeamRatio = 1000
		local lenient: Image.QaConfig = { schema = QA.schema, codec = Codec, thresholds = relaxed }
		local strict = Qa.assess(QA, seamed(), declaration { tiles = true }, "spec://candidate.png")
		local loose = Qa.assess(lenient, seamed(), declaration { tiles = true }, "spec://candidate.png")
		expect(refusedOn(strict, "tileability")):toBe(true)
		expect(refusedOn(loose, "tileability")):toBe(false)
		expect(loose.facts.schema):toBe(QA.schema)
	end)
end)

describe("Image.qa gating one run against its declared artifact list", function()
	local files: { [string]: string } = { ["a.png"] = authoredOpacity(), ["b.png"] = oneBitOpacity() }
	local deps: Image.QaDeps = {
		exists = function(path: string): boolean
			return files[path] ~= nil
		end,
		read = function(path: string): string
			return files[path] or error("spec harness read " .. path)
		end,
	}

	it("passes a run whose every declared artifact was delivered and cleared its facts", function()
		local gate = Qa.gate(QA, deps, { declaration { id = "one", transparentBackground = true } }, { one = "a.png" })
		expect(gate.status):toBe "produced"
		assert(gate.status == "produced")
		expect(#gate.artifacts):toBe(1)
		expect(#gate.refusals):toBe(0)
		expect(gate.thresholds.maxHaloRatio):toBe(LIMITS.maxHaloRatio)
	end)

	it("refuses a run that delivered a different number of images than the request declared", function()
		local gate = Qa.gate(QA, deps, {
			declaration { id = "one", transparentBackground = true },
			declaration { id = "two", transparentBackground = true },
		}, { one = "a.png" })
		expect(gate.status):toBe "refused"
		assert(gate.status == "refused")
		expect(gate.refusals[1]):toContain "declares 2 artifacts and the run delivered 1"
	end)

	it("names the failing fact on the artifact that failed it", function()
		local gate = Qa.gate(QA, deps, { declaration { id = "two", transparentBackground = true } }, { two = "b.png" })
		expect(gate.status):toBe "refused"
		assert(gate.status == "refused")
		expect(gate.refusals[1]):toContain "two: opacity-census"
	end)

	it("refuses a declared artifact the run never located", function()
		local gate = Qa.gate(QA, deps, { declaration { id = "ghost" } }, { ghost = "absent.png" })
		expect(gate.status):toBe "refused"
		assert(gate.status == "refused")
		expect(gate.refusals[1]):toContain "does not exist"
	end)
end)

describe("Image.matte", function()
	local MATTE_SIZE = 32

	local function disc(x: number, y: number): boolean
		local dx, dy = x - 15.5, y - 15.5
		return dx * dx + dy * dy <= 100
	end

	local function fixture(pixel: (number, number) -> Image.Rgba): string
		return Codec.encodeRgba(MATTE_SIZE, MATTE_SIZE, pixel)
	end

	local function assessed(bytes: string): Image.QaAssessment
		return Qa.assess(QA, bytes, {
			id = "matte.fixture",
			role = "cutout-card",
			tiles = false,
			transparentBackground = true,
			singleSubject = false,
		}, "spec://matte.png")
	end

	it("removes key residue, repairs a halo, and leaves the opaque interior unchanged", function()
		local bytes = fixture(function(x: number, y: number): Image.Rgba
			if not disc(x, y) then
				return { r = 240, g = 12, b = 12, a = 0 }
			end
			local dx, dy = x - 15.5, y - 15.5
			local value = if math.sqrt(dx * dx + dy * dy) > 9 then 230 else 60
			return { r = value, g = value, b = value, a = 255 }
		end)
		local before = assessed(bytes)
		expect(before.facts.keyResidueFraction > LIMITS.maxKeyResidueFraction):toBe(true)
		expect(before.facts.haloRatio > LIMITS.maxHaloRatio):toBe(true)
		local result = Matte.run(Codec, bytes, MATTE_PARAMETERS)
		expect(result.ok):toBe(true)
		assert(result.ok == true)
		local after = assessed(result.bytes)
		expect(after.facts.keyResidueFraction):toBe(0)
		expect(after.facts.haloRatio < LIMITS.maxHaloRatio):toBe(true)
		local output = decoded(result.bytes)
		expect(sample(output, 15, 15, 0)):toBe(60)
		expect(sample(output, 0, 0, 0)):toBe(230)
	end)

	it("turns a one-bit cutout into a feathered opacity field", function()
		local result = Matte.run(
			Codec,
			fixture(function(x: number, y: number): Image.Rgba
				return { r = 80, g = 110, b = 70, a = if disc(x, y) then 255 else 0 }
			end),
			MATTE_PARAMETERS
		)
		expect(result.ok):toBe(true)
		assert(result.ok == true)
		expect(assessed(result.bytes).facts.semiTransparentFraction >= LIMITS.minSemiTransparentFraction):toBe(true)
	end)

	it("is byte-idempotent on a clean card and reports the parameters it applied", function()
		local clean = fixture(function(x: number, y: number): Image.Rgba
			local distance = math.sqrt((x - 15.5) ^ 2 + (y - 15.5) ^ 2)
			return { r = 75, g = 95, b = 65, a = math.clamp(math.floor((10.5 - distance) * 170), 0, 255) }
		end)
		local once = Matte.run(Codec, clean, MATTE_PARAMETERS)
		expect(once.ok):toBe(true)
		assert(once.ok == true)
		local twice = Matte.run(Codec, once.bytes, MATTE_PARAMETERS)
		expect(twice.ok):toBe(true)
		assert(twice.ok == true)
		expect(twice.bytes):toBe(once.bytes)
		expect(once.parameters.featherRadius):toBe(MATTE_PARAMETERS.featherRadius)
	end)

	it("refuses a source that carries no opacity channel", function()
		expect(Matte.run(Codec, "not a png", MATTE_PARAMETERS).ok):toBe(false)
	end)
end)

describe("Image.register", function()
	local TARGET: Image.RegisterTarget =
		{ hue = 210, saturationCeiling = 0.15, values = { p5 = 25, p50 = 75, p95 = 130 } }

	local function warmFixture(): string
		return Codec.encodeRgba(96, 96, function(x: number, y: number): Image.Rgba
			local value = 45 + ((x * 7 + y * 11) % 125)
			if x >= 32 and x < 64 and y >= 32 and y < 64 then
				value = 170
			end
			return { r = math.min(255, value + 48), g = math.min(255, value + 8), b = math.max(0, value - 35), a = 255 }
		end)
	end

	local function pixel(image: Image.Image, x: number, y: number): number
		return buffer.readu8(image.pixels, (y * image.width + x) * 4)
	end

	it("pulls a warm surface into the cold target and remaps its declared value points", function()
		local result = Register.run(TRANSFORM, warmFixture(), TARGET)
		expect(result.ok):toBe(true)
		assert(result.ok == true)
		local complete = result
		expect(complete.preFacts.meanHue > 20 and complete.preFacts.meanHue < 60):toBe(true)
		expect(complete.postFacts.meanHue > 195 and complete.postFacts.meanHue < 225):toBe(true)
		expect(complete.postFacts.meanSaturation <= 0.16):toBe(true)
		expect(complete.postFacts.p5 >= 18 and complete.postFacts.p5 <= 35):toBe(true)
		expect(complete.postFacts.p50 >= 62 and complete.postFacts.p50 <= 88):toBe(true)
		expect(complete.postFacts.p95 >= 115 and complete.postFacts.p95 <= 145):toBe(true)
		expect(complete.sha256.pre == complete.sha256.post):toBe(false)
	end)

	it("relieves a repeated highlight plateau from adjacent local gradients", function()
		local source = decoded(warmFixture())
		local output = Register.apply(source, TARGET)
		expect(pixel(output, 32, 40) == pixel(output, 33, 40)):toBe(false)
	end)

	it("is byte-deterministic and refuses an invalid register target", function()
		local once = Register.run(TRANSFORM, warmFixture(), TARGET)
		local twice = Register.run(TRANSFORM, warmFixture(), TARGET)
		expect(once.ok):toBe(true)
		assert(once.ok == true)
		expect(twice.ok):toBe(true)
		assert(twice.ok == true)
		assert(twice.ok)
		expect(once.bytes):toBe(twice.bytes)
		local invalid =
			Register.run(TRANSFORM, warmFixture(), { hue = 360, saturationCeiling = 0.15, values = TARGET.values })
		expect(invalid.ok):toBe(false)
		assert(invalid.ok == false)
	end)
end)

describe("Image.deliver", function()
	local CELL = 4

	local function checkerboard(size: number): string
		return Codec.encodeRgba(size, size, function(x: number, y: number): Image.Rgba
			local value = if (x // CELL + y // CELL) % 2 == 0 then 20 else 235
			return { r = value, g = value, b = value, a = 255 }
		end)
	end

	local function upsample2x(bytes: string): string
		local image = decoded(bytes)
		return Codec.encodeRgba(image.width * 2, image.height * 2, function(x: number, y: number): Image.Rgba
			local base = ((y // 2) * image.width + (x // 2)) * 4
			return {
				r = buffer.readu8(image.pixels, base),
				g = buffer.readu8(image.pixels, base + 1),
				b = buffer.readu8(image.pixels, base + 2),
				a = buffer.readu8(image.pixels, base + 3),
			}
		end)
	end

	it("is a no-op at the declared size: identity filters, unchanged bytes", function()
		local source = checkerboard(64)
		local result = Deliver.run(TRANSFORM, source, 64, 64)
		expect(result.ok):toBe(true)
		assert(result.ok == true)
		local complete = result
		expect(complete.resampled):toBe(false)
		expect(complete.parameters.filterWidth):toBe "identity"
		expect(complete.parameters.filterHeight):toBe "identity"
		expect(complete.sha256.pre):toBe(complete.sha256.post)
		expect(complete.bytes):toBe(source)
	end)

	it("inverts a 2x nearest-neighbour upsample of a checkerboard back to the original", function()
		local original = checkerboard(64)
		local upsampled = upsample2x(original)
		expect(decoded(upsampled).width):toBe(128)
		local result = Deliver.run(TRANSFORM, upsampled, 64, 64)
		expect(result.ok):toBe(true)
		assert(result.ok == true)
		local complete = result
		expect(complete.resampled):toBe(true)
		expect(complete.parameters.filterWidth):toBe "area"
		expect(complete.bytes):toBe(original)
		expect(complete.preFacts.width):toBe(128)
		expect(complete.postFacts.width):toBe(64)
		expect(type(complete.preFacts.hfScreenPatternPeakRatio)):toBe "number"
	end)

	it("upsamples a smaller source with a windowed sinc and lands on the declared size", function()
		local result = Deliver.run(TRANSFORM, checkerboard(32), 64, 64)
		expect(result.ok):toBe(true)
		assert(result.ok == true)
		local complete = result
		expect(complete.resampled):toBe(true)
		expect(complete.parameters.filterWidth):toBe "lanczos3"
		expect(decoded(complete.bytes).width):toBe(64)
	end)

	it("resamples a non-integer ratio onto the declared size", function()
		local result = Deliver.run(TRANSFORM, checkerboard(300), 256, 256)
		expect(result.ok):toBe(true)
		assert(result.ok == true)
		expect(result.parameters.filterWidth):toBe "area"
		expect(decoded(result.bytes).width):toBe(256)
	end)

	it("is byte-deterministic across repeated runs on the same input", function()
		local source = upsample2x(checkerboard(48))
		local once = Deliver.run(TRANSFORM, source, 48, 48)
		local twice = Deliver.run(TRANSFORM, source, 48, 48)
		expect(once.ok):toBe(true)
		assert(once.ok == true)
		assert(twice.ok)
		expect(once.bytes):toBe(twice.bytes)
	end)

	it("refuses a non-whole or non-positive declared size and undecodable bytes", function()
		local source = checkerboard(16)
		expect(Deliver.run(TRANSFORM, source, 0, 16).ok):toBe(false)
		expect(Deliver.run(TRANSFORM, source, 16.5, 16).ok):toBe(false)
		expect(Deliver.run(TRANSFORM, source, -4, 16).ok):toBe(false)
		expect(Deliver.run(TRANSFORM, "not a png", 16, 16).ok):toBe(false)
	end)
end)

return nil
