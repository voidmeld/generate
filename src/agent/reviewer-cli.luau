--!strict

export type Request = {
	executable: string,
	configuredPath: string?,
	environmentVariable: string?,
	readEnv: ((name: string) -> string?)?,
	exists: ((path: string) -> boolean)?,
	arguments: { string }?,
}

export type Source = "configured" | "environment"

export type Resolved = {
	ok: true,
	executable: string,
	path: string,
	source: Source,
	origin: string,
	command: { string },
}

export type Refused = {
	ok: false,
	executable: string,
	refusal: string,
}

export type Resolution = Resolved | Refused

local function nonempty(value: unknown): boolean
	return type(value) == "string" and value ~= ""
end

local function origins(request: Request): string
	local named: { string } = {}
	if nonempty(request.configuredPath) then
		table.insert(named, ("configured path %s"):format(request.configuredPath :: string))
	else
		table.insert(named, "no configured path")
	end
	if nonempty(request.environmentVariable) then
		table.insert(named, ("environment variable %s"):format(request.environmentVariable :: string))
	else
		table.insert(named, "no environment variable")
	end
	return table.concat(named, " and ")
end

local function refuse(request: Request, detail: string): Refused
	return {
		ok = false,
		executable = request.executable,
		refusal = ("Generate reviewer runner cannot resolve the %s executable: %s. The runner never falls back to a search path, so name the executable through a configured path or an environment variable (%s)."):format(
			request.executable,
			detail,
			origins(request)
		),
	}
end

local function accept(request: Request, path: string, source: Source, origin: string): Resolved
	local command: { string } = { path }
	if request.arguments ~= nil then
		for _, argument in request.arguments do
			table.insert(command, argument)
		end
	end
	return {
		ok = true,
		executable = request.executable,
		path = path,
		source = source,
		origin = origin,
		command = command,
	}
end

local function resolve(request: Request): Resolution
	if type(request) ~= "table" or not nonempty(request.executable) then
		error("Generate.reviewerCli.resolve expects a request naming the executable it needs", 2)
	end
	if request.arguments ~= nil then
		for index, argument in request.arguments do
			if not nonempty(argument) then
				error(("Generate reviewer runner argument %d must be a non-empty string"):format(index), 2)
			end
		end
	end
	local exists = request.exists or function(): boolean
		return true
	end
	if nonempty(request.configuredPath) then
		local path = request.configuredPath :: string
		local checked, present = pcall(exists, path)
		if not checked then
			return refuse(request, ("the configured path %s could not be inspected"):format(path))
		end
		if present ~= true then
			return refuse(request, ("the configured path %s names no executable file"):format(path))
		end
		return accept(request, path, "configured", ("configured path %s"):format(path))
	end
	if not nonempty(request.environmentVariable) then
		return refuse(request, "neither a configured path nor an environment variable was supplied")
	end
	local name = request.environmentVariable :: string
	local readEnv = request.readEnv
	if readEnv == nil then
		return refuse(request, ("environment variable %s cannot be read without a host reader"):format(name))
	end
	local read, value = pcall(readEnv, name)
	if not read then
		return refuse(request, ("environment variable %s could not be read"):format(name))
	end
	if not nonempty(value) then
		return refuse(request, ("environment variable %s is unset or empty"):format(name))
	end
	local path = value :: string
	local checked, present = pcall(exists, path)
	if not checked then
		return refuse(request, ("environment variable %s names %s, which could not be inspected"):format(name, path))
	end
	if present ~= true then
		return refuse(request, ("environment variable %s names %s, which is no executable file"):format(name, path))
	end
	return accept(request, path, "environment", ("environment variable %s"):format(name))
end

return {
	resolve = resolve,
}
