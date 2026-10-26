--!strict

export type Unit = "m" | "cm" | "mm"

export type Size = {
	x: number,
	y: number,
	z: number,
	unit: Unit?,
}

export type Studs = {
	x: number,
	y: number,
	z: number,
}

local METRES_PER_STUD = 0.28

local METRES_PER_UNIT: { [string]: number } = {
	m = 1,
	cm = 0.01,
	mm = 0.001,
}

local function dimension(value: unknown, axis: string): number
	if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
		error(("Generate Roblox size %s must be a positive finite number"):format(axis), 3)
	end
	return value :: number
end

local function studs(size: Size): Studs
	local unit = size.unit or "m"
	local scale = METRES_PER_UNIT[unit]
	if scale == nil then
		error("Generate Roblox size unit must be m, cm or mm", 2)
	end
	return {
		x = dimension(size.x, "x") * scale / METRES_PER_STUD,
		y = dimension(size.y, "y") * scale / METRES_PER_STUD,
		z = dimension(size.z, "z") * scale / METRES_PER_STUD,
	}
end

return {
	studs = studs,
}
