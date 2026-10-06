--!strict

local Codec = require "./image/codec"
local Deliver = require "./image/deliver"
local Host = require "./image/host"
local Lane = require "./image/lane"
local Matte = require "./image/matte"
local Measure = require "./image/measure"
local Postprocess = require "./image/postprocess"
local Provider = require "./image/provider"
local Qa = require "./image/qa"
local Register = require "./image/register"
local Request = require "./image/request"
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
export type HostBinding = Host.Binding
export type HostMatteBinding = Host.MatteBinding
export type HostRegisterBinding = Host.RegisterBinding
export type HostDeliverBinding = Host.DeliverBinding
export type HostDeps = Host.Deps
export type HostOptions = Host.Options
export type HostTool = Host.Tool
export type HostTools = Host.Tools
export type LaneConfig = Lane.Config
export type LaneSummary = Lane.Summary
export type MatteParameters = Matte.Parameters
export type MatteResult = Matte.Result
export type MatteSuccess = Matte.Success
export type MeasureBounds = Measure.Bounds
export type MeasureConfig = Measure.Config
export type MeasureOutcome = Measure.Outcome
export type MeasureEvidence = Measure.Evidence
export type Measurement = Measure.Measurement
export type PostprocessConfig = Postprocess.Config
export type PostprocessKind = Postprocess.Kind
export type PostprocessTransform = Postprocess.Transform
export type ProviderConfig = Provider.Config
export type ProviderDeps = Provider.Deps
export type ProviderPaths = Provider.Paths
export type ProviderRequest = Provider.Request
export type ProviderRunResult = Provider.RunResult
export type QaAssessment = Qa.Assessment
export type QaPair = Qa.Pair
export type QaRefusal = Qa.Refusal
export type QaConfig = Qa.Config
export type QaDeclaration = Qa.Declaration
export type QaDeps = Qa.Deps
export type QaGate = Qa.Gate
export type QaThresholds = Qa.Thresholds
export type QaHueBand = Qa.HueBand
export type RegisterConfig = Register.Config
export type RegisterResult = Register.Result
export type RegisterSuccess = Register.Success
export type RegisterDeclarationTarget = Register.DeclarationTarget
export type RegisterFacts = Register.Facts
export type RegisterTarget = Register.Target
export type RegisterValues = Register.Values
export type RequestArtifact = Request.Artifact
export type RequestBound = Request.Bound
export type RequestConfig = Request.Config
export type RequestDecoded = Request.Decoded
export type RequestDocument = Request.Document
export type RequestRefusal = Request.Refusal
export type ReviewConfig = Review.Config
export type ReviewOutcome = Review.Outcome
export type ReviewRequest = Review.Request

return {
	codec = Codec,
	deliver = { run = Deliver.run },
	host = { create = Host.create },
	lane = { summary = Lane.summary },
	matte = { apply = Matte.apply, run = Matte.run },
	measure = {
		MEDIA_TYPE = Measure.MEDIA_TYPE,
		pngDimensions = Measure.pngDimensions,
		measure = Measure.measure,
		artifact = Measure.artifact,
		runStage = Measure.runStage,
	},
	postprocess = { runStage = Postprocess.runStage },
	provider = { runStage = Provider.runStage },
	qa = { assess = Qa.assess, gate = Qa.gate },
	register = { facts = Register.facts, run = Register.run },
	request = {
		fromBrief = Request.fromBrief,
		decode = Request.decode,
		bindings = Request.bindings,
		encode = Request.encode,
	},
	review = { DEFAULT_CONFIG = Review.DEFAULT_CONFIG, stage = Review.stage, runStage = Review.runStage },
}
