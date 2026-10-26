--!strict

local process = require "@std/process"
local Policy = require "./checks-policy"
local Repository = require "../.lute/dependencies/verify/src/checks/repository"
local Clone = require "../.lute/dependencies/verify/src/checks/clean-clone"
local Comments = require "../.lute/dependencies/verify/src/checks/comments"
local Manifest = require "../.lute/dependencies/verify/src/checks/manifest"
local Provenance = require "../.lute/dependencies/verify/src/checks/provenance"
local Surface = require "../.lute/dependencies/verify/src/checks/surface"

local config: {
	boundary: Repository.Boundary,
	leakage: Repository.Scan,
	provenance: Provenance.Config,
	comments: Comments.Config,
	manifest: Manifest.Config,
	publicSurface: Surface.Config,
	cleanClone: Clone.Config,
	noAny: Repository.Selection,
	specStyle: Repository.Selection,
} =
	{
		boundary = {
			root = "src/core",
			rules = Policy.boundary,
		},
		leakage = {
			untracked = true,
			suffixes = { ".luau", ".lua", ".md", ".json", ".toml", ".txt", ".yml", ".yaml" },
			exclude = { [Policy.selfPath] = true, LICENSE = true },
			rules = Policy.leakage,
			allowedLiterals = {},
		},
		provenance = {
			forbiddenPaths = {
				"vendor",
				"third_party",
				"third-party",
				"node_modules",
				"Packages",
				"DevPackages",
				"bench/frameworks",
			},
			license = "LICENSE",
			licensePrefix = "MIT License\n",
			licenseFragments = {
				"Copyright (c) 2026 voidmeld",
				"Permission is hereby granted, free of charge, to any person obtaining a copy",
			},
			lock = "dependencies.lock.luau",
			dependencyCommand = { "lute", "run", "tools/sync-dependencies.luau", "--check" },
			root = ".",
			skip = { ".git/", "build/", "bench/results/", ".lute/" },
			suffixes = { ".luau", ".lua", ".md", ".toml", ".json", ".yml", ".yaml", ".sh", ".py" },
			descriptors = {
				"manifest.json",
				"package.json",
				"package-lock.json",
				"wally.toml",
				"wally.lock",
				"rotriever.toml",
			},
			noticeNames = { "LICENSE", "LICENCE", "LICENSE.md", "LICENCE.md", "COPYING", "NOTICE", "NOTICE.md" },
			expectedNotices = { LICENSE = "Generate's MIT license grant" },
			scriptExceptions = {},
			forbiddenSuffixes = { ".py" },
			justifiedSuffixes = { ".sh" },
		},
		comments = {
			roots = { "bench", "examples", "src", "tests", "tools" },
			files = { "dependencies.lock.luau", "lint.config.luau" },
			configFiles = { ".styluaignore", "rokit.toml", "stylua.toml" },
			allowed = { "^%-%-![A-Za-z]+", "^%-%-# selene" },
			lineDirectives = true,
		},
		manifest = {
			path = "tools/test-manifest.luau",
			rules = {
				{ root = "tests", pattern = "%.verify%.luau$" },
				{ root = "tools", pattern = "%.verify%.luau$" },
			},
		},
		publicSurface = {
			docs = "docs/api.md",
			recursive = true,
			codeReferences = true,
			includeTypes = true,
			undocumented = {},
			packages = {
				{
					prefix = "Generate",
					entry = "src/core/init.luau",
					load = function(): unknown
						return require "../src/core"
					end,
				},
				{
					prefix = "Agent",
					entry = "src/agent/init.luau",
					load = function(): unknown
						return require "../src/agent"
					end,
				},
				{
					prefix = "Roblox",
					entry = "src/roblox/init.luau",
					load = function(): unknown
						return require "../src/roblox"
					end,
				},
				{
					prefix = "Media",
					entry = "src/media/init.luau",
					load = function(): unknown
						return require "../src/media"
					end,
				},
				{
					prefix = "Image",
					entry = "src/image/init.luau",
					load = function(): unknown
						return require "../src/image"
					end,
				},
				{
					prefix = "Content",
					entry = "src/content/init.luau",
					load = function(): unknown
						return require "../src/content"
					end,
				},
				{
					prefix = "Lute",
					entry = "src/lute/init.luau",
					load = function(): unknown
						return require "../src/lute"
					end,
				},
				{
					prefix = "Host",
					entry = "src/host/init.luau",
					load = function(): unknown
						return require "../src/host"
					end,
				},
				{
					prefix = "Consumer",
					entry = "src/consumer/init.luau",
					load = function(): unknown
						return require "../src/consumer"
					end,
				},
			},
		},
		cleanClone = {
			prefix = "generate-clean-clone",
			command = { "lute", "run", "tools/gate.luau", "--tier", "fast" },
			env = { VERIFY_SOURCE = tostring(process.cwd()) .. "/.lute/dependencies/verify" },
			requiredPaths = { ".lute/dependencies" },
		},
		noAny = { untracked = true },
		specStyle = { untracked = true, exclude = { ["tests/adapters.lute.verify.luau"] = true } },
	}

local function writeRequested(): boolean
	local write = false
	for index = 2, #process.args do
		assert(process.args[index] == "--write", "expected no arguments or --write")
		write = true
	end
	return write
end

config.comments.write = if string.match(process.args[1], "check%-code%-comments%.luau$")
	then writeRequested()
	else false
if string.match(process.args[1], "check%-test%-manifest%.luau$") then
	config.manifest.write = writeRequested()
	config.manifest.entries = if config.manifest.write then nil else require "./test-manifest"
	config.manifest.format = function(path)
		local result = process.run { "stylua", path }
		assert(result.ok, result.stderr)
	end
end
return config
