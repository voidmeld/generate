--!strict

local function digest(bytes: string): string
	local low, high = 2166136261, 4294967291
	for index = 1, #bytes do
		low = bit32.bxor(low * 16777619 % 4294967296, string.byte(bytes, index))
		high = (high * 31 + string.byte(bytes, index)) % 4294967296
	end
	return string.format("%08x%08x%08x%08x", low, high, bit32.bxor(low, high), (low + high) % 4294967296)
end

return {
	digest = digest,
}
