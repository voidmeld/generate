--!strict

local Generate = require "../src/core"

local CANDIDATE = "example.wall.candidate"
local FIRST_DIGEST = string.rep("a", 64)
local SECOND_DIGEST = string.rep("b", 64)

local history = Generate.revisionLedger(CANDIDATE, {
	{ revision = 1, producer = "example-author", outcome = "rejected", packetId = "example.wall.v1/packet" },
	{ revision = 2, producer = "example-author", outcome = "unresolved", packetId = "example.wall.v2/packet" },
})

local rolled = Generate.rollCandidate(history, {
	producer = "example-author",
	artifacts = { { id = "wall", digest = SECOND_DIGEST, digestAlgorithm = "sha256" } },
})

local settled = Generate.revisionLedger(CANDIDATE, {
	{ revision = 1, producer = "example-author", outcome = "rejected" },
	{ revision = 2, producer = "example-author", outcome = "unresolved" },
	{ revision = 3, producer = "example-author", outcome = "approved" },
})

local reroll: Generate.RevisionRollDraft = {
	producer = "example-author",
	artifacts = { { id = "wall", digest = FIRST_DIGEST, digestAlgorithm = "sha256" } },
}
local superseding: Generate.RevisionRollDraft = {
	producer = "example-author",
	artifacts = { { id = "wall", digest = FIRST_DIGEST, digestAlgorithm = "sha256" } },
	supersede = true,
}
local refused = select(2, pcall(Generate.rollCandidate, settled, reroll))

print(history.head.outcome)
print(tostring(history.nextRevision))
print(rolled.candidateId .. " revision " .. tostring(rolled.revision))
print(tostring(settled.settled))
print(tostring(refused))
print("supersede to revision " .. tostring(Generate.rollCandidate(settled, superseding).revision))

return {
	history = history,
	rolled = rolled,
	settled = settled,
}
