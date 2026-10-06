--!strict

local Image = require "../../src/image"

local thresholds: Image.QaThresholds = {
	opaqueAlpha = 250,
	transparentAlpha = 5,
	keyResidueSaturation = 60,
	gutterLumaRange = 14,
	brightMaximaLuma = 150,
	chromaSaturationFloor = 0.15,
	maxWrapSeamRatio = 1.25,
	maxInteriorSeamRatio = 1.5,
	maxFractionalSeamRatio = 1.3,
	maxUnlitVignetteRatio = 1.1,
	maxUnlitLightingGradient = 8,
	maxBrightMaximaFraction = 0.005,
	minEdgeBlurRatio = 0.8,
	maxHfScreenPatternPeakRatio = 50,
	maxEdgeMirrorCorrelation = 0.8,
	minMedianLuma = 45,
	minPairedLuminanceRatio = 0.95,
	maxPairedLuminanceRatio = 1.05,
	minPairedRegistrationCorrelation = 0.7,
	minSemiTransparentFraction = 0.005,
	maxKeyResidueFraction = 0.002,
	maxHaloRatio = 1.25,
	maxPanels = 1,
	minGutterBand = 4,
	warnVignetteRatio = 1.12,
	warnLightingGradient = 12,
	warnLumaSpread = 48,
}

return thresholds
