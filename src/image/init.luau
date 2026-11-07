--!strict

local Codec = require "./image/codec"
local Deliver = require "./image/deliver"
local Measure = require "./image/measure"
local Review = require "./image/review"

export type Codec = Codec.Codec
export type Digest = Codec.Digest
export type Decoded = Codec.Decoded
export type Image = Codec.Image
export type Rgba = Codec.Rgba
export type DeliverConfig = Deliver.Config
export type DeliverFacts = Deliver.Facts
export type DeliverResult = Deliver.Result
export type DeliverSuccess = Deliver.Success
export type MeasureBounds = Measure.Bounds
export type MeasureConfig = Measure.Config
export type MeasureOutcome = Measure.Outcome
export type MeasureEvidence = Measure.Evidence
export type Measurement = Measure.Measurement
export type ReviewConfig = Review.Config
export type ReviewOutcome = Review.Outcome
export type ReviewRequest = Review.Request

return {
	codec = Codec,
	deliver = { run = Deliver.run },
	measure = {
		MEDIA_TYPE = Measure.MEDIA_TYPE,
		pngDimensions = Measure.pngDimensions,
		measure = Measure.measure,
		artifact = Measure.artifact,
		runStage = Measure.runStage,
	},
	review = { DEFAULT_CONFIG = Review.DEFAULT_CONFIG, stage = Review.stage, runStage = Review.runStage },
}
