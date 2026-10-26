--!strict

export type Measurement = {
	sampleRate: number,
	channels: number,
	bitsPerSample: number,
	frames: number,
	durationSeconds: number,
	peak: number,
	peakDbfs: number,
	rmsDbfs: number,
	silentFraction: number,
	leadingSilenceSeconds: number,
}

export type Outcome = { ok: true, measurement: Measurement } | { ok: false, diagnostic: string }

local SILENCE = 0.001
local FLOOR_DB = -200

local function db(linear: number): number
	if linear <= 0 then
		return FLOOR_DB
	end
	return math.max(FLOOR_DB, 20 * math.log10(linear))
end

local function sampleReader(bits: number, float: boolean): ((bytes: string, offset: number) -> number)?
	if float and bits == 32 then
		return function(bytes, offset)
			return string.unpack("<f", bytes, offset) :: number
		end
	end
	if float then
		return nil
	end
	if bits == 16 then
		return function(bytes, offset)
			return (string.unpack("<i2", bytes, offset) :: number) / 32768
		end
	end
	if bits == 24 then
		return function(bytes, offset)
			local value = string.unpack("<I3", bytes, offset) :: number
			if value >= 8388608 then
				value -= 16777216
			end
			return value / 8388608
		end
	end
	if bits == 32 then
		return function(bytes, offset)
			return (string.unpack("<i4", bytes, offset) :: number) / 2147483648
		end
	end
	return nil
end

local function measure(bytes: string): Outcome
	if #bytes < 44 or string.sub(bytes, 1, 4) ~= "RIFF" or string.sub(bytes, 9, 12) ~= "WAVE" then
		return { ok = false, diagnostic = "the file is not a RIFF WAVE container" }
	end
	local format: { tag: number, channels: number, rate: number, bits: number }? = nil
	local dataStart, dataLength = nil, 0
	local position = 13
	while position + 8 <= #bytes + 1 do
		local id = string.sub(bytes, position, position + 3)
		local size = string.unpack("<I4", bytes, position + 4) :: number
		if id == "fmt " then
			local tag, channels, rate, _, _, bits = string.unpack("<I2I2I4I4I2I2", bytes, position + 8)
			format = {
				tag = tag :: number,
				channels = channels :: number,
				rate = rate :: number,
				bits = bits :: number,
			}
		elseif id == "data" then
			dataStart = position + 8
			dataLength = math.min(size, #bytes - dataStart + 1)
			break
		end
		position += 8 + size + (size % 2)
	end
	if format == nil or dataStart == nil then
		return { ok = false, diagnostic = "the WAVE file has no fmt or data chunk" }
	end
	local waveFormat = format
	local float = waveFormat.tag == 3
	if waveFormat.tag ~= 1 and not float then
		return { ok = false, diagnostic = "only PCM and 32-bit float WAVE data is measured" }
	end
	local read = sampleReader(waveFormat.bits, float)
	if read == nil or waveFormat.channels < 1 or waveFormat.rate < 1 then
		return { ok = false, diagnostic = "the WAVE sample format is not supported" }
	end
	local width = waveFormat.bits // 8
	local count = dataLength // width
	local frames = count // waveFormat.channels
	if frames == 0 then
		return { ok = false, diagnostic = "the WAVE file holds no audio frames" }
	end
	local peak, squares, silent = 0, 0, 0
	local leading: number? = nil
	for frame = 0, frames - 1 do
		local framePeak = 0
		for channel = 0, waveFormat.channels - 1 do
			local value = read(bytes, dataStart + (frame * waveFormat.channels + channel) * width)
			local magnitude = math.abs(value)
			squares += value * value
			framePeak = math.max(framePeak, magnitude)
		end
		peak = math.max(peak, framePeak)
		if framePeak < SILENCE then
			silent += 1
		elseif leading == nil then
			leading = frame
		end
	end
	return {
		ok = true,
		measurement = {
			sampleRate = waveFormat.rate,
			channels = waveFormat.channels,
			bitsPerSample = waveFormat.bits,
			frames = frames,
			durationSeconds = frames / waveFormat.rate,
			peak = peak,
			peakDbfs = db(peak),
			rmsDbfs = db(math.sqrt(squares / (frames * waveFormat.channels))),
			silentFraction = silent / frames,
			leadingSilenceSeconds = (leading or frames) / waveFormat.rate,
		},
	}
end

local function encode(sampleRate: number, channels: number, samples: { number }): string
	local pieces: { string } = {}
	for _, sample in samples do
		table.insert(pieces, string.pack("<i2", math.clamp(math.round(sample * 32767), -32768, 32767)))
	end
	local data = table.concat(pieces)
	return table.concat {
		"RIFF",
		string.pack("<I4", 36 + #data),
		"WAVEfmt ",
		string.pack("<I4I2I2I4I4I2I2", 16, 1, channels, sampleRate, sampleRate * channels * 2, channels * 2, 16),
		"data",
		string.pack("<I4", #data),
		data,
	}
end

return table.freeze {
	SILENCE = SILENCE,
	measure = measure,
	encode = encode,
}
