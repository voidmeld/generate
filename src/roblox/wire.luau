--!strict

export type Response = {
	ok: boolean,
	status: number,
	body: string,
}

export type AuthorizedRequest = {
	method: "GET" | "POST" | "PATCH",
	url: string,
	headers: { [string]: string },
	body: string?,
}

export type SendAuthorized = (request: AuthorizedRequest) -> Response

export type Decode = (body: string) -> unknown
export type Encode = (value: unknown) -> string

local function text(value: unknown): string?
	return if type(value) == "string" and value ~= "" then value else nil
end

local function numericId(value: unknown): string?
	if type(value) == "string" and string.match(value, "^[1-9][0-9]*$") ~= nil then
		return value
	end
	if type(value) == "number" and value > 0 and value % 1 == 0 and value ~= math.huge then
		return ("%.0f"):format(value)
	end
	return nil
end

local function field(value: unknown, name: string): unknown
	if type(value) ~= "table" then
		return nil
	end
	for key, item in value do
		if key == name then
			return item
		end
	end
	return nil
end

local function sameIds(left: unknown, right: { string }): boolean
	if type(left) ~= "table" then
		return false
	end
	local count = 0
	for index, assetId in left do
		if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or right[index] ~= assetId then
			return false
		end
		count += 1
	end
	return count == #right
end

return {
	text = text,
	numericId = numericId,
	field = field,
	sameIds = sameIds,
}
