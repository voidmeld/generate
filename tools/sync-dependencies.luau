--!strict
local fs = require "@std/fs"
local process = require "@lute/process"
type Dependency = {
	name: string,
	repository: string,
	commit: string,
	tree: string,
	rights: string,
	surfaces: { { root: string, role: "runtime" | "tooling" | "verification" } },
}
type Lock = {
	schemaVersion: number,
	dependencies: { Dependency },
}
local CACHE_ROOT = ".lute/dependencies"
local REQUIRED_RIGHTS = "MIT"
local lock = require "../dependencies.lock" :: Lock
local function trim(value: string): string
	return string.match(value, "^%s*(.-)%s*$") or ""
end
local function git(path: string, arguments: { string }): (boolean, string)
	local argv = { "git", "-C", path }
	for _, argument in arguments do
		table.insert(argv, argument)
	end
	local result = process.run(argv)
	return result.ok, trim(result.stdout)
end
local function validateDefinition(dependency: Dependency): string?
	if string.match(dependency.name, "^[a-z][a-z0-9%-]*$") == nil then
		return "name must match ^[a-z][a-z0-9%-]*$"
	end
	if string.match(dependency.repository, "^https://github%.com/voidmeld/[a-z0-9%-]+%.git$") == nil then
		return "repository must name an HTTPS studio repository without credentials"
	end
	if
		string.match(
			dependency.commit,
			"^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"
		) == nil
	then
		return "commit must be a full 40-character object id"
	end
	if
		string.match(
			dependency.tree,
			"^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"
		) == nil
	then
		return "tree must be a full 40-character object id"
	end
	if dependency.rights ~= REQUIRED_RIGHTS then
		return "rights must declare the dependency's MIT license"
	end
	if #dependency.surfaces == 0 then
		return "surfaces must name at least one consumed root"
	end
	local seenRoots: { [string]: boolean } = {}
	for _, surface in dependency.surfaces do
		local root = surface.root
		if root == "" or string.sub(root, 1, 1) == "/" or string.find(root, "..", 1, true) ~= nil then
			return "surface roots must be repository-relative paths without traversal"
		end
		if seenRoots[root] then
			return "a consumed root may be classified only once"
		end
		seenRoots[root] = true
		if surface.role ~= "runtime" and surface.role ~= "tooling" and surface.role ~= "verification" then
			return "surface roles must be runtime, tooling, or verification"
		end
	end
	return nil
end
local function findings(dependency: Dependency, path: string): { string }
	local out: { string } = {}
	local function check(label: string, arguments: { string }, expected: string)
		local ok, actual = git(path, arguments)
		if not ok then
			table.insert(out, label .. " could not be read")
		elseif actual ~= expected then
			table.insert(out, ("%s is %s, expected %s"):format(label, actual, expected))
		end
	end
	check("commit", { "rev-parse", "HEAD" }, dependency.commit)
	check("tree", { "rev-parse", "HEAD^{tree}" }, dependency.tree)
	check("repository", { "config", "--local", "--get", "remote.origin.url" }, dependency.repository)
	local statusOk, status = git(path, { "status", "--porcelain" })
	if not statusOk then
		table.insert(out, "working-tree state could not be read")
	elseif status ~= "" then
		table.insert(out, "cached checkout is dirty")
	end
	for _, surface in dependency.surfaces do
		local root = surface.root
		if not fs.exists(path .. "/" .. root) then
			table.insert(out, root .. " is absent")
		end
	end
	return out
end
local function exactSibling(dependency: Dependency): string?
	local sibling = "../" .. dependency.name
	if not fs.exists(sibling) then
		return nil
	end
	local headOk, head = git(sibling, { "rev-parse", "HEAD" })
	local treeOk, tree = git(sibling, { "rev-parse", "HEAD^{tree}" })
	local statusOk, status = git(sibling, { "status", "--porcelain" })
	if headOk and treeOk and statusOk and head == dependency.commit and tree == dependency.tree and status == "" then
		return sibling
	end
	return nil
