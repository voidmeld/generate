--!strict

local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect

local Bracket = require "../src/core/evidence-bracket"
local Generate = require "../src/core"
local Revision = require "../src/core/revision"
local Host = require "../src/host"

local CANDIDATE_DIGEST = string.rep("a", 64)
local EVIDENCE_DIGEST = string.rep("b", 64)
local SECOND_DIGEST = string.rep("c", 64)

local RUBRIC: Generate.RubricIdentity = { id = "module", fingerprint = "rubric-module-v1", version = "1" }

type BriefOptions = {
	blindness: ("required" | "optional")?,
	independence: ("required" | "optional")?,
	requireParentLineage: boolean?,
	requiredRightsFacts: { Generate.RightsFactName }?,
}

local function brief(options: BriefOptions?): Generate.Brief
	local settings: BriefOptions = options or {}
	return Generate.brief {
		id = "fixture.wall.v1",
		kind = "modular-mesh",
		intent = { role = "fixture wall", style = "fixture" },
		constraints = { triangleBudget = 1000 },
		review = {
			rubric = RUBRIC.id,
			rubricFingerprint = RUBRIC.fingerprint,
			rubricVersion = RUBRIC.version,
			views = { "front", "corner" },
			blindness = settings.blindness,
			independence = settings.independence,
		},
		provenance = {
			requireParentLineage = settings.requireParentLineage,
			requiredRightsFacts = settings.requiredRightsFacts,
		},
		delivery = { semanticId = "fixture.wall", target = "fixture-host" },
	}
end

local function artifact(id: string): Generate.Artifact
	return {
		id = id,
		digest = CANDIDATE_DIGEST,
		digestAlgorithm = "sha256",
		mediaType = "model/gltf-binary",
		metadata = {},
	}
end

local function candidateArtifact(id: string, digest: string): Generate.Artifact
	return {
		id = id,
		digest = digest,
		digestAlgorithm = "sha256",
		mediaType = "model/gltf-binary",
		semanticId = "fixture.wall",
		metadata = {},
	}
end

local function evidenceArtifact(id: string, digest: string): Generate.Artifact
	return {
		id = id,
		digest = digest,
		digestAlgorithm = "sha256",
		mediaType = "image/png",
		metadata = {},
	}
end

local KNOWN_RIGHTS = {
	source = { state = "known" :: "known", value = "fixture:first-party" },
	license = { state = "known" :: "known", value = "fixture:reserved" },
	owner = { state = "known" :: "known", value = "fixture:studio" },
	consent = { state = "known" :: "known", value = "fixture:not-applicable" },
}

local function originalDerivation(id: string, digest: string): Generate.DerivationDraft
	return {
		artifactId = id,
		artifactDigest = digest,
		origin = "original",
		attempt = 1,
		environment = { runtime = "fixture" },
		rights = KNOWN_RIGHTS,
	}
end

local function packetDraft(
	revision: number,
	candidateId: string,
	candidateDigest: string,
	evidenceId: string,
	evidenceDigest: string,
	producer: string
): Generate.ReviewPacketDraft
	return {
		id = ("fixture.packet.%d"):format(revision),
		candidate = {
			candidateId = "fixture.wall",
			revision = revision,
			producer = producer,
			artifacts = { { id = candidateId, digest = candidateDigest, digestAlgorithm = "sha256" } },
		},
		evidence = {
			{
				id = evidenceId,
				digest = evidenceDigest,
				digestAlgorithm = "sha256",
				view = "front",
				role = "canonical-view",
			},
		},
		rubric = RUBRIC,
		requestedViews = { "front", "corner" },
		captureEnvironment = { renderer = "fixture", colorSpace = "srgb" },
	}
end

local function bind(
	value: Generate.Brief,
	plan: Generate.Plan,
	stageId: string,
	draft: Generate.ReviewPacketDraft
): Generate.ReviewPacket
	return Generate.reviewPacket(draft, {
		briefId = value.id,
		briefFingerprint = plan.briefFingerprint,
		planFingerprint = plan.fingerprint,
		stageId = stageId,
	})
end

type DraftOptions = {
	verdict: Generate.Verdict?,
	blind: boolean?,
	context: ("independent" | "shared")?,
	candidateFingerprint: string?,
	evidenceFingerprint: string?,
	rubric: Generate.RubricIdentity?,
	role: string?,
	score: number?,
	refusals: { string }?,
}

local function reviewDraft(
	packet: Generate.ReviewPacket,
	actor: string,
	options: DraftOptions?
): Generate.ReviewDecisionDraft
	local settings: DraftOptions = options or {}
	local verdict: Generate.Verdict = settings.verdict or "approved"
	return {
		packetId = packet.id,
		packetFingerprint = packet.fingerprint,
		candidateFingerprint = settings.candidateFingerprint or packet.candidate.fingerprint,
		evidenceFingerprint = settings.evidenceFingerprint or packet.evidenceFingerprint,
		rubric = settings.rubric or packet.rubric,
		actor = actor,
		role = settings.role or "art",
		context = settings.context or "independent",
		blind = if settings.blind == nil then true else settings.blind,
		modelFamily = "fixture-family",
		providerFamily = "fixture-provider",
		certainty = "high",
		verdict = verdict,
		reasons = { "fixture reason" },
		score = settings.score,
		refusals = settings.refusals,
	}
end

local AUTHORITY: Generate.Authority = {
	capabilities = { "generate", "publish" },
	destinations = { "fixture-host" },
	mutationBudget = 1,
}

