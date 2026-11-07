--!strict

local Test = require "./harness"

local describe, it, expect = Test.describe, Test.it, Test.expect
local protected = Test.protectedCall

local Canonical = require "../src/core/canonical"
local Types = require "../src/core/types"
local Generate = require "../src/core"
local Destination = require "../src/core/destination"
local Revision = require "../src/core/revision"

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

local KNOWN_RIGHTS: Types.RightsFactsDraft = {
	source = { state = "known", value = "fixture:first-party" },
	license = { state = "known", value = "fixture:reserved" },
	owner = { state = "known", value = "fixture:studio" },
	consent = { state = "known", value = "fixture:not-applicable" },
}

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

local REVIEW_STAGES: { Generate.StageDraft } = {
	{ id = "candidate", operation = "generate" },
	{ id = "capture", operation = "verify", dependsOn = { "candidate" } },
	{ id = "review", operation = "review", dependsOn = { "capture" } },
}

describe("Generate briefs and plans", function()
	it("preserves structured brief metadata and binds it to the fingerprint", function()
		local draft: Generate.BriefDraft = {
			id = "fixture.metadata",
			kind = "image",
			intent = { role = "metadata contract" },
			review = { rubric = RUBRIC.id, rubricFingerprint = RUBRIC.fingerprint, views = { "front" } },
			delivery = { semanticId = "fixture.metadata", target = "fixture-host" },
			metadata = { retained = { path = "source.png", dimensions = { 32, 64 }, inspected = false } },
		}
		local value = Generate.brief(draft)
		expect(value.metadata):toEqual(draft.metadata)
		local changed = table.clone(value)
		changed.metadata = { retained = { path = "source.png", dimensions = { 64, 64 }, inspected = false } }
		expect(Generate.briefFingerprint(value) == Generate.briefFingerprint(changed)):toEqual(false)
		draft.metadata = { retained = { measure = math.huge } }
		expect(function()
			Generate.brief(draft)
		end):toThrow "non-finite"
		draft.metadata = { retained = { read = function() end } }
		expect(function()
			Generate.brief(draft)
		end):toThrow "executable"
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
		local invalid = brief()
		local ok, why = protected(Generate.brief, {
			id = invalid.id,
			kind = invalid.kind,
			intent = invalid.intent,
			delivery = invalid.delivery,
			review = {
				rubric = RUBRIC.id,
				rubricFingerprint = RUBRIC.fingerprint,
				views = { "front" },
				independence = "unknown",
			},
		})
		expect(ok):toEqual(false)
		expect(tostring(why)):toContain "independence"
	end)

	it("produces the same plan fingerprint from the same declared data", function()
		local value = brief()
		local stages: { Generate.StageDraft } = {
			{ id = "make", operation = "generate", requires = { "generate" } },
			{ id = "review", operation = "review", dependsOn = { "make" }, requires = {} },
		}
		expect(Generate.plan(value, stages).fingerprint):toEqual(Generate.plan(value, stages).fingerprint)
	end)

	it("sorts copied requirements and keeps stage drafts independent", function()
		local requirements = { "transform", "generate" }
		local parameters = { shape = "wall" }
		local plan = Generate.plan(brief(), {
			{ id = "make", operation = "generate", requires = requirements, parameters = parameters },
		})
		expect(plan.stages[1].requires):toEqual { "generate", "transform" }
		expect(requirements):toEqual { "transform", "generate" }
		plan.stages[1].requires[1] = "verify"
		plan.stages[1].parameters.shape = "tower"
		expect(requirements):toEqual { "transform", "generate" }
		expect(parameters.shape):toEqual "wall"
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

	it("copies typed plain records without sharing nested mutable state", function()
		local original = { nested = { value = 1 }, labels = { "first", "second" } }
		local copied = Canonical.copy(original)
		copied.nested.value = 2
		copied.labels[1] = "changed"
		expect(original.nested.value):toBe(1)
		expect(original.labels[1]):toBe "first"
		expect(copied.nested.value):toBe(2)
		expect(function()
			Canonical.copy(setmetatable({}, {
				__index = function()
					error "executable metadata"
				end,
			}))
		end):toThrow "plain tables"
	end)

	it("refuses non-string publication descriptor and constraint keys", function()
		expect(function()
			Destination.normalize({ adapter = "fixture", descriptor = { "unnamed" } }, false)
		end):toThrow "descriptor requires string keys"
		expect(function()
			Generate.brief {
				id = "fixture.constraints",
				kind = "image",
				intent = { role = "fixture" },
				constraints = { "unnamed" },
				review = { rubric = "fixture", rubricFingerprint = "fixture", views = { "front" } },
				delivery = { semanticId = "fixture", target = "local" },
			}
		end):toThrow "constraints require string keys"
	end)

	it("rejects cyclic and non-finite canonical state", function()
		local cyclic: { [string]: unknown } = {}
		cyclic.self = cyclic
		expect(function()
			Canonical.copy(cyclic)
		end):toThrow "cycles"
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
		local ok, why = protected(Generate.resolveReview, packet, {
			rubric = value.review.rubric,
			views = value.review.views,
			blindness = value.review.blindness,
			independence = "unknown",
		}, {})
		expect(ok):toEqual(false)
		expect(tostring(why)):toContain "declared independence"
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

describe("review contract fields", function()
	it("refuses an unknown acceptance field", function()
		expect(function()
			Generate.brief {
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
			}
		end):toThrow "review carries unknown field secondaryAcceptance"
	end)
end)

describe("Generate structured provenance", function()
	it("records parents, invocation facts, attempt ordinal, and disposition", function()
		local derivation = Generate.derivation {
			artifactId = "derived",
			artifactDigest = SECOND_DIGEST,
			origin = "derived",
			parents = {
				{ artifactId = "candidate", artifactDigest = CANDIDATE_DIGEST },
				{ receiptId = "earlier/receipt", jobId = "earlier/job", briefFingerprint = "gen-fp2-earlier" },
			},
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
				origin = "derived",
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
			origin = "imported",
			parents = { { receiptId = "legacy/import-ledger" } },
		}
		local child = Generate.derivation {
			artifactId = "derived",
			artifactDigest = SECOND_DIGEST,
			origin = "derived",
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

describe("delivery destinations", function()
	local FIXTURE_DESTINATION: Generate.Destination = {
		adapter = "fixture-host",
		descriptor = { owner = { kind = "team", id = "42" }, kindName = "Image" },
	}

	local function destinationBrief(destination: unknown, hostVerification: unknown): Generate.Brief
		local normalized, verification = Destination.normalize(destination, hostVerification)
		return Generate.brief {
			id = "fixture.icon.v1",
			kind = "image",
			intent = { role = "fixture icon" },
			review = { rubric = "icon", rubricFingerprint = "rubric-icon-v1", views = { "canonical" } },
			delivery = {
				semanticId = "fixture.icon",
				target = "fixture-host",
				destination = normalized,
				hostVerification = verification,
			},
		}
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
end)

describe("Generate candidate revision bookkeeping", function()
	local function ledgerOf(outcomes: { Generate.RevisionOutcome }): Generate.RevisionLedger
		local entries: { Generate.RevisionEntryDraft } = {}
		for index, outcome in outcomes do
			local draft: Generate.RevisionEntryDraft = {
				revision = index,
				producer = "fixture-author",
				outcome = outcome,
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
			local item: Generate.RevisionEntryDraft =
				{ revision = revision, producer = "fixture-author", outcome = "rejected" }
			table.insert(history, item)
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

		local ok, why = protected(Generate.revisionLedger, "fixture.wall.candidate", {
			{ revision = 1, producer = "fixture-author", outcome = "withdrawn" },
		})
		expect(ok):toEqual(false)
		expect(tostring(why)):toContain "outcome must be open"

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

		local resolved, refusal = protected(Revision.outcomeFor, { disposition = "invented" })
		expect(resolved):toEqual(false)
		expect(tostring(refusal)):toContain "review disposition"
	end)
end)

return nil
