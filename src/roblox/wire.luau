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
	return if type(value) == "string" and value ~= "" then value :: string else nil
end

local function numericId(value: unknown): string?
	if type(value) == "string" and string.match(value :: string, "^[1-9][0-9]*$") ~= nil then
		return value :: string
	end
	if type(value) == "number" and value > 0 and value % 1 == 0 and value ~= math.huge then
		return ("%.0f"):format(value)
	end
	return nil
end

local function sameIds(left: unknown, right: { string }): boolean
	if type(left) ~= "table" or #(left :: { unknown }) ~= #right then
		return false
	end
	for index, assetId in right do
		if (left :: { unknown })[index] ~= assetId then
			return false
		end
	end
	return true
end

return {
	text = text,
	numericId = numericId,
	sameIds = sameIds,
}
