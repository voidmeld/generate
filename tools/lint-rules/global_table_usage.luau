--!strict

local path = require "@std/path"
local query = require "@std/syntax/query"
local syntax = require "@std/syntax"
local utils = require "@std/syntax/utils"

type Violation = {
	lintname: string,
	location: syntax.Span,
	message: string,
	severity: "error" | "warning" | "info" | "hint",
	sourcepath: path.Path?,
}

type Global = { name: { text: string }, location: syntax.Span }

local NAME = "global_table_usage"
local FLAGGED: { [string]: boolean } = { _G = true, shared = true }

local function asGlobal(node: syntax.CstNode): Global?
	return (utils.isExprGlobal(node) :: unknown) :: Global?
end

local function lint(cst: syntax.CstStatBlock, sourcepath: path.Path?, _context: unknown): { Violation }
	return query
		.findAllFromRoot(cst, asGlobal)
		:filter(function(node: Global): boolean
			return FLAGGED[node.name.text] == true
		end)
		:mapToArray(function(node: Global): Violation
			return {
				lintname = NAME,
				location = node.location,
				message = ("`%s` is ambient process-wide state; pass it through an explicit Generate host or adapter"):format(
					node.name.text
				),
				severity = "warning",
				sourcepath = sourcepath,
			}
		end)
end

return table.freeze { name = NAME, lint = lint }