local REVIEW_STAGES: { Generate.StageDraft } = {
	{ id = "candidate", operation = "generate" },
	{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
	{ id = "review", operation = "review", dependsOn = { "capture" } },
}

local function reviewOutcomes(
	decisions: { Generate.ReviewDecisionDraft },
	draft: Generate.ReviewPacketDraft
): { [string]: Generate.StageOutcome }
	return {
		candidate = {
			status = "returned",
			output = {
				artifacts = { candidateArtifact("candidate", CANDIDATE_DIGEST) },
				derivations = { originalDerivation("candidate", CANDIDATE_DIGEST) },
			},
		},
		capture = {
			status = "returned",
			output = { artifacts = { evidenceArtifact("front-view", EVIDENCE_DIGEST) } },
		},
		review = { status = "returned", output = { reviewPacket = draft, decisions = decisions } },
	}
end

describe("Generate briefs and plans", function()
	it("keeps the simple path to four ordinary calls", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
		local receipt = Generate.execute(value, plan, Host.fake.create(), AUTHORITY)
		expect(receipt.status):toEqual "produced"
	end)

	it("normalizes a versioned review and provenance contract", function()
		local value = brief()
		expect(value.schemaVersion):toEqual(1)
		expect(value.review.rubric.fingerprint):toEqual "rubric-module-v1"
		expect(value.provenance.requireParentLineage):toEqual(true)
		expect(value.review.independence):toEqual "required"
		expect(value.delivery.semanticId):toEqual "fixture.wall"
	end)

	it("refuses unpinned rubrics and invalid independence", function()
		expect(function()
			Generate.brief {
				id = "bad",
				kind = "image",
				intent = { role = "bad" },
				review = { rubric = "image", rubricFingerprint = "", views = { "front" } },
				delivery = { semanticId = "bad", target = "local" },
			}
		end):toThrow()
		expect(function()
			brief(({ independence = "unknown" } :: unknown) :: BriefOptions)
		end):toThrow()
	end)

	it("produces the same plan fingerprint from the same declared data", function()
		local value = brief()
		local stages: { Generate.StageDraft } = {
			{ id = "make", operation = "generate", requires = { "generate" } },
			{ id = "review", operation = "review", dependsOn = { "make" }, requires = {} },
		}
		expect(Generate.plan(value, stages).fingerprint):toEqual(Generate.plan(value, stages).fingerprint)
	end)

	it("refuses unknown dependencies and unsafe mutation plans", function()
		expect(function()
			Generate.plan(brief(), { { id = "late", operation = "custom", dependsOn = { "missing" } } })
		end):toThrow()
		expect(function()
			Generate.plan(brief(), { { id = "publish", operation = "publish", mutation = true } })
		end):toThrow()
	end)

	it("rejects incomplete reviews rather than inventing acceptance", function()
		expect(function()
			Generate.brief {
				id = "bad",
				kind = "image",
				intent = { role = "bad" },
				review = { rubric = "image", rubricFingerprint = "rubric-image-v1", views = {} },
				delivery = { semanticId = "bad", target = "local" },
			}
		end):toThrow()
	end)

	it("rejects secret-shaped data before it reaches a plan or receipt", function()
		expect(function()
			Generate.brief {
				id = "secret",
				kind = "image",
				intent = { role = "fixture" },
				constraints = { provider = { apiKey = "must-not-enter" } },
				review = { rubric = "fixture", rubricFingerprint = "rubric-fixture-v1", views = { "front" } },
				delivery = { semanticId = "fixture", target = "local" },
			}
		end):toThrow()
		expect(function()
			Generate.plan(brief(), {
				{
					id = "make",
					operation = "generate",
					parameters = { access_token = "must-not-enter" },
				},
			})
		end):toThrow()
	end)

	it("rejects cyclic and non-finite canonical state", function()
		local cyclic: { [string]: unknown } = {}
		cyclic.self = cyclic
		expect(function()
			Generate.fingerprint(cyclic)
		end):toThrow()
		expect(function()
			Generate.brief {
				id = "nonfinite",
				kind = "image",
				intent = { role = "fixture" },
				constraints = { scale = math.nan },
				review = { rubric = "fixture", rubricFingerprint = "rubric-fixture-v1", views = { "front" } },
				delivery = { semanticId = "fixture", target = "local" },
			}
		end):toThrow()
	end)

	it("refuses a plan after the bound brief contents change", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
		value.intent.role = "changed after planning"
		expect(function()
			Generate.execute(value, plan, Host.fake.create(), AUTHORITY)
		end):toThrow()
	end)

	it("refuses every executable plan field after compilation", function()
		local mutators = {
			function(stage: Generate.Stage)
				stage.parameters.mode = "changed"
			end,
			function(stage: Generate.Stage)
				table.insert(stage.requires, "changed")
			end,
			function(stage: Generate.Stage)
				table.insert(stage.dependsOn, "changed")
			end,
			function(stage: Generate.Stage)
				stage.rollback = "required"
			end,
		}
		for _, mutate in mutators do
			local value = brief()
			local plan = Generate.plan(value, {
				{ id = "make", operation = "generate", parameters = { mode = "original" } },
			})
			mutate(plan.stages[1])
			expect(function()
				Generate.execute(value, plan, Host.fake.create(), AUTHORITY)
			end):toThrow "contents changed after compilation"
		end
	end)
end)

describe("Generate review packets and review resolution", function()
	it("binds every decision to one exact candidate, evidence, rubric, view, and capture set", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		expect(packet.candidate.fingerprint).never:toEqual(packet.fingerprint)
		expect(packet.requestedViews):toEqual { "front", "corner" }
		expect(packet.captureEnvironment.renderer):toEqual "fixture"
		local decision = Generate.reviewDecision(reviewDraft(packet, "reviewer-a"))
		expect(decision.blind):toEqual(true)
		expect(decision.modelFamily):toEqual "fixture-family"
		expect(decision.certainty):toEqual "high"
	end)

	it("refuses a packet without candidate digests, evidence, or a capture environment", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local empty = table.clone(draft)
		empty.evidence = {}
		expect(function()
			bind(value, plan, "review", empty)
		end):toThrow()
		local uncaptured = table.clone(draft)
		uncaptured.captureEnvironment = {}
		expect(function()
			bind(value, plan, "review", uncaptured)
		end):toThrow()
	end)

	it("counts distinct eligible actors and excludes duplicates and self-review as data", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		local decisions = {
			Generate.reviewDecision(reviewDraft(packet, "reviewer-a")),
			Generate.reviewDecision(reviewDraft(packet, "reviewer-a", { role = "safety" })),
			Generate.reviewDecision(reviewDraft(packet, "producer")),
		}
		local review = Generate.resolveReview(packet, value.review, decisions, { stale = false })
		expect(#review.decisions):toEqual(1)
		expect(review.disposition):toEqual "unresolved"
		expect(review.excluded[1].reason):toEqual "duplicate-actor"
		expect(review.excluded[2].reason):toEqual "producer-self-review"
	end)

	it("permits truthful producer inspection only when the brief explicitly makes independence optional", function()
		local value = brief { independence = "optional", blindness = "optional" }
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		local inspected =
			Generate.reviewDecision(reviewDraft(packet, "producer", { context = "shared", blind = false }))
		local review = Generate.resolveReview(packet, value.review, { inspected })
		expect(review.disposition):toEqual "approved"
		expect(review.decisions[1].actor):toEqual "producer"
		local required = table.clone(value.review)
		required.independence = "required"
		local refused = Generate.resolveReview(packet, required, { inspected })
		expect(refused.disposition):toEqual "incomplete"
		expect(refused.excluded[1].reason):toEqual "producer-self-review"
		inspected.evidenceFingerprint = "changed"
		expect(Generate.resolveReview(packet, value.review, { inspected }).disposition):toEqual "incomplete"
		expect(Generate.briefFingerprint(value) == Generate.briefFingerprint(brief())):toEqual(false)
	end)

	it("excludes stale-candidate, evidence-drift, and rubric-drift decisions", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		local decisions = {
			Generate.reviewDecision(reviewDraft(packet, "reviewer-a", { candidateFingerprint = "gen-fp2-stale" })),
			Generate.reviewDecision(reviewDraft(packet, "reviewer-b", { evidenceFingerprint = "gen-fp2-other" })),
			Generate.reviewDecision(reviewDraft(packet, "reviewer-c", {
				rubric = { id = "module", fingerprint = "rubric-module-v2" },
			})),
		}
		local review = Generate.resolveReview(packet, value.review, decisions, { stale = false })
		expect(review.disposition):toEqual "incomplete"
		expect(#review.decisions):toEqual(0)
		local reasons: { string } = {}
		for _, entry in review.excluded do
			table.insert(reasons, entry.reason)
		end
		table.sort(reasons)
		expect(reasons):toEqual { "candidate-drift", "evidence-drift", "rubric-drift" }
	end)

	it("excludes a reviewer that is neither blind nor independent when the contract requires both", function()
		local value = brief { blindness = "required", independence = "required" }
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		local sighted = Generate.resolveReview(
			packet,
			value.review,
			{ Generate.reviewDecision(reviewDraft(packet, "reviewer-a", { blind = false })) },
			{ stale = false }
		)
		expect(sighted.excluded[1].reason):toEqual "blindness-required"
		local shared = Generate.resolveReview(
			packet,
			value.review,
			{ Generate.reviewDecision(reviewDraft(packet, "reviewer-a", { context = "shared" })) },
			{ stale = false }
		)
		expect(shared.excluded[1].reason):toEqual "independence-required"
	end)

	it("blocks multiple eligible reviewers instead of resolving consensus", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		local unresolved = Generate.resolveReview(packet, value.review, {
			Generate.reviewDecision(reviewDraft(packet, "reviewer-a")),
			Generate.reviewDecision(reviewDraft(packet, "reviewer-b", { verdict = "rejected" })),
			Generate.reviewDecision(reviewDraft(packet, "reviewer-c", { verdict = "abstained" })),
		}, { stale = false })
		expect(unresolved.disposition):toEqual "unresolved"
		expect(unresolved.resolution):toContain "eligible=3"
		local carried = Generate.resolveReview(packet, value.review, {
			Generate.reviewDecision(reviewDraft(packet, "reviewer-a")),
			Generate.reviewDecision(reviewDraft(packet, "reviewer-b")),
			Generate.reviewDecision(reviewDraft(packet, "reviewer-c", { verdict = "rejected" })),
		}, { stale = false })
		expect(carried.disposition):toEqual "unresolved"
	end)

	it("requires declared independence at direct resolution and blocks abstention", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		local contract = table.clone(value.review)
		local changes = (contract :: unknown) :: { [string]: unknown }
		changes.independence = "unknown"
		expect(function()
			Generate.resolveReview(packet, contract, {})
		end):toThrow "declared independence"
		local review = Generate.resolveReview(
			packet,
			value.review,
			{ Generate.reviewDecision(reviewDraft(packet, "reviewer-a", { verdict = "abstained" })) }
		)
		expect(review.disposition):toEqual "unresolved"
	end)

	it("resolves a stale review without pretending it approved", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		local review = Generate.resolveReview(
			packet,
			value.review,
			{ Generate.reviewDecision(reviewDraft(packet, "reviewer-a")) },
			{ stale = true, reason = "superseded by a later transform" }
		)
		expect(review.disposition):toEqual "stale"
		expect(review.reasons[1]):toContain "superseded"
	end)
end)

describe("review contract retirement", function()
	it("refuses a retired score-based acceptance contract instead of silently accepting it", function()
		expect(function()
			Generate.brief({
				id = "fixture.retired",
				kind = "image",
				intent = { role = "fixture" },
				review = {
					rubric = "fixture",
					rubricFingerprint = "fixture",
					views = { "front" },
					secondaryAcceptance = { minScore = 0, reviewers = 1 },
				},
				delivery = { semanticId = "fixture", target = "local" },
			} :: Generate.BriefDraft)
		end):toThrow "review decision must approve"
	end)
end)

describe("Generate structured provenance", function()
	it("records parents, invocation facts, attempt ordinal, and disposition", function()
		local derivation = Generate.derivation {
			artifactId = "derived",
			artifactDigest = SECOND_DIGEST,
			origin = "derived" :: Generate.DerivationOrigin,
			parents = {
				{ artifactId = "candidate", artifactDigest = CANDIDATE_DIGEST },
				{ receiptId = "earlier/receipt", jobId = "earlier/job", briefFingerprint = "gen-fp2-earlier" },
			} :: { Generate.ParentRef },
			inputDigests = { CANDIDATE_DIGEST },
			referenceDigests = { EVIDENCE_DIGEST },
			invocation = {
				tool = "fixture",
				toolVersion = "1",
				parametersFingerprint = Generate.fingerprint {},
				deterministic = true,
			},
			environment = { runtime = "fixture" },
			attempt = 2,
			disposition = "active",
			rights = KNOWN_RIGHTS,
		}
		expect(derivation.attempt):toEqual(2)
		expect(derivation.rights.state):toEqual "known"
		expect(#derivation.parents):toEqual(2)
		expect(Generate.rights({}).state):toEqual "unknown"
		expect(Generate.rights({ source = { state = "known", value = "fixture" } }).state):toEqual "partial"
	end)

	it("refuses missing parent lineage and rights knowledge without a recorded fact", function()
		expect(function()
			Generate.derivation {
				artifactId = "derived",
				artifactDigest = SECOND_DIGEST,
				origin = "derived" :: Generate.DerivationOrigin,
				parents = {},
			}
		end):toThrow()
		expect(function()
			Generate.derivation {
				artifactId = "original",
				artifactDigest = CANDIDATE_DIGEST,
				origin = "original",
				rights = { license = { state = "known" } },
			}
		end):toThrow()
		expect(function()
			Generate.derivation {
				artifactId = "original",
				artifactDigest = CANDIDATE_DIGEST,
				origin = "original",
				rights = { license = { state = "unknown", value = "invented" } },
			}
		end):toThrow()
	end)

	it("blocks unknown required history and rights a parent does not carry", function()
		local unknownParent = Generate.derivation {
			artifactId = "candidate",
			artifactDigest = CANDIDATE_DIGEST,
			origin = "imported" :: Generate.DerivationOrigin,
			parents = { { receiptId = "legacy/import-ledger" } },
		}
		local child = Generate.derivation {
			artifactId = "derived",
			artifactDigest = SECOND_DIGEST,
			origin = "derived" :: Generate.DerivationOrigin,
			parents = { { artifactId = "candidate", artifactDigest = CANDIDATE_DIGEST } },
			rights = { license = { state = "known", value = "fixture:invented" } },
		}
		local byId = { candidate = unknownParent, derived = child }
		local contract: Generate.ProvenanceContract = {
			requireParentLineage = true,
			requiredRightsFacts = { "license" },
		}
		expect(Generate.provenanceFaults(unknownParent, contract, byId, "candidate")[1]):toContain "unknown-history"
		expect(Generate.provenanceFaults(child, contract, byId, "derived")[1]):toContain "does not carry"
		expect(#Generate.provenanceFaults(nil, contract, byId, "absent")):toEqual(1)
	end)
end)

describe("Generate execution", function()
	it("bounds declared and actual provider cost before acceptance", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "make", operation = "generate", estimatedCostMicros = 10 },
		})
		local denied = Generate.execute(value, plan, Host.fake.create(), {
			capabilities = {},
			destinations = {},
			mutationBudget = 0,
			costBudgetMicros = 9,
		})
		expect(denied.status):toEqual "unsupported"
		expect(denied.stages[1].detail):toContain "cost-budget"

		local allowed = Generate.execute(
			value,
			plan,
			Host.fake.create { outcomes = { make = { status = "returned", output = { costMicros = 7 } } } },
			{ capabilities = {}, destinations = {}, mutationBudget = 0, costBudgetMicros = 10 }
		)
		expect(allowed.costMicros):toEqual(7)
	end)

	it("continues independent review without replaying completed production", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify" },
			{ id = "review", operation = "review" },
		})
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local produced =
			Generate.execute(value, plan, Host.fake.create { outcomes = reviewOutcomes({}, draft) }, AUTHORITY)
		expect(produced.status):toEqual "produced"
		expect(#produced.decisions):toEqual(0)
		expect(Generate.receiptFingerprint(produced)):toEqual(produced.fingerprint)
		local before = Generate.canonical(produced)

		local reviewed = Generate.continueReview(value, plan, produced, { reviewDraft(packet, "reviewer-a") })
		expect(reviewed.status):toEqual "accepted"
		expect(#reviewed.decisions):toEqual(1)
		expect(reviewed.stages[3].decisions[1].actor):toEqual "reviewer-a"
		expect(reviewed.reviews[1].disposition):toEqual "approved"
		expect(reviewed.startedMicros):toEqual(produced.startedMicros)
		expect(reviewed.durationMicros):toEqual(produced.durationMicros)
		expect(reviewed.costMicros):toEqual(produced.costMicros)
		expect(produced.status):toEqual "produced"
		expect(#produced.decisions):toEqual(0)
		expect(Generate.canonical(produced)):toEqual(before)

		reviewed.reviewPackets[1].candidate.artifacts[1].digest = SECOND_DIGEST
		reviewed.artifacts[1].metadata.changed = "returned-only"
		reviewed.stages[1].artifacts[1].metadata.changed = "returned-stage-only"
		expect(Generate.canonical(produced)):toEqual(before)
	end)

	it("refuses review continuation from changed state, unknown packets, or completed mutations", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local produced =
			Generate.execute(value, plan, Host.fake.create { outcomes = reviewOutcomes({}, draft) }, AUTHORITY)

		local changed = table.clone(produced)
		changed.environment = { fixture = "changed" }
		expect(Generate.receiptFingerprint(changed)).never:toEqual(changed.fingerprint)
		expect(function()
			Generate.continueReview(value, plan, changed, { reviewDraft(packet, "reviewer-a") })
		end):toThrow "unchanged receipt"

		local unknown = reviewDraft(packet, "reviewer-a")
		unknown.packetId = "unknown-packet"
		expect(function()
			Generate.continueReview(value, plan, produced, { unknown })
		end):toThrow "unknown packet"

		local mutationPlan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify" },
			{ id = "review", operation = "review" },
			{ id = "mutate", operation = "custom", mutation = true, rollback = "required" },
		})
		local mutationDraft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local mutationPacket = bind(value, mutationPlan, "review", mutationDraft)
		local outcomes = reviewOutcomes({}, mutationDraft)
		outcomes.mutate = { status = "returned", output = { rollbackToken = "fixture-rollback" } }
		local mutated = Generate.execute(
			value,
			mutationPlan,
			Host.fake.create { outcomes = outcomes },
			{ capabilities = {}, destinations = {}, mutationBudget = 1 }
		)
		expect(mutated.status):toEqual "produced"
		expect(function()
			Generate.continueReview(value, mutationPlan, mutated, { reviewDraft(mutationPacket, "reviewer-a") })
		end):toThrow "non-mutation stages"
	end)

	it("derives stable idempotency keys from the bound plan and stage", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
		local first: { string } = {}
		local second: { string } = {}
		Generate.execute(value, plan, Host.fake.create { idempotencyKeys = first }, AUTHORITY)
		Generate.execute(value, plan, Host.fake.create { idempotencyKeys = second }, AUTHORITY)
		expect(first):toEqual(second)
		expect(first[1]):toContain(plan.fingerprint)
	end)

	it("records production without calling it accepted", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate", requires = { "generate" } } })
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				capabilities = { "generate" },
				outcomes = { make = { status = "returned", output = { artifacts = { artifact "candidate" } } } },
			},
			AUTHORITY
		)
		expect(receipt.status):toEqual "produced"
		expect(receipt.limitations[1]):toContain "no resolved review"
	end)

	it("records exact artifact inputs for every dispatched stage", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "make", operation = "generate" },
			{ id = "transform", operation = "transform", dependsOn = { "make" } },
		})
		local derived = artifact "derived"
		derived.digest = SECOND_DIGEST
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = {
					make = { status = "returned", output = { artifacts = { artifact "source" } } },
					transform = { status = "returned", output = { artifacts = { derived } } },
				},
			},
			AUTHORITY
		)
		expect(#receipt.stages[1].inputArtifacts):toEqual(0)
		expect(receipt.stages[2].inputArtifacts[1].id):toEqual "source"
	end)

	it("rejects duplicate artifact identities instead of making lineage ambiguous", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "one", operation = "generate" },
			{ id = "two", operation = "transform", dependsOn = { "one" } },
		})
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = {
					one = { status = "returned", output = { artifacts = { artifact "same" } } },
					two = { status = "returned", output = { artifacts = { artifact "same" } } },
				},
			},
			AUTHORITY
		)
		expect(receipt.status):toEqual "failed"
		expect(receipt.stages[2].detail):toContain "duplicate artifact id"
	end)

	it("refuses stochastic evidence from a stage declared deterministic", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate", deterministic = true } })
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = {
					make = {
						status = "returned",
						output = {
							invocations = {
								{
									tool = "fixture",
									toolVersion = "1",
									parametersFingerprint = Generate.fingerprint {},
									deterministic = false,
								},
							},
						},
					},
				},
			},
			AUTHORITY
		)
		expect(receipt.status):toEqual "failed"
		expect(receipt.stages[1].detail):toContain "stochastic invocation"
	end)

	it("retains safe stage metadata and refuses secret-shaped metadata", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
		local safe = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = { make = { status = "returned", output = { metadata = { operationId = "op-1" } } } },
			},
			AUTHORITY
		)
		expect(safe.stages[1].metadata.operationId):toEqual "op-1"

		local unsafe = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = { make = { status = "returned", output = { metadata = { apiKey = "leak" } } } },
			},
			AUTHORITY
		)
		expect(unsafe.status):toEqual "failed"
	end)

	it("accepts only a resolved review bound to the exact delivered candidate", function()
		local value = brief { blindness = "required", independence = "required" }
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft),
			},
			AUTHORITY
		)
		expect(receipt.status):toEqual "accepted"
		expect(receipt.reviews[1].disposition):toEqual "approved"
		expect(receipt.reviews[1].decisions[1].actor):toEqual "reviewer-a"
		expect(receipt.derivations[1].disposition):toEqual "approved"
		expect(receipt.reviewPackets[1].fingerprint):toEqual(packet.fingerprint)
		expect(receipt.reviewContract.rubric.fingerprint):toEqual "rubric-module-v1"
	end)

	it("refuses a review packet whose rubric or requested views drift from the brief", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local drifted = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		drifted.rubric = { id = "module", fingerprint = "rubric-module-v2" }
		local rubricReceipt =
			Generate.execute(value, plan, Host.fake.create { outcomes = reviewOutcomes({}, drifted) }, AUTHORITY)
		expect(rubricReceipt.status):toEqual "failed"
		expect(rubricReceipt.stages[3].detail):toContain "against brief rubric"

		local views = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		views.requestedViews = { "front" }
		local viewReceipt =
			Generate.execute(value, plan, Host.fake.create { outcomes = reviewOutcomes({}, views) }, AUTHORITY)
		expect(viewReceipt.status):toEqual "failed"
		expect(viewReceipt.stages[3].detail):toContain "requested review views"
	end)

	it("refuses a packet bound to evidence this receipt never produced", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "absent-view", EVIDENCE_DIGEST, "producer")
		local receipt =
			Generate.execute(value, plan, Host.fake.create { outcomes = reviewOutcomes({}, draft) }, AUTHORITY)
		expect(receipt.status):toEqual "failed"
		expect(receipt.stages[3].detail):toContain "bound evidence artifact"
	end)

	it("keeps extra reviewers and missing review out of acceptance", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local split = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = reviewOutcomes(
					{ reviewDraft(packet, "reviewer-a"), reviewDraft(packet, "reviewer-b", { verdict = "rejected" }) },
					draft
				),
			},
			AUTHORITY
		)
		expect(split.status):toEqual "produced"
		expect(split.reviews[1].disposition):toEqual "unresolved"

		local incomplete =
			Generate.execute(value, plan, Host.fake.create { outcomes = reviewOutcomes({}, draft) }, AUTHORITY)
		expect(incomplete.status):toEqual "produced"
		expect(incomplete.reviews[1].disposition):toEqual "incomplete"
		expect(incomplete.limitations[1]):toContain "incomplete"
	end)

	it("excludes duplicate actors and producer self-review through a real run", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = reviewOutcomes({
					reviewDraft(packet, "reviewer-a"),
					reviewDraft(packet, "reviewer-a", { role = "safety" }),
					reviewDraft(packet, "producer", { role = "safety" }),
				}, draft),
			},
			AUTHORITY
		)
		expect(receipt.status):toEqual "produced"
		expect(receipt.reviews[1].disposition):toEqual "unresolved"
		expect(#receipt.reviews[1].excluded):toEqual(2)
	end)

	it("does not let an approval survive a later transform of the reviewed candidate", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
			{ id = "review", operation = "review", dependsOn = { "capture" } },
			{ id = "polish", operation = "transform", dependsOn = { "review" } },
		})
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft)
		outcomes.polish = {
			status = "returned",
			output = {
				artifacts = { candidateArtifact("polished", SECOND_DIGEST) },
				derivations = {
					{
						artifactId = "polished",
						artifactDigest = SECOND_DIGEST,
						origin = "derived" :: Generate.DerivationOrigin,
						parents = { { artifactId = "candidate", artifactDigest = CANDIDATE_DIGEST } },
						attempt = 2,
						rights = KNOWN_RIGHTS,
					},
				},
			},
		}
		local receipt = Generate.execute(value, plan, Host.fake.create { outcomes = outcomes }, AUTHORITY)
		expect(receipt.status):toEqual "produced"
		expect(receipt.reviews[1].disposition):toEqual "stale"
		expect(receipt.derivations[1].disposition):toEqual "superseded"
		expect(receipt.derivations[2].attempt):toEqual(2)
	end)

	it("excludes a decision carried onto a newer candidate revision", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
			{ id = "review", operation = "review", dependsOn = { "capture" } },
		})
		local firstDraft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local firstPacket = bind(value, plan, "review", firstDraft)
		local secondDraft = packetDraft(2, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local secondPacket = bind(value, plan, "review", secondDraft)
		local carried = reviewDraft(secondPacket, "reviewer-a")
		carried.candidateFingerprint = firstPacket.candidate.fingerprint
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create { outcomes = reviewOutcomes({ carried }, secondDraft) },
			AUTHORITY
		)
		expect(receipt.status):toEqual "produced"
		expect(receipt.reviews[1].excluded[1].reason):toEqual "candidate-drift"
	end)

	it("blocks publication and promotion when required history is unknown", function()
		local value = brief { requiredRightsFacts = { "license", "owner" } :: { Generate.RightsFactName } }
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft)
		outcomes.candidate = {
			status = "returned",
			output = {
				artifacts = { candidateArtifact("candidate", CANDIDATE_DIGEST) },
				derivations = {
					{
						artifactId = "candidate",
						artifactDigest = CANDIDATE_DIGEST,
						origin = "imported" :: Generate.DerivationOrigin,
						parents = { { receiptId = "legacy/import-ledger" } },
					},
				},
			},
		}
		local receipt = Generate.execute(value, plan, Host.fake.create { outcomes = outcomes }, AUTHORITY)
		expect(receipt.status):toEqual "produced"
		expect(receipt.limitations[1]):toContain "unknown-history"
		expect(function()
			Generate.manifest(receipt, { "candidate" })
		end):toThrow()
	end)

	it("refuses a delivered artifact with no derivation record at all", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft)
		outcomes.candidate = {
			status = "returned",
			output = { artifacts = { candidateArtifact("candidate", CANDIDATE_DIGEST) } },
		}
		local receipt = Generate.execute(value, plan, Host.fake.create { outcomes = outcomes }, AUTHORITY)
		expect(receipt.status):toEqual "produced"
		expect(receipt.limitations[1]):toContain "no derivation record"
	end)

	it("refuses a derivation that names an artifact the stage did not produce", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local outcomes = reviewOutcomes({}, draft)
		outcomes.capture = {
			status = "returned",
			output = {
				artifacts = { evidenceArtifact("front-view", EVIDENCE_DIGEST) },
				derivations = { originalDerivation("candidate", CANDIDATE_DIGEST) },
			},
		}
		local receipt = Generate.execute(value, plan, Host.fake.create { outcomes = outcomes }, AUTHORITY)
		expect(receipt.status):toEqual "failed"
		expect(receipt.stages[2].detail):toContain "without producing it"
	end)

	it("emits a deterministic semantic manifest only from an unchanged accepted receipt", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create { outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft) },
			AUTHORITY
		)
		local manifest = Generate.manifest(receipt, { "candidate" })
		expect(manifest.entries[1].semanticId):toEqual "fixture.wall"
		expect(manifest.entries[1].reviewFingerprint):toEqual(receipt.reviews[1].fingerprint)
		expect(manifest.entries[1].candidateFingerprint):toEqual(packet.candidate.fingerprint)
		expect(manifest.receiptFingerprint):toEqual(receipt.fingerprint)

		expect(function()
			Generate.manifest(receipt, { "front-view" })
		end):toThrow()

		receipt.artifacts[1].semanticId = "changed"
		expect(function()
			Generate.manifest(receipt, { "candidate" })
		end):toThrow()
	end)

	it("never publishes before one resolved decision binds the delivered artifact", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
			{ id = "review", operation = "review", dependsOn = { "capture" } },
			{
				id = "publish",
				operation = "publish",
				dependsOn = { "review" },
				mutation = true,
				rollback = "required",
			},
		})
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local outcomes = reviewOutcomes({}, draft)
		outcomes.publish = { status = "returned", output = { rollbackToken = "should-not-run" } }
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create { capabilities = { "publish" }, outcomes = outcomes },
			AUTHORITY
		)
		expect(receipt.status):toEqual "unsupported"
		expect(receipt.stages[4].status):toEqual "unsupported"
		expect(receipt.stages[4].detail):toContain "resolved-review-decision"
	end)

	it("publishes once the review resolved and the delivered digest still matches", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
			{ id = "review", operation = "review", dependsOn = { "capture" } },
			{
				id = "publish",
				operation = "publish",
				dependsOn = { "review" },
				mutation = true,
				rollback = "required",
			},
		})
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft)
		outcomes.publish = { status = "returned", output = { rollbackToken = "asset-version:1" } }
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create { capabilities = { "publish" }, outcomes = outcomes },
			AUTHORITY
		)
		expect(receipt.status):toEqual "accepted"
		expect(receipt.stages[4].status):toEqual "returned"
	end)

	it("compensates mutations newest-first and retains every rollback failure", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
			{ id = "review", operation = "review", dependsOn = { "capture" } },
			{
				id = "publish",
				operation = "publish",
				dependsOn = { "review" },
				mutation = true,
				rollback = "required",
			},
			{ id = "readback", operation = "verify", dependsOn = { "publish" } },
		})
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft)
		outcomes.publish = { status = "returned", output = { rollbackToken = "asset-version:1" } }
		outcomes.readback = { status = "faulted", detail = "readback failed" }
		local trace: { string } = {}
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				capabilities = { "publish" },
				trace = trace,
				compensationFaults = { publish = "rollback refused" },
				outcomes = outcomes,
			},
			AUTHORITY
		)
		expect(receipt.status):toEqual "failed"
		expect(trace[5]):toEqual "run:readback"
		expect(trace[6]):toEqual "rollback:publish"
		expect(receipt.compensations[1].status):toEqual "faulted"
	end)

	it("fails safely when a mutating host operation omits its rollback token", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
			{ id = "review", operation = "review", dependsOn = { "capture" } },
			{ id = "reserve", operation = "custom", dependsOn = { "review" }, mutation = true, rollback = "required" },
			{
				id = "publish",
				operation = "publish",
				dependsOn = { "reserve" },
				mutation = true,
				rollback = "required",
			},
		})
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft)
		outcomes.reserve = { status = "returned", output = { rollbackToken = "reservation" } }
		outcomes.publish = { status = "returned", output = {} }
		local trace: { string } = {}
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create { outcomes = outcomes, trace = trace },
			{ capabilities = {}, destinations = { "fixture-host" }, mutationBudget = 2 }
		)
		expect(receipt.status):toEqual "failed"
		expect(receipt.stages[5].status):toEqual "faulted"
		expect(trace[6]):toEqual "rollback:reserve"
	end)

	it("compensates the current mutation when its returned contract is invalid", function()
		local value = brief()
		local plan = Generate.plan(value, {
			{ id = "candidate", operation = "generate" },
			{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
			{ id = "review", operation = "review", dependsOn = { "capture" } },
			{
				id = "publish",
				operation = "publish",
				dependsOn = { "review" },
				mutation = true,
				rollback = "required",
			},
		})
		local draft = packetDraft(1, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		local packet = bind(value, plan, "review", draft)
		local bad = artifact "published"
		bad.digest = "not-a-digest"
		local outcomes = reviewOutcomes({ reviewDraft(packet, "reviewer-a") }, draft)
		outcomes.publish = {
			status = "returned",
			output = { artifacts = { bad }, rollbackToken = "published-version" },
		}
		local trace: { string } = {}
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create { capabilities = { "publish" }, trace = trace, outcomes = outcomes },
			AUTHORITY
		)
		expect(receipt.status):toEqual "failed"
		expect(trace[5]):toEqual "rollback:publish"
	end)

	it("does not dispatch a stage without both host capability and consumer authority", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate", requires = { "generate" } } })
		local receipt = Generate.execute(value, plan, Host.fake.create { capabilities = {} }, AUTHORITY)
		expect(receipt.status):toEqual "unsupported"
		expect(receipt.stages[1].status):toEqual "unsupported"
	end)
end)

