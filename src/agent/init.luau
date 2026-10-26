--!strict

local ReviewerCli = require "./agent/reviewer-cli"
local ReviewerStream = require "./agent/reviewer-stream"

export type ReviewerCliRequest = ReviewerCli.Request
export type ReviewerCliResolution = ReviewerCli.Resolution
export type ReviewerCliResolved = ReviewerCli.Resolved
export type ReviewerCliRefused = ReviewerCli.Refused
export type ReviewerPacketRef = ReviewerStream.PacketRef
export type ReviewerStreamOptions = ReviewerStream.StreamOptions
export type ReviewerStreamContract = ReviewerStream.StreamContract
export type ReviewerStreamVerdict = ReviewerStream.StreamVerdict

return {
	reviewerCli = ReviewerCli,
	reviewerStream = ReviewerStream,
}
