--!strict

local Generate = require "../src/core"
local Host = require "../src/host"

local ICON_DIGEST = string.rep("a", 64)
local NORMAL_VIEW_DIGEST = string.rep("b", 64)
local SMALL_VIEW_DIGEST = string.rep("c", 64)
local RUBRIC_FINGERPRINT = "rubric-icon-v1-4f1c9d"

local brief = Generate.brief {
	id = "example.icon.v1",
	kind = "image",
	intent = { role = "A product-neutral inventory icon" },
	review = {
		rubric = "icon",
		rubricFingerprint = RUBRIC_FINGERPRINT,
		rubricVersion = "1",
		views = { "normal", "32px" },
		blindness = "required",
		independence = "required",
	},
	provenance = {
		requireParentLineage = true,
		requiredRightsFacts = { "source", "license", "owner", "consent" } :: { Generate.RightsFactName },
	},
	delivery = { semanticId = "example.icon", target = "local" },
}

local plan = Generate.plan(brief, {
	{ id = "image", operation = "generate" },
	{ id = "capture", operation = "verify", dependsOn = { "image" } },
	{ id = "review", operation = "review", dependsOn = { "capture" } },
})

local packet: Generate.ReviewPacketDraft = {
	id = "example.icon.v1/packet/1",
	candidate = {
		candidateId = "example.icon",
		revision = 1,
		producer = "example-producer",
		artifacts = { { id = "example.icon.png", digest = ICON_DIGEST, digestAlgorithm = "sha256" } },
	},
	evidence = {
		{
			id = "example.icon.normal.png",
			digest = NORMAL_VIEW_DIGEST,
			digestAlgorithm = "sha256",
			view = "normal",
			role = "canonical-view",
		},
		{
			id = "example.icon.32px.png",
			digest = SMALL_VIEW_DIGEST,
			digestAlgorithm = "sha256",
			view = "32px",
			role = "canonical-view",
		},
	},
	rubric = { id = "icon", fingerprint = RUBRIC_FINGERPRINT, version = "1" },
	requestedViews = { "normal", "32px" },
	captureEnvironment = { renderer = "fixture-capture", colorSpace = "srgb" },
}

local bound = Generate.reviewPacket(packet, {
	briefId = brief.id,
	briefFingerprint = plan.briefFingerprint,
	planFingerprint = plan.fingerprint,
	stageId = "review",
})

local function reviewDraft(actor: string, role: string): Generate.ReviewDecisionDraft
	return {
		packetId = bound.id,
		packetFingerprint = bound.fingerprint,
		candidateFingerprint = bound.candidate.fingerprint,
		evidenceFingerprint = bound.evidenceFingerprint,
		rubric = bound.rubric,
		actor = actor,
		role = role,
		context = "independent",
		blind = true,
		certainty = "high",
		verdict = "approved",
		reasons = { "fixture satisfies the example rubric" },
	}
end

local produced = Generate.execute(
	brief,
	plan,
	Host.fake.create {
		outcomes = {
			image = {
				status = "returned",
				output = {
					artifacts = {
						{
							id = "example.icon.png",
							digest = ICON_DIGEST,
							digestAlgorithm = "sha256",
							mediaType = "image/png",
							semanticId = "example.icon",
							metadata = { pixelWidth = "512", pixelHeight = "512" },
						},
					},
					derivations = {
						{
							artifactId = "example.icon.png",
							artifactDigest = ICON_DIGEST,
							origin = "original",
							attempt = 1,
							environment = { runtime = "fixture" },
							rights = {
								source = { state = "known", value = "example:first-party-prompt" },
								license = { state = "known", value = "example:all-rights-reserved" },
								owner = { state = "known", value = "example:studio" },
								consent = { state = "known", value = "example:not-applicable" },
							},
						},
					},
				},
			},
			capture = {
				status = "returned",
				output = {
					artifacts = {
						{
							id = "example.icon.normal.png",
							digest = NORMAL_VIEW_DIGEST,
							digestAlgorithm = "sha256",
							mediaType = "image/png",
							metadata = { view = "normal" },
						},
						{
							id = "example.icon.32px.png",
							digest = SMALL_VIEW_DIGEST,
							digestAlgorithm = "sha256",
							mediaType = "image/png",
							metadata = { view = "32px" },
						},
					},
				},
			},
			review = {
				status = "returned",
				output = {
					reviewPacket = packet,
					decisions = {},
				},
			},
		},
	},
	{ capabilities = {}, destinations = {}, mutationBudget = 0 }
)

assert(produced.status == "produced", "native work must remain pending until its reviewers answer")
assert(
	Generate.receiptFingerprint(produced) == produced.fingerprint,
	"review collection requires the unchanged production receipt"
)
local receipt = Generate.continueReview(brief, plan, produced, {
	reviewDraft("example-reviewer-a", "art"),
})
assert(receipt.status == "accepted", "example receipt must resolve one approved review")
local manifest = Generate.manifest(receipt, { "example.icon.png" })
print(receipt.reviews[1].disposition)
print(manifest.entries[1].semanticId)
print(manifest.entries[1].reviewFingerprint)
print(manifest.fingerprint)

return manifest
