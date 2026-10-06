--!strict

local Media = require "./lute/media"

export type MediaRun = Media.Run
export type MediaResult = Media.Result
export type MediaProbe = Media.Probe
export type MediaLoudness = Media.Loudness
export type MediaConvert = Media.Convert
export type MediaFailure = Media.Failure

return {
	media = Media,
	process = require "./lute/process",
}
