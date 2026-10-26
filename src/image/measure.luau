--!strict

local Codec = require "./codec"
local Generate = require "../core"

export type Digest = Codec.Digest

export type Bounds = { minShortSide: number, maxLongSide: number }

export type Config = { digest: Digest, bounds: Bounds }

export type Measurement = {
	digest: string,
	byteCount: number,
	width: number,
	height: number,
	shortSide: number,
	longSide: number,
}

export type Evidence = { id: string, view: string, role: string, path: string }

export type Outcome = { ok: true, measurement: Measurement } | { ok: false, diagnostic: string }

export type Deps = { exists: (path: string) -> boolean, read: (path: string) -> string }

local PNG_SIGNATURE = "\137PNG\r\n\26\n"
local MEDIA_TYPE = "image/png"

local function pngDimensions(bytes: string): (number?, number?, string)
	if #bytes < 24 or string.sub(bytes, 1, 8) ~= PNG_SIGNATURE then
		return nil, nil, "the saved file does not carry a PNG signature"
	end
	if string.sub(bytes, 13, 16) ~= "IHDR" then
		return nil, nil, "the saved PNG does not open with an IHDR chunk"
	end
	local width = string.unpack(">I4", bytes, 17)
	local height = string.unpack(">I4", bytes, 21)
	return width, height, ""
end

local function measure(config: Config, bytes: string): Outcome
	local width, height, malformed = pngDimensions(bytes)
	if width == nil or height == nil then
		return { ok = false, diagnostic = malformed }
	end
	local shortSide, longSide = math.min(width, height), math.max(width, height)
	if shortSide < config.bounds.minShortSide or longSide > config.bounds.maxLongSide then
		return {
			ok = false,
			diagnostic = ("the saved PNG is %dx%d; the short side must be at least %d and the long side at most %d"):format(
				width,
				height,
				config.bounds.minShortSide,
				config.bounds.maxLongSide
			),
		}
	end
	return {
		ok = true,
		measurement = {
			digest = config.digest(bytes),
			byteCount = #bytes,
			width = width,
			height = height,
			shortSide = shortSide,
			longSide = longSide,
		},
	}
end

local function artifact(
	config: Config,
	id: string,
	locator: string,
	measurement: Measurement,
	semanticId: string?
): Generate.Artifact
	return {
		id = id,
		digest = measurement.digest,
		digestAlgorithm = "sha256",
		mediaType = MEDIA_TYPE,
		byteCount = measurement.byteCount,
		locator = locator,
		semanticId = semanticId,
		metadata = {
			width = tostring(measurement.width),
			height = tostring(measurement.height),
			shortSide = tostring(measurement.shortSide),
			longSide = tostring(measurement.longSide),
			minShortSide = tostring(config.bounds.minShortSide),
			maxLongSide = tostring(config.bounds.maxLongSide),
		},
	}
end

local function runStage(config: Config, deps: Deps, evidence: { Evidence }): Generate.StageOutcome
	if #evidence == 0 then
		return { status = "rejected", detail = "the measurement stage was given no evidence surface to measure" }
	end
	local artifacts: { Generate.Artifact } = {}
	for _, surface in evidence do
		if not deps.exists(surface.path) then
			return {
				status = "rejected",
				detail = ("evidence %s names %s, which does not exist"):format(surface.id, surface.path),
			}
		end
		local outcome = measure(config, deps.read(surface.path))
		if not outcome.ok then
			return { status = "rejected", detail = ("evidence %s: %s"):format(surface.id, outcome.diagnostic) }
		end
		table.insert(artifacts, artifact(config, surface.id, surface.path, outcome.measurement))
	end
	return { status = "returned", output = { artifacts = artifacts } }
end

return {
	MEDIA_TYPE = MEDIA_TYPE,
	PNG_SIGNATURE = PNG_SIGNATURE,
	pngDimensions = pngDimensions,
	measure = measure,
	artifact = artifact,
	runStage = runStage,
}
