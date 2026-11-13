--!strict
local Fixture = require "./fixtures/image-codec"
local Image = require "../src/image"
local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Codec = Image.png
local Deliver = Image.deliver
local TRANSFORM: Image.DeliverConfig = { codec = Codec, digest = Fixture.digest }
local function decoded(bytes: string): Image.Image
	local value = Codec.decode(bytes)
	expect(value.ok):toBe(true)
	assert(value.ok == true)
	return value.image
end

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