describe("quota evaluation", function()
	local function draft(value: number, kind: string?): Generate.QuotaDraft
		return {
			subject = "fixture.module",
			quotas = {
				{ name = "triangles", value = value, quota = 4000 },
				{ name = "textures", value = 1, quota = 2 },
			},
			kind = if kind ~= nil then { name = "collision", kind = kind, allowedKinds = { "box", "hull" } } else nil,
		}
	end

	it("reports a subject within every declared quota", function()
		local report = Generate.evaluateQuota(draft(1200, "box"))
		expect(report.status):toEqual "within"
		expect(report.overruns):toEqual {}
		expect(report.subject):toEqual "fixture.module"
		expect((report.kind :: Generate.QuotaKindOutcome).allowed):toEqual(true)
	end)

	it("counts a value exactly equal to its quota as within quota", function()
		local report = Generate.evaluateQuota(draft(4000, "box"))
		expect(report.status):toEqual "within"
		expect(report.outcomes[1].over):toEqual(false)
	end)

	it("names every measure over its quota, sorted, and never guesses a cause", function()
		local report = Generate.evaluateQuota {
			subject = "fixture.module",
			quotas = {
				{ name = "triangles", value = 9000, quota = 4000 },
				{ name = "textures", value = 5, quota = 2 },
			},
		}
		expect(report.status):toEqual "over"
		expect(report.overruns):toEqual { "textures", "triangles" }
		expect(report.kind):toBeNil()
	end)

	it("refuses an enumerated kind that is absent from its allowlist", function()
		local report = Generate.evaluateQuota(draft(500, "precise-decomposition"))
		expect(report.status):toEqual "over"
		expect((report.kind :: Generate.QuotaKindOutcome).allowed):toEqual(false)
		expect(report.overruns):toEqual { "collision:precise-decomposition" }
	end)

	it("compares a measure at its ceiling and a kind against its allowed list", function()
		local function over(value: number): boolean
			return Generate.evaluateQuota({
				subject = "fixture",
				quotas = { { name = "triangles", value = value, quota = 10 } },
			}).status == "over"
		end
		expect(over(10)):toEqual(false)
		expect(over(11)):toEqual(true)
		local function allowed(kind: string, kinds: { string }): boolean
			return (Generate.evaluateQuota({
				subject = "fixture",
				quotas = {},
				kind = { name = "collision", kind = kind, allowedKinds = kinds },
			}).kind :: Generate.QuotaKindOutcome).allowed
		end
		expect(allowed("box", { "box", "hull" })):toEqual(true)
		expect(function()
			allowed("box", {})
		end):toThrow "allows no value"
	end)

	it("refuses a declaration it cannot evaluate rather than reporting a verdict", function()
		expect(function()
			Generate.evaluateQuota { subject = "", quotas = { { name = "triangles", value = 1, quota = 2 } } }
		end):toThrow()
		expect(function()
			Generate.evaluateQuota { subject = "fixture.module", quotas = {} }
		end):toThrow()
		expect(function()
			Generate.evaluateQuota {
				subject = "fixture.module",
				quotas = {
					{ name = "triangles", value = 1, quota = 2 },
					{ name = "triangles", value = 1, quota = 3 },
				},
			}
		end):toThrow()
		expect(function()
			Generate.evaluateQuota {
				subject = "fixture.module",
				quotas = { { name = "triangles", value = 1, quota = -1 } },
			}
		end):toThrow()
		expect(function()
			Generate.evaluateQuota {
				subject = "fixture.module",
				quotas = {},
				kind = { name = "collision", kind = "box", allowedKinds = {} },
			}
		end):toThrow()
	end)
end)

