--!strict

local Wav = require "./media/wav"

export type WavMeasurement = Wav.Measurement
export type WavOutcome = Wav.Outcome

return {
	wav = Wav,
}
