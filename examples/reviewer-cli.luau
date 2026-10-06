--!strict

local json = require "@std/json"

local Agent = require "../src/agent"

local ENVIRONMENT: { [string]: string } = { REVIEWER_CLI = "/usr/local/bin/reviewer" }
local INSTALLED: { [string]: boolean } = { ["/usr/local/bin/reviewer"] = true }

local function readEnv(name: string): string?
	return ENVIRONMENT[name]
end

local function exists(path: string): boolean
	return INSTALLED[path] == true
end

local fromEnvironment = Agent.reviewerCli.resolve {
	executable = "reviewer",
	environmentVariable = "REVIEWER_CLI",
	readEnv = readEnv,
	exists = exists,
	arguments = { "exec", "--json" },
}

local fromConfiguration = Agent.reviewerCli.resolve {
	executable = "reviewer",
	configuredPath = "/usr/local/bin/reviewer",
	environmentVariable = "REVIEWER_CLI",
	readEnv = readEnv,
	exists = exists,
}

local unresolved = Agent.reviewerCli.resolve {
	executable = "reviewer",
	environmentVariable = "REVIEWER_CLI",
	readEnv = function(): string?
		return nil
	end,
	exists = exists,
}

print(if fromEnvironment.ok then (fromEnvironment :: Agent.ReviewerCliResolved).origin else "unresolved")
print(if fromConfiguration.ok then (fromConfiguration :: Agent.ReviewerCliResolved).origin else "unresolved")
print(if unresolved.ok then "resolved" else (unresolved :: Agent.ReviewerCliRefused).refusal)

local CONTRACT: Agent.ReviewerStreamContract = {
	threadEventType = "thread.started",
	threadIdField = "thread_id",
	answerEventType = "item.completed",
	answerItemType = "agent_message",
	actorPrefix = "reviewer:",
}

local function stream(threadId: string, verdict: string, reason: string): string
	return table.concat({
		json.serialize { type = "thread.started", thread_id = threadId },
		json.serialize {
			type = "item.completed",
			item = {
				type = "agent_message",
				text = json.serialize { verdict = verdict, certainty = "high", reasons = { reason } },
			},
		},
	}, "\n") .. "\n"
end

local decisions, refusal = Agent.reviewerStream.decisions {
	decode = function(text: string): unknown
		return json.deserialize(text)
	end,
	contract = CONTRACT,
	packet = {
		id = "example.packet",
		fingerprint = "gen-fp2-packet",
		candidateFingerprint = "gen-fp2-candidate",
		evidenceFingerprint = "gen-fp2-evidence",
		rubric = { id = "example", fingerprint = "rubric-example-v1" },
	},
	streams = {
		stream("thread-a", "approved", "the delivered content clears the rubric"),
	},
	role = "reviewer",
}
assert(decisions ~= nil, tostring(refusal))
print(decisions[1].actor, decisions[1].verdict)

return {
	fromEnvironment = fromEnvironment,
	fromConfiguration = fromConfiguration,
	unresolved = unresolved,
	decisions = decisions,
}