end
local function clone(dependency: Dependency, destination: string): string?
	local source = exactSibling(dependency) or dependency.repository
	local cloned = process.run { "git", "clone", "--quiet", "--no-checkout", source, destination }
	if not cloned.ok then
		return "clone failed; check repository availability and access"
	end
	local checkedOut = process.run {
		"git",
		"-C",
		destination,
		"checkout",
		"--quiet",
		"--detach",
		dependency.commit,
	}
	if not checkedOut.ok then
		return "the locked commit is not reachable from the repository"
	end
	local canonical = process.run {
		"git",
		"-C",
		destination,
		"remote",
		"set-url",
		"origin",
		dependency.repository,
	}
	if not canonical.ok then
		return "the cache remote could not be canonicalized"
	end
	local problems = findings(dependency, destination)
	if #problems > 0 then
		return table.concat(problems, "; ")
	end
	return nil
end
local function sync(dependency: Dependency, checkOnly: boolean): string?
	local target = CACHE_ROOT .. "/" .. dependency.name
	if fs.exists(target) and #findings(dependency, target) == 0 then
		return nil
	end
	if checkOnly then
		return "cache is absent or does not match the lock; run lute run tools/sync-dependencies.luau"
	end
	fs.createDirectory(CACHE_ROOT, { makeParents = true })
	local temporary = CACHE_ROOT .. "/." .. dependency.name .. "-" .. tostring(process.pid())
	if fs.exists(temporary) then
		fs.removeDirectory(temporary, { recursive = true })
	end
	local problem = clone(dependency, temporary)
	if problem ~= nil then
		if fs.exists(temporary) then
			fs.removeDirectory(temporary, { recursive = true })
		end
		return problem
	end
	if fs.exists(target) then
		if #findings(dependency, target) == 0 then
			fs.removeDirectory(temporary, { recursive = true })
			return nil
		end
		fs.removeDirectory(target, { recursive = true })
	end
	fs.move(temporary, target)
	return nil
end

local function validateRepositoryShape(seen: { [string]: boolean }): string?
	if fs.exists "vendor" then
		return "vendor/ is forbidden; sibling products belong in the ignored dependency cache"
	end
	if not fs.exists(CACHE_ROOT) then
		return nil
	end
	for _, entry in fs.listDirectory(CACHE_ROOT) do
		if string.sub(entry.name, 1, 1) ~= "." and not seen[entry.name] then
			return CACHE_ROOT .. "/" .. entry.name .. " is not declared by dependencies.lock.luau"
		end
	end
	return nil
end
local function main(): number
	local checkOnly = false
	for index = 2, #process.args do
		if process.args[index] == "--check" then
			checkOnly = true
		else
			print(("sync-dependencies: unrecognized argument %q"):format(process.args[index]))
			return 1
		end
	end
	if lock.schemaVersion ~= 1 then
		print "sync-dependencies: dependencies.lock.luau must use schema version 1"
		return 1
	end
	local seen: { [string]: boolean } = {}
	if #lock.dependencies == 0 then
		print "sync-dependencies: the lock contains no dependency"
		return 1
	end
	for _, dependency in lock.dependencies do
		if seen[dependency.name] then
			print("sync-dependencies: duplicate dependency " .. dependency.name)
			return 1
		end
		seen[dependency.name] = true
		local invalid = validateDefinition(dependency)
		if invalid ~= nil then
			print(("sync-dependencies: %s: %s"):format(dependency.name, invalid))
			return 1
		end
		local problem = sync(dependency, checkOnly)
		if problem ~= nil then
			print(("sync-dependencies: %s: %s"):format(dependency.name, problem))
			return 1
		end
		local roles: { string } = {}
		for _, surface in dependency.surfaces do
			table.insert(roles, surface.root .. ":" .. surface.role)
		end
		table.sort(roles)
		print(
			("sync-dependencies: %s at %s (%s)"):format(dependency.name, dependency.commit, table.concat(roles, ", "))
		)
	end
	local shapeProblem = validateRepositoryShape(seen)
	if shapeProblem ~= nil then
		print("sync-dependencies: " .. shapeProblem)
		return 1
	end
	return 0
end
local code = main()
if code ~= 0 then
	process.exit(code)
end
return nil
