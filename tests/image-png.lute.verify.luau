--!strict
local Image = require "../src/image"
local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Png = Image.png

local COMPRESSED =
	"89504e470d0a1a0a0000000d49484452000000040000000308020000003b963991000000154944415478da6364b0a9d08001267624c082cc01004e6202cc2010842e0000000049454e44ae426082"

local function fromHex(hex: string): string
	return (
		string.gsub(hex, "%x%x", function(pair: string): string
			return string.char(assert(tonumber(pair, 16)))
		end)
	)
end

describe("Image.png", function()
	it("decodes authored RGBA pixels without losing colour or alpha", function()
		local bytes = Png.encodeRgba(2, 1, function(x: number): Image.Rgba
			return if x == 0 then { r = 12, g = 34, b = 56, a = 78 } else { r = 90, g = 123, b = 145, a = 167 }
		end)
		local decoded = Png.decode(bytes)
		assert(decoded.ok == true)
		expect(decoded.image.width):toBe(2)
		expect(decoded.image.height):toBe(1)
		expect(decoded.image.channels):toBe(4)
		expect(Png.sample(decoded.image, 0, 0, 0)):toBe(12)
		expect(Png.sample(decoded.image, 0, 0, 3)):toBe(78)
		expect(Png.sample(decoded.image, 1, 0, 1)):toBe(123)
		expect(Png.sample(decoded.image, 1, 0, 3)):toBe(167)
	end)

	it("decodes a deflate-compressed RGB image through Sub, Up and Paeth rows", function()
		local decoded = Png.decode(fromHex(COMPRESSED))
		assert(decoded.ok == true)
		expect(decoded.image.width):toBe(4)
		expect(decoded.image.height):toBe(3)
		expect(decoded.image.channels):toBe(3)
		for y = 0, 2 do
			for x = 0, 3 do
				for channel = 0, 2 do
					expect(Png.sample(decoded.image, x, y, channel)):toBe((x * 40 + y * 7 + channel * 60) % 256)
				end
			end
		end
	end)

	it("returns the inflater refusal when a PNG carries an invalid compressed stream", function()
		local bytes = Png.encodeRgba(1, 1, function(): Image.Rgba
			return { r = 12, g = 34, b = 56, a = 255 }
		end)
		local found = string.find(bytes, "IDAT", 1, true)
		assert(found ~= nil)
		local start = found + 4
		local corrupted = string.sub(bytes, 1, start - 1) .. "\0\0" .. string.sub(bytes, start + 2)
		local decoded = Png.decode(corrupted)
		assert(decoded.ok == false)
		expect(decoded.reason):toBe "the compressed stream is not zlib deflate"
	end)

	it("refuses bytes without a PNG signature", function()
		local decoded = Png.decode "invalid"
		assert(decoded.ok == false)
		expect(decoded.reason):toBe "the file does not carry a PNG signature"
	end)

	it("satisfies the image codec interface", function()
		local codec: Image.Codec = Png
		expect(codec.decode(codec.encodeRgba(1, 1, function(): Image.Rgba
			return { r = 1, g = 2, b = 3, a = 4 }
		end)).ok):toBe(true)
	end)
end)

return nil
