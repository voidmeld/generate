--!strict

local json = require "@std/json"
local process = require "@std/process"

export type Result = { ok: boolean, stdout: string, stderr: string, exitcode: number }
export type Run = (command: { string }) -> Result

export type Probe = {
	durationSeconds: number,
	codec: string,
	sampleRate: number,
	channels: number,
	bitRate: number?,
}

export type Loudness = { integratedLufs: number, loudnessRange: number, truePeakDbfs: number }

export type Convert = {
	input: string,
	output: string,
	filter: string?,
	sampleRate: number?,
	channels: number?,
	codec: string?,
	bitrate: string?,
}

export type Failure = { ok: false, diagnostic: string }

local QUIET: { string } = { "-y", "-hide_banner", "-loglevel", "error" }

local function defaultRun(command: { string }): Result
	local result = process.run(command)
	return { ok = result.ok, stdout = result.stdout, stderr = result.stderr, exitcode = result.exitcode }
end

local function failure(tool: string, result: Result): Failure
	return { ok = false, diagnostic = ("%s exited %d: %s"):format(tool, result.exitcode, result.stderr) }
end

local function convertCommand(options: Convert): { string }
	local command: { string } = { "ffmpeg", table.unpack(QUIET) }
	table.insert(command, "-i")
	table.insert(command, options.input)
	if options.filter then
		table.insert(command, "-af")
		table.insert(command, options.filter)
	end
	if options.sampleRate then
		table.insert(command, "-ar")
		table.insert(command, tostring(options.sampleRate))
	end
	if options.channels then
		table.insert(command, "-ac")
		table.insert(command, tostring(options.channels))
	end
	if options.codec then
		table.insert(command, "-codec:a")
		table.insert(command, options.codec)
	end
	if options.bitrate then
		table.insert(command, "-b:a")
		table.insert(command, options.bitrate)
	end
	table.insert(command, options.output)
	return command
end

local function reviewCommand(
	input: string,
	output: string,
	width: number,
	waveHeight: number,
	spectrumHeight: number
): { string }
	local graph = (
		"[0:a]asplit=2[a1][a2];[a1]showwavespic=s=%dx%d:colors=0x7fd0ff[w];"
		.. "[a2]showspectrumpic=s=%dx%d:legend=0:scale=log:fscale=log[s];[w][s]vstack=inputs=2[v]"
	):format(width, waveHeight, width, spectrumHeight)
	return {
		"ffmpeg",
		table.unpack(QUIET),
		"-i",
		input,
		"-filter_complex",
		graph,
		"-map",
		"[v]",
		"-frames:v",
		"1",
		output,
	}
end

local function convert(options: Convert, run: Run?): { ok: true } | Failure
	local result = (run or defaultRun)(convertCommand(options))
	if not result.ok then
		return failure("ffmpeg", result)
	end
	return { ok = true }
end

local function review(
	input: string,
	output: string,
	size: { width: number, waveHeight: number, spectrumHeight: number }?,
	run: Run?
): { ok: true } | Failure
	local use = size or { width = 1200, waveHeight = 240, spectrumHeight = 360 }
	local result = (run or defaultRun)(reviewCommand(input, output, use.width, use.waveHeight, use.spectrumHeight))
	if not result.ok then
		return failure("ffmpeg", result)
	end
	return { ok = true }
end

local function probe(path: string, run: Run?): { ok: true, probe: Probe } | Failure
	local result = (run or defaultRun) {
		"ffprobe",
		"-v",
		"error",
		"-show_format",
		"-show_streams",
		"-of",
		"json",
		path,
	}
	if not result.ok then
		return failure("ffprobe", result)
	end
	local parsed, document = pcall(json.deserialize, result.stdout)
	if not parsed or type(document) ~= "table" then
		return { ok = false, diagnostic = "ffprobe returned no JSON document" }
	end
	local doc = document :: {
		streams: {
			{
				codec_type: unknown,
				codec_name: unknown,
				sample_rate: string | number?,
				channels: string | number?,
			}
		}?,
		format: { duration: string | number?, bit_rate: string | number? }?,
	}
	local stream: { codec_type: unknown, codec_name: unknown, sample_rate: string | number?, channels: string | number? }? =
		nil
	for _, candidate in
		(doc.streams or {}) :: { { codec_type: unknown, codec_name: unknown, sample_rate: string | number?, channels: string | number? } }
	do
		if candidate.codec_type == "audio" then
			stream = candidate
			break
		end
	end
	local duration = tonumber(doc.format and doc.format.duration)
	if stream == nil or duration == nil then
		return { ok = false, diagnostic = "the file has no measurable audio stream" }
	end
	return {
		ok = true,
		probe = {
			durationSeconds = duration,
			codec = tostring(stream.codec_name),
			sampleRate = tonumber(stream.sample_rate) or 0,
			channels = tonumber(stream.channels) or 0,
			bitRate = tonumber((doc.format :: { duration: string | number?, bit_rate: string | number? }).bit_rate),
		},
	}
end

local function loudness(path: string, run: Run?): { ok: true, loudness: Loudness } | Failure
	local result = (run or defaultRun) {
		"ffmpeg",
		"-hide_banner",
		"-nostats",
		"-i",
		path,
		"-af",
		"ebur128=peak=true",
		"-f",
		"null",
		"-",
	}
	if not result.ok then
		return failure("ffmpeg", result)
	end
	local summary = string.match(result.stderr, "Summary:.*$") or ""
	local integrated = tonumber(string.match(summary, "I:%s+(%-?[%d%.]+) LUFS"))
	local range = tonumber(string.match(summary, "LRA:%s+(%-?[%d%.]+) LU"))
	local peak = tonumber(string.match(summary, "Peak:%s+(%-?[%d%.]+) dBFS"))
	if integrated == nil or range == nil or peak == nil then
		return { ok = false, diagnostic = "the ebur128 summary could not be read" }
	end
	return { ok = true, loudness = { integratedLufs = integrated, loudnessRange = range, truePeakDbfs = peak } }
end

return table.freeze {
	convertCommand = convertCommand,
	reviewCommand = reviewCommand,
	convert = convert,
	review = review,
	probe = probe,
	loudness = loudness,
}