describe("evidence bracket", function()
	local function bracket(): Generate.EvidenceBracket
		return Generate.evidenceBracket {
			id = "fixture.bracket",
			poses = {
				{ id = "front", evidenceId = "01-front", parameters = { azimuth = 0 } :: { [string]: unknown } },
				{ id = "side", evidenceId = "02-side", parameters = { azimuth = 90 } :: { [string]: unknown } },
				{ id = "rear", evidenceId = "03-rear", parameters = { azimuth = 180 } :: { [string]: unknown } },
			},
		}
	end

	local function captures(): { Generate.EvidenceCapture }
		return {
			{ pose = "front", digest = "aa" },
			{ pose = "side", digest = "bb" },
			{ pose = "rear", digest = "cc" },
		}
	end

	it("plans an ordered bracket and keeps consumer parameters opaque", function()
		local planned = bracket()
		expect(planned.schemaVersion):toEqual(1)
		expect(#planned.poses):toEqual(3)
		expect(planned.poses[2].index):toEqual(2)
		expect(planned.poses[2].evidenceId):toEqual "02-side"
		expect(planned.poses[2].parameters.azimuth :: number):toEqual(90)
		expect((Bracket.poseFor(planned, "03-rear") :: Generate.EvidencePose).id):toEqual "rear"
		expect(Bracket.poseFor(planned, "primary-angle")):toBeNil()
	end)

	it("binds a complete in-order bracket into an ordered evidence manifest", function()
		local report = Generate.bindEvidence(bracket(), captures())
		expect(report.status):toEqual "bound"
		expect(report.reasons):toEqual {}
		expect(report.ordered):toEqual { "front:aa", "side:bb", "rear:cc" }
		local rows = Generate.evidenceManifest(report)
		expect(#rows):toEqual(3)
		expect(rows[1].evidenceId):toEqual "01-front"
		expect(rows[3].pose):toEqual "rear"
	end)

	it("accepts a capture named by its evidence id as readily as by its pose id", function()
		local report = Generate.bindEvidence(bracket(), {
			{ pose = "01-front", digest = "aa" },
			{ pose = "02-side", digest = "bb" },
			{ pose = "03-rear", digest = "cc" },
		})
		expect(report.status):toEqual "bound"
		expect(report.entries[1].pose):toEqual "front"
	end)

	it("refuses a short bracket and names every pose it never saw", function()
		local short = { captures()[1], captures()[2] }
		local report = Generate.bindEvidence(bracket(), short)
		expect(report.status):toEqual "refused"
		expect(report.faults[1].reason):toEqual(Generate.EVIDENCE_BRACKET_REASONS.SHORT)
		expect(report.reasons[1]):toEqual "bracket fixture.bracket was offered 2 of its 3 poses and is missing rear"
		expect(report.entries):toEqual {}
		expect(function()
			Generate.evidenceManifest(report)
		end):toThrow()
	end)

	it("refuses an empty bracket rather than reporting an empty manifest", function()
		local report = Generate.bindEvidence(bracket(), {})
		expect(report.status):toEqual "refused"
		expect(report.faults[1].reason):toEqual(Generate.EVIDENCE_BRACKET_REASONS.EMPTY)
	end)

	it("refuses a reordered bracket at the exact position that drifted", function()
		local reordered = captures()
		reordered[1], reordered[2] = reordered[2], reordered[1]
		local report = Generate.bindEvidence(bracket(), reordered)
		expect(report.status):toEqual "refused"
		expect(report.faults[1].reason):toEqual(Generate.EVIDENCE_BRACKET_REASONS.OUT_OF_ORDER)
		expect(report.faults[1].index):toEqual(1)
		expect(report.faults[1].pose):toEqual "side"
	end)

	it("refuses a duplicated pose, an undeclared pose, and a pose that never posed", function()
		local twice = Generate.bindEvidence(bracket(), {
			{ pose = "front", digest = "aa" },
			{ pose = "front", digest = "aa" },
			{ pose = "rear", digest = "cc" },
		})
		expect(twice.faults[1].reason):toEqual(Generate.EVIDENCE_BRACKET_REASONS.DUPLICATE)

		local unknown = Generate.bindEvidence(bracket(), {
			{ pose = "primary-angle", digest = "aa" },
			{ pose = "side", digest = "bb" },
			{ pose = "rear", digest = "cc" },
		})
		expect(unknown.faults[1].reason):toEqual(Generate.EVIDENCE_BRACKET_REASONS.UNKNOWN)

		local held = captures()
		held[2] = { pose = "side", digest = "bb", posed = false }
		local unposed = Generate.bindEvidence(bracket(), held)
		expect(unposed.faults[1].reason):toEqual(Generate.EVIDENCE_BRACKET_REASONS.UNPOSED)
		expect(unposed.status):toEqual "refused"
	end)

	it("holds the consumer to the digest requirement it declared", function()
		local undigested = captures()
		undigested[3] = { pose = "rear" }
		local missing = Generate.bindEvidence(bracket(), undigested)
		expect(missing.faults[1].reason):toEqual(Generate.EVIDENCE_BRACKET_REASONS.MISSING_DIGEST)

		local order = Generate.bindEvidence(bracket(), {
			{ pose = "front", posed = true },
			{ pose = "side", posed = true },
			{ pose = "rear", posed = true },
		}, "absent")
		expect(order.status):toEqual "bound"
		expect(order.ordered):toEqual { "front", "side", "rear" }
		expect(Generate.bindEvidence(bracket(), captures(), "absent").faults[1].reason):toEqual(
			Generate.EVIDENCE_BRACKET_REASONS.UNEXPECTED_DIGEST
		)
	end)

	it("refuses a bracket declaration it cannot plan rather than repairing it", function()
		expect(function()
			Generate.evidenceBracket { id = "", poses = { { id = "front", evidenceId = "01-front" } } }
		end):toThrow()
		expect(function()
			Generate.evidenceBracket { id = "fixture.bracket", poses = {} }
		end):toThrow()
		expect(function()
			Generate.evidenceBracket { id = "fixture.bracket", poses = { { id = "", evidenceId = "01-front" } } }
		end):toThrow()
		expect(function()
			Generate.evidenceBracket { id = "fixture.bracket", poses = { { id = "front", evidenceId = "" } } }
		end):toThrow()
		expect(function()
			Generate.evidenceBracket {
				id = "fixture.bracket",
				poses = {
					{ id = "front", evidenceId = "01-front" },
					{ id = "front", evidenceId = "02-front" },
				},
			}
		end):toThrow()
		expect(function()
			Generate.evidenceBracket {
				id = "fixture.bracket",
				poses = {
					{ id = "front", evidenceId = "01-front" },
					{ id = "side", evidenceId = "front" },
				},
			}
		end):toThrow()
	end)
end)

describe("delivery destination and publication records", function()
	local FIXTURE_DESTINATION: Generate.Destination = {
		adapter = "fixture-host",
		descriptor = { owner = { kind = "team", id = "42" }, kindName = "Image" },
	}

	local function destinationBrief(destination: unknown, hostVerification: unknown): Generate.Brief
		return Generate.brief {
			id = "fixture.icon.v1",
			kind = "image",
			intent = { role = "fixture icon" },
			review = { rubric = "icon", rubricFingerprint = "rubric-icon-v1", views = { "canonical" } },
			delivery = {
				semanticId = "fixture.icon",
				target = "fixture-host",
				destination = destination :: Generate.Destination?,
				hostVerification = hostVerification :: boolean?,
			},
		}
	end

	local function receiptOf(status: Generate.ReceiptStatus?): Generate.Receipt
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
		local receipt = Generate.execute(value, plan, Host.fake.create(), AUTHORITY)
		if status == nil then
			return receipt
		end
		local forced = table.clone(receipt)
		forced.status = status
		forced.fingerprint = Generate.receiptFingerprint(forced)
		return forced
	end

	local REMOVE: unknown = {}

	local function record(overrides: { [string]: unknown }): Generate.PublicationRecord
		local base: { [string]: unknown } = {
			schemaVersion = 1,
			disposition = "unaccepted",
			state = "stopped",
			detail = "the run resolved produced, not accepted",
			dryRun = false,
			quarantined = true,
			placeholder = false,
			credential = { name = "FIXTURE_PUBLISH_KEY", exposed = false },
			attemptsAuthorised = 1,
			attemptsMade = 0,
			attempts = {},
			compensations = {},
			stages = { { id = "acceptance", status = "refused", detail = "produced" } },
			facts = {},
		}
		for key, value in overrides do
			base[key] = if value == REMOVE then nil else value
		end
		return (base :: unknown) :: Generate.PublicationRecord
	end

	it("declares a destination as opaque adapter data and host verification as a flag", function()
		local plain = destinationBrief(nil, nil)
		expect(plain.delivery.destination):toEqual(nil)
		expect(plain.delivery.hostVerification):toEqual(nil)
		local declared = destinationBrief(FIXTURE_DESTINATION, nil)
		expect(declared.delivery.destination):toEqual(FIXTURE_DESTINATION)
		expect(declared.delivery.hostVerification):toEqual(false)
		expect(Generate.briefFingerprint(declared)).never:toEqual(Generate.briefFingerprint(plain))
		local verified = destinationBrief(FIXTURE_DESTINATION, true)
		expect(verified.delivery.hostVerification):toEqual(true)
		expect(Generate.briefFingerprint(verified)).never:toEqual(Generate.briefFingerprint(declared))
		expect(function()
			destinationBrief(nil, true)
		end):toThrow "requires delivery.destination"
		expect(function()
			destinationBrief(FIXTURE_DESTINATION, "yes")
		end):toThrow "must be a boolean"
		expect(function()
			destinationBrief("fixture-host", nil)
		end):toThrow "must be a table"
		expect(function()
			destinationBrief({ adapter = "Fixture Host", descriptor = {} }, nil)
		end):toThrow "adapter"
		expect(function()
			destinationBrief({ adapter = "fixture-host" }, nil)
		end):toThrow "descriptor"
		expect(function()
			destinationBrief({ adapter = "fixture-host", descriptor = {}, extra = true }, nil)
		end):toThrow "unknown field"
		expect(function()
			destinationBrief({ adapter = "fixture-host", descriptor = { apiKey = "smuggled" } }, nil)
		end):toThrow "secret-shaped"
	end)

	it("attaches one publication record to an unchanged receipt and re-fingerprints it", function()
		local receipt = receiptOf()
		local value = record {}
		local attached = Generate.attachPublication(receipt, value)
		expect(attached.publication):toEqual(value)
		expect(attached.fingerprint):toEqual(Generate.receiptFingerprint(attached))
		expect(attached.fingerprint).never:toEqual(receipt.fingerprint)
		expect(receipt.publication):toEqual(nil)
		expect(function()
			Generate.attachPublication(attached, value)
		end):toThrow "already records"

		local changed = table.clone(receipt)
		changed.limitations = { "edited" }
		expect(function()
			Generate.attachPublication(changed, value)
		end):toThrow "unchanged receipt"

		expect(function()
			Generate.attachPublication(
				receipt,
				record { credential = { name = "FIXTURE_PUBLISH_KEY", exposed = true } }
			)
		end):toThrow "no credential value was exposed"
		expect(function()
			Generate.attachPublication(receipt, record { quarantined = false })
		end):toThrow "quarantined"
		expect(function()
			Generate.attachPublication(receipt, record { placeholder = REMOVE })
		end):toThrow "placeholder"
		expect(function()
			Generate.attachPublication(receipt, record { state = REMOVE })
		end):toThrow "pending, confirmed, reconciled or stopped"
		expect(function()
			Generate.attachPublication(receipt, record { state = "terminal" })
		end):toThrow "pending, confirmed, reconciled or stopped"
		expect(function()
			Generate.attachPublication(receipt, record { facts = REMOVE })
		end):toThrow "adapter facts"
		expect(function()
			Generate.attachPublication(receipt, record { artifactDigest = "ABC" })
		end):toThrow "artifact digest"
		expect(function()
			Generate.attachPublication(receipt, record { attemptsMade = 2 })
		end):toThrow "attempts made"
		expect(function()
			Generate.attachPublication(receipt, record { readback = { apiKey = "leak" } })
		end):toThrow "secret-shaped"
		expect(function()
			Generate.attachPublication(receipt, record { facts = { token = "leak" } })
		end):toThrow "secret-shaped"
		expect(Generate.publicationFault(record {})):toEqual(nil)
		expect(Generate.publicationFault(record { disposition = "" })):toEqual "publication record must name one disposition"

		local rehearsed = Generate.attachPublication(receipt, record { disposition = "dry-run", dryRun = true })
		local final = Generate.attachPublication(rehearsed, value)
		expect((final.publication :: Generate.PublicationRecord).dryRun):toEqual(false)
	end)

	it("confirms a pending publication record, and refuses a settled one", function()
		local receipt = receiptOf()
		local pending = record {
			disposition = "moderation-pending",
			state = "pending",
			detail = "content 999000111 remains in review",
			contentId = "999000111",
			attemptsMade = 1,
			stages = { { id = "spend", status = "refused", detail = "moderation-pending" } },
		}
		local attached = Generate.attachPublication(receipt, pending)
		expect(function()
			Generate.confirmPublication(receipt, pending)
		end):toThrow "pending or reconciled"
		local confirmed = Generate.confirmPublication(
			attached,
			record {
				disposition = "published",
				state = "confirmed",
				detail = pending.detail,
				contentId = "999000111",
				version = "1",
				attemptsMade = 1,
				stages = pending.stages,
			}
		)
		expect((confirmed.publication :: Generate.PublicationRecord).state):toEqual "confirmed"
		expect(confirmed.fingerprint):toEqual(Generate.receiptFingerprint(confirmed))
		expect(confirmed.fingerprint).never:toEqual(attached.fingerprint)
		expect(function()
			Generate.confirmPublication(confirmed, pending)
		end):toThrow "pending or reconciled"
		expect(function()
			Generate.confirmPublication(Generate.attachPublication(receipt, record {}), pending)
		end):toThrow "pending or reconciled"
	end)

	it("reconciles only a stopped failed-readback create with a failed compensation", function()
		local receipt = receiptOf()
		local failedAttempt: Generate.PublicationAttempt = {
			ordinal = 1,
			stageId = "spend",
			grantId = "grant-1",
			grantFingerprint = "grant-fp",
			action = "create",
			semanticId = "fixture.icon",
			state = "failed-readback",
		}
		local stopped = record {
			disposition = "failed-compensation",
			state = "stopped",
			attemptsMade = 1,
			attempts = { failedAttempt },
			compensations = {
				{ ordinal = 1, stageId = "spend", rollbackToken = "token-1", status = "failed", detail = "denied" },
			},
		}
		local attached = Generate.attachPublication(receipt, stopped)
		local function reconciled(overrides: { [string]: unknown }): Generate.PublicationRecord
			local base: { [string]: unknown } = {
				disposition = "access-pending",
				state = "reconciled",
				attemptsMade = 1,
				attempts = stopped.attempts,
				compensations = stopped.compensations,
				version = "3",
				readback = { creator = "fixture" },
				reconciliation = {
					sourceReceiptFingerprint = attached.fingerprint,
					evidencePath = "evidence/readback.json",
					evidenceDigest = string.rep("e", 64),
				},
			}
			for key, value in overrides do
				base[key] = value
			end
			return record(base)
		end
		local settled = Generate.reconcilePublication(attached, reconciled {})
		expect((settled.publication :: Generate.PublicationRecord).state):toEqual "reconciled"
		local finished = Generate.confirmPublication(
			settled,
			record {
				disposition = "published",
				state = "confirmed",
				attemptsMade = 1,
				attempts = stopped.attempts,
				compensations = stopped.compensations,
				version = "3",
				readback = { creator = "fixture" },
				reconciliation = (settled.publication :: Generate.PublicationRecord).reconciliation,
			}
		)
		expect((finished.publication :: Generate.PublicationRecord).state):toEqual "confirmed"

		expect(function()
			Generate.reconcilePublication(receipt, reconciled {})
		end):toThrow "stopped publication record"
		expect(function()
			Generate.reconcilePublication(attached, reconciled { state = "pending" })
		end):toThrow "bound to the original receipt"
		expect(function()
			Generate.reconcilePublication(
				attached,
				reconciled {
					reconciliation = {
						sourceReceiptFingerprint = "other",
						evidencePath = "evidence/readback.json",
						evidenceDigest = string.rep("e", 64),
					},
				}
			)
		end):toThrow "bound to the original receipt"
		expect(function()
			Generate.reconcilePublication(attached, reconciled { attempts = {}, attemptsMade = 0 })
		end):toThrow "preserve the original attempts"
		expect(function()
			Generate.reconcilePublication(attached, reconciled { version = REMOVE })
		end):toThrow "bound to the original receipt"
		local plain = Generate.attachPublication(receipt, record {})
		expect(function()
			Generate.reconcilePublication(
				plain,
				reconciled {
					reconciliation = {
						sourceReceiptFingerprint = plain.fingerprint,
						evidencePath = "evidence/readback.json",
						evidenceDigest = string.rep("e", 64),
					},
				}
			)
		end):toThrow "failed-readback create"
		expect(function()
			Generate.attachPublication(receipt, reconciled { reconciliation = REMOVE })
		end):toThrow "reconciliation evidence"
	end)

	local function sourceFingerprint(receipt: Generate.Receipt): string
		local source = table.clone(receipt)
		source.publication = nil
		return Generate.receiptFingerprint(source)
	end

	local function request(source: Generate.Receipt, hostBuild: string): Generate.HostVerificationRequest
		local payload: Generate.HostVerificationRequestPayload = {
			schemaVersion = 1,
			receiptId = source.id,
			sourceReceiptFingerprint = sourceFingerprint(source),
			briefFingerprint = source.briefFingerprint,
			artifactId = "candidate",
			artifactDigest = CANDIDATE_DIGEST,
			contentId = "999000111",
			version = "1",
			grantId = "grant-1",
			grantFingerprint = "grant-fp",
			writeAheadDigest = SECOND_DIGEST,
			stateFingerprint = "state-1",
			host = "fixture-host 1.0",
			hostBuild = hostBuild,
			windowSeconds = 5,
			binding = { scope = "fixture" },
		}
		local result = table.clone(payload) :: Generate.HostVerificationRequest
		result.fingerprint = Generate.fingerprint(payload)
		return result
	end

	local function verification(hostBuild: string, disposition: ("verified" | "refused")?): Generate.HostVerification
		local refused = disposition == "refused"
		return {
			schemaVersion = 1,
			requested = true,
			disposition = disposition or "verified",
			refusalReason = if refused then "load_failed" else nil,
			detail = if refused then "the host did not load the content" else nil,
			contentId = "999000111",
			hostBuild = hostBuild,
			windowSeconds = 5,
			measurements = { loaded = true },
			diagnostics = {},
			captureRef = "frame://999000111",
			observationFingerprint = if refused then nil else string.rep("f", 32),
		}
	end

	local function published(overrides: { [string]: unknown }): Generate.PublicationRecord
		local base: { [string]: unknown } = {
			disposition = "published",
			state = "confirmed",
			detail = nil,
			contentId = "999000111",
			attemptsMade = 1,
			stages = { { id = "host-verification", status = "not-run", detail = "the brief does not request it" } },
		}
		for key, value in overrides do
			base[key] = value
		end
		return record(base)
	end

	it("reports host verification only for an exact accepted confirmed record", function()
		local receipt = receiptOf "accepted"
		local base = published {}
		local unverified = Generate.attachPublication(receipt, base)
		expect(Generate.hostVerified(unverified)):toEqual(false)
		expect(Generate.hostVerified(({ publication = nil } :: unknown) :: Generate.Receipt)):toEqual(false)

		local verified = published { verification = verification "build-1" }
		local attached = Generate.attachPublication(receipt, verified)
		expect(Generate.hostVerified(attached)):toEqual(true)

		for _, other in { receiptOf "produced", receiptOf "rejected", receiptOf "failed" } do
			expect(Generate.hostVerified(Generate.attachPublication(other, verified))):toEqual(false)
		end

		local tampered = Generate.attachPublication(receipt, verified)
		local observation = (tampered.publication :: Generate.PublicationRecord).verification :: Generate.HostVerification
		observation.observationFingerprint = "changed-observation"
		expect(Generate.hostVerified(tampered)):toEqual(false)

		local changedHost = table.clone(attached)
		changedHost.host = "changed-host"
		expect(Generate.hostVerified(changedHost)):toEqual(false)
		local changedContent = table.clone(attached)
		changedContent.publication = published { verification = verification "build-1", contentId = "999000112" }
		expect(Generate.hostVerified(changedContent)):toEqual(false)

		for _, state in { "pending", "stopped" } do
			expect(
				Generate.hostVerified(
					Generate.attachPublication(
						receipt,
						published { verification = verification "build-1", state = state }
					)
				)
			):toEqual(false)
		end
		for _, field in { "dryRun", "placeholder" } do
			expect(
				Generate.hostVerified(
					Generate.attachPublication(
						receipt,
						published { verification = verification "build-1", [field] = true }
					)
				)
			):toEqual(false)
		end
		expect(
			Generate.hostVerified(
				Generate.attachPublication(
					receipt,
					published { verification = verification "build-1", contentId = REMOVE }
				)
			)
		):toEqual(false)
		expect(
			Generate.hostVerified(
				Generate.attachPublication(
					receipt,
					published { verification = verification "build-1", contentId = "999000112" }
				)
			)
		):toEqual(false)

		local refused =
			Generate.attachPublication(receipt, published { verification = verification("build-1", "refused") })
		expect(Generate.hostVerified(refused)):toEqual(false)
		local unnamed = verification("build-1", "refused")
		unnamed.refusalReason = nil
		expect(function()
			Generate.attachPublication(receipt, published { verification = unnamed })
		end):toThrow "refusal reason"
		local unfingerprinted = verification "build-1"
		unfingerprinted.observationFingerprint = nil
		expect(function()
			Generate.attachPublication(receipt, published { verification = unfingerprinted })
		end):toThrow "observation fingerprint"
		local unbuilt = verification "build-1"
		unbuilt.hostBuild = ""
		expect(function()
			Generate.attachPublication(receipt, published { verification = unbuilt })
		end):toThrow "host build"
		local unwindowed = verification "build-1"
		unwindowed.windowSeconds = 0
		expect(function()
			Generate.attachPublication(receipt, published { verification = unwindowed })
		end):toThrow "observation window"
		local undiagnosed = (verification "build-1" :: unknown) :: { [string]: unknown }
		undiagnosed.diagnostics = nil
		expect(function()
			Generate.attachPublication(receipt, published { verification = undiagnosed })
		end):toThrow "diagnostics"
	end)

	it("completes and rebinds a deferred host verification request", function()
		local receipt = receiptOf "accepted"
		local deferred = request(receipt, "build-1")
		local pendingRecord = record {
			disposition = "verification-pending",
			state = "pending",
			contentId = "999000111",
			version = "1",
			artifactId = "candidate",
			artifactDigest = CANDIDATE_DIGEST,
			grantId = "grant-1",
			grantFingerprint = "grant-fp",
			writeAheadDigest = SECOND_DIGEST,
			attemptsMade = 1,
			verificationRequest = deferred,
		}
		local pending = Generate.attachPublication(receipt, pendingRecord)
		expect(Generate.hostVerified(pending)):toEqual(false)

		local function completion(requestValue: Generate.HostVerificationRequest): Generate.HostVerificationCompletion
			return {
				requestFingerprint = requestValue.fingerprint,
				pendingReceiptFingerprint = pending.fingerprint,
				evidencePath = "evidence/verification.json",
				evidenceDigest = string.rep("d", 64),
				stateFingerprint = "state-1",
			}
		end
		local function completed(build: string, disposition: ("verified" | "refused")?): Generate.PublicationRecord
			local observed = verification(build, disposition)
			local stages = table.clone(pendingRecord.stages)
			table.insert(stages, {
				id = "complete-host-verification",
				status = if observed.disposition == "verified" then "passed" else "refused",
				detail = observed.detail,
			})
			return record {
				disposition = "published",
				state = "confirmed",
				detail = if observed.detail == nil then REMOVE else observed.detail,
				contentId = "999000111",
				version = "1",
				artifactId = "candidate",
				artifactDigest = CANDIDATE_DIGEST,
				grantId = "grant-1",
				grantFingerprint = "grant-fp",
				writeAheadDigest = SECOND_DIGEST,
				attemptsMade = 1,
				stages = stages,
				verificationRequest = deferred,
				verification = observed,
				verificationCompletion = completion(deferred),
			}
		end
		local done = Generate.confirmPublication(pending, completed "build-1")
		expect(Generate.hostVerified(done)):toEqual(true)
		expect(Generate.hostVerified(Generate.confirmPublication(pending, completed("build-1", "refused")))):toEqual(
			false
		)
		expect(function()
			Generate.confirmPublication(pending, completed "build-2")
		end):toThrow "host build of its request"
		local missing = completed "build-1"
		missing.verificationCompletion = nil
		expect(function()
			Generate.confirmPublication(pending, missing)
		end):toThrow "bound to the pending verification request"

		local rebound = request(receipt, "build-2")
		local rebinding = table.clone(pendingRecord)
		rebinding.verificationRequest = rebound
		rebinding.verificationRebindings = {
			{
				receiptFingerprint = pending.fingerprint,
				requestFingerprint = deferred.fingerprint,
				hostBuild = "build-1",
			},
		}
		local reboundReceipt = Generate.confirmPublication(pending, rebinding)
		expect((reboundReceipt.publication :: Generate.PublicationRecord).verificationRequest):toEqual(rebound)
		expect(function()
			Generate.confirmPublication(pending, pendingRecord)
		end):toThrow "bound to the pending verification request"
		local same = table.clone(rebinding)
		same.verificationRequest = deferred
		expect(function()
			Generate.confirmPublication(pending, same)
		end):toThrow "different build"
		local forged = table.clone(rebinding)
		forged.detail = "forged"
		expect(function()
			Generate.confirmPublication(pending, forged)
		end):toThrow "protected request field"

		local tamperedRequest = table.clone(deferred)
		tamperedRequest.windowSeconds = 9
		expect(function()
			Generate.attachPublication(receipt, record { verificationRequest = tamperedRequest })
		end):toThrow "fingerprint changed"
		local foreign = table.clone(pendingRecord)
		foreign.contentId = "999000112"
		expect(function()
			Generate.attachPublication(receipt, foreign)
		end):toThrow "exact publication identity"
	end)
end)

describe("Generate candidate revision bookkeeping", function()
	local function ledgerOf(outcomes: { Generate.RevisionOutcome }): Generate.RevisionLedger
		local entries: { Generate.RevisionEntryDraft } = {}
		for index, outcome in outcomes do
			local draft: Generate.RevisionEntryDraft = {
				revision = index,
				producer = "fixture-author",
				outcome = outcome :: Generate.RevisionOutcome,
			}
			table.insert(entries, draft)
		end
		return Generate.revisionLedger("fixture.wall.candidate", entries)
	end

	it("reads the next revision from a resolved review instead of a pinned constant", function()
		local value = brief()
		local plan = Generate.plan(value, REVIEW_STAGES)
		local packet = bind(
			value,
			plan,
			"review",
			packetDraft(6, "candidate", CANDIDATE_DIGEST, "front-view", EVIDENCE_DIGEST, "producer")
		)
		local rejected = Generate.resolveReview(packet, value.review, {
			Generate.reviewDecision(reviewDraft(packet, "reviewer-a", { verdict = "rejected" })),
		}, { stale = false })
		expect(rejected.disposition):toEqual "rejected"
		local entry = Revision.entryFor(rejected)
		expect(entry.revision):toEqual(6)
		expect(entry.outcome):toEqual "rejected"
		expect(entry.packetId):toEqual(packet.id)

		local history: { Generate.RevisionEntryDraft } = {}
		for revision = 1, 5 do
			table.insert(history, { revision = revision, producer = "fixture-author", outcome = "rejected" })
		end
		table.insert(history, entry)
		local current = Generate.revisionLedger("fixture.wall.candidate", history)
		expect(current.head.revision):toEqual(6)
		expect(current.settled):toEqual(false)
		expect(current.nextRevision):toEqual(7)

		local rolled = Generate.rollCandidate(current, {
			producer = "fixture-author",
			artifacts = { { id = "candidate", digest = SECOND_DIGEST, digestAlgorithm = "sha256" } },
		})
		expect(rolled.candidateId):toEqual "fixture.wall.candidate"
		expect(rolled.revision):toEqual(7)
		expect(rolled.artifacts[1].digest):toEqual(SECOND_DIGEST)

		local next_ = bind(value, plan, "review", {
			id = "fixture.packet.7",
			candidate = rolled,
			evidence = {
				{
					id = "front-view",
					digest = EVIDENCE_DIGEST,
					digestAlgorithm = "sha256",
					view = "front",
					role = "canonical-view",
				},
			},
			rubric = RUBRIC,
			requestedViews = { "front", "corner" },
			captureEnvironment = { renderer = "fixture", colorSpace = "srgb" },
		})
		expect(next_.candidate.revision):toEqual(7)
		expect(next_.candidate.fingerprint).never:toEqual(packet.candidate.fingerprint)
	end)

	it("maps every review disposition and refuses a ledger or roll that loses the ordering", function()
		expect(ledgerOf({ "rejected", "unresolved", "stale" }).nextRevision):toEqual(4)
		expect(ledgerOf({ "rejected", "approved" }).settled):toEqual(true)
		expect(ledgerOf({ "rejected", "approved" }).nextRevision):toEqual(3)
		expect(ledgerOf({ "open" }).nextRevision):toEqual(nil)

		expect(function()
			Generate.revisionLedger("fixture.wall.candidate", {})
		end):toThrow "at least the first revision"

		expect(function()
			Generate.revisionLedger("fixture.wall.candidate", {
				{ revision = 2, producer = "fixture-author", outcome = "rejected" },
			})
		end):toThrow "revisions start at 1"

		expect(function()
			Generate.revisionLedger("fixture.wall.candidate", {
				{ revision = 1, producer = "fixture-author", outcome = "open" },
				{ revision = 2, producer = "fixture-author", outcome = "rejected" },
			})
		end):toThrow "only the head may be open"

		expect(function()
			Generate.revisionLedger("fixture.wall.candidate", {
				{
					revision = 1,
					producer = "fixture-author",
					outcome = ("withdrawn" :: unknown) :: Generate.RevisionOutcome,
				},
			})
		end):toThrow "outcome must be open"

		expect(function()
			Generate.rollCandidate(ledgerOf { "approved" }, {
				producer = "fixture-author",
				artifacts = { { id = "candidate", digest = SECOND_DIGEST, digestAlgorithm = "sha256" } },
			})
		end):toThrow "must declare supersede"
		expect(Generate.rollCandidate(ledgerOf { "approved" }, {
			producer = "fixture-author",
			artifacts = { { id = "candidate", digest = SECOND_DIGEST, digestAlgorithm = "sha256" } },
			supersede = true,
		}).revision):toEqual(2)

		expect(function()
			Generate.rollCandidate(ledgerOf { "open" }, {
				producer = "fixture-author",
				artifacts = { { id = "candidate", digest = SECOND_DIGEST, digestAlgorithm = "sha256" } },
			})
		end):toThrow "rolls only after its review resolves"

		expect(function()
			Generate.rollCandidate(ledgerOf { "rejected" }, { producer = "fixture-author", artifacts = {} })
		end):toThrow "at least one candidate artifact digest"

		expect(function()
			Generate.rollCandidate(ledgerOf { "rejected" }, {
				producer = "fixture-author",
				artifacts = {
					{ id = "candidate", digest = SECOND_DIGEST, digestAlgorithm = "sha256" },
					{ id = "candidate", digest = CANDIDATE_DIGEST, digestAlgorithm = "sha256" },
				},
			})
		end):toThrow "repeat"

		expect(function()
			Generate.rollCandidate(ledgerOf { "rejected" }, {
				producer = "fixture-author",
				artifacts = { { id = "candidate", digest = "short", digestAlgorithm = "sha256" } },
			})
		end):toThrow "lowercase SHA-256 digest"

		expect(function()
			Revision.outcomeFor(({ disposition = "invented" } :: unknown) :: Generate.ResolvedReview)
		end):toThrow "review disposition"
	end)
end)

describe("Generate economics", function()
	it("round-trips a stage's declared economics on the receipt", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = {
					make = {
						status = "returned",
						output = {
							economics = {
								attemptCount = 1,
								providerCalls = {
									{ provider = "acme", kind = "image", count = 2, costMicros = 500 },
								},
							},
						},
					},
				},
			},
			AUTHORITY
		)
		local economics = receipt.stages[1].economics :: Generate.StageEconomics
		local providerCalls = economics.providerCalls :: { Generate.ProviderCallEconomics }
		expect(economics.attemptCount):toEqual(1)
		expect(providerCalls[1].count):toEqual(2)
		expect(providerCalls[1].costMicros):toEqual(500)
		expect(economics.wallSeconds):toEqual(0.001)
		expect(receipt.fingerprint):toEqual(Generate.receiptFingerprint(receipt))
	end)

	it("fills wall seconds even when a host declares no economics", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
		local receipt = Generate.execute(value, plan, Host.fake.create(), AUTHORITY)
		local economics = receipt.stages[1].economics :: Generate.StageEconomics
		expect(economics.wallSeconds):toEqual(0.001)
		expect(economics.attemptCount):toBeNil()
	end)

	it("refuses a declared economics value that is negative or fractional", function()
		local value = brief()
		local plan = Generate.plan(value, { { id = "make", operation = "generate" } })
		local receipt = Generate.execute(
			value,
			plan,
			Host.fake.create {
				outcomes = {
					make = { status = "returned", output = { economics = { attemptCount = -1 } } },
				},
			},
			AUTHORITY
		)
		expect(receipt.status):toEqual "failed"
		expect(receipt.stages[1].detail):toContain "invalid economics"
	end)
end)

return nil
