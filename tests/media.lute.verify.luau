--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local Lute = require "../src/lute"
local Media = require "../src/media"
local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local RATE = 8000

local function tone(seconds: number, amplitude: number, silentLead: number): { number }
	local samples: { number } = {}
	for index = 0, math.floor(seconds * RATE) - 1 do
		if index < silentLead * RATE then
			table.insert(samples, 0)
		else
			table.insert(samples, amplitude * math.sin(2 * math.pi * 440 * index / RATE))
		end
	end
	return samples
end

describe("wav measurement", function()
	it("measures duration, peak, level and silence of a generated tone", function()
		local result = Media.wav.measure(Media.wav.encode(RATE, 1, tone(1, 0.5, 0.25)))
		expect(result.ok):toBe(true)
		assert(result.ok)
		local measurement = result.measurement
		expect(measurement.sampleRate):toBe(RATE)
		expect(measurement.durationSeconds):toBe(1)
		expect(math.abs(measurement.peak - 0.5) < 0.001):toBe(true)
		expect(math.abs(measurement.peakDbfs + 6.02) < 0.05):toBe(true)
		expect(math.abs(measurement.leadingSilenceSeconds - 0.25) < 0.01):toBe(true)
		expect(math.abs(measurement.silentFraction - 0.25) < 0.02):toBe(true)
	end)

	it("reports true silence and refuses malformed files", function()
		local silent = Media.wav.measure(Media.wav.encode(RATE, 1, tone(0.5, 0, 0)))
		assert(silent.ok)
		expect(silent.measurement.peakDbfs):toBe(-200)
		expect(Media.wav.measure("not audio").ok):toBe(false)
		expect(Media.wav.measure(string.sub(Media.wav.encode(RATE, 1, { 0.1 }), 1, 40)).ok):toBe(false)
	end)
end)

describe("media adapters", function()
	it("builds convert and review commands without running anything", function()
		local command = Lute.media.convertCommand {
			input = "a.wav",
			output = "a.mp3",
			filter = "loudnorm",
			sampleRate = 44100,
			channels = 2,
			codec = "libmp3lame",
			bitrate = "192k",
		}
		expect(command[1]):toBe "ffmpeg"
		expect(command[#command]):toBe "a.mp3"
		expect(table.find(command, "-af") ~= nil):toBe(true)
		local review = Lute.media.reviewCommand("a.wav", "a.png", 100, 20, 30)
		expect(review[#review]):toBe "a.png"
	end)

	it("reports a failing tool through its diagnostic", function()
		local run: Lute.MediaRun = function()
			return { ok = false, stdout = "", stderr = "no such file", exitcode = 1 }
		end
		local probe = Lute.media.probe("missing.wav", run)
		expect(probe.ok):toBe(false)
		assert(not probe.ok)
		expect(probe.diagnostic):toBe "ffprobe exited 1: no such file"
		expect(Lute.media.loudness("missing.wav", run).ok):toBe(false)
	end)

	it("parses recorded probe and loudness output", function()
		local probe = Lute.media.probe("a.wav", function()
			return {
				ok = true,
				stdout = '{"streams":[{"codec_type":"audio","codec_name":"pcm_s16le","sample_rate":"8000","channels":1}],"format":{"duration":"1.000000","bit_rate":"128000"}}',
				stderr = "",
				exitcode = 0,
			}
		end)
		assert(probe.ok)
		expect(probe.probe.durationSeconds):toBe(1)
		expect(probe.probe.codec):toBe "pcm_s16le"
		local loudness = Lute.media.loudness("a.wav", function()
			return {
				ok = true,
				stdout = "",
				stderr = "  Summary:\n\n  Integrated loudness:\n    I:         -23.4 LUFS\n  Loudness range:\n    LRA:         1.2 LU\n  True peak:\n    Peak:       -6.1 dBFS\n",
				exitcode = 0,
			}
		end)
		assert(loudness.ok)
		expect(loudness.loudness.integratedLufs):toBe(-23.4)
		expect(loudness.loudness.truePeakDbfs):toBe(-6.1)
	end)

	it("converts, probes, measures loudness and renders a review image with real ffmpeg", function()
		if not process.run({ "sh", "-c", "command -v ffmpeg && command -v ffprobe" }).ok then
			return
		end
		local root = ".lute/tmp/media-spec"
		fs.createDirectory(root, { makeParents = true })
		local wav = root .. "/tone.wav"
		fs.writeStringToFile(wav, Media.wav.encode(RATE, 1, tone(1, 0.5, 0)))
		local mp3 = root .. "/tone.mp3"
		expect(Lute.media.convert({ input = wav, output = mp3, codec = "libmp3lame", bitrate = "64k" }).ok):toBe(true)
		local probe = Lute.media.probe(mp3)
		expect(probe.ok):toBe(true)
		assert(probe.ok)
		expect(math.abs(probe.probe.durationSeconds - 1) < 0.2):toBe(true)
		local loudness = Lute.media.loudness(wav)
		expect(loudness.ok):toBe(true)
		assert(loudness.ok)
		expect(math.abs(loudness.loudness.truePeakDbfs + 6) < 0.5):toBe(true)
		local image = root .. "/review.png"
		expect(Lute.media.review(wav, image, { width = 64, waveHeight = 16, spectrumHeight = 16 }).ok):toBe(true)
		expect(string.sub(fs.readFileToString(image), 2, 4)):toBe "PNG"
		fs.removeDirectory(root, { recursive = true })
	end)
end)

return nil
