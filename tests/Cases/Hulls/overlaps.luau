--[[
    Hulls.overlaps tests an oriented box against every walking hull, downed
    ones included, down to a rod only a crossed pair of edges separates
--]]

--!strict
local Environment = require("../../Environment")

local HULLS: string = "src/Step/Hulls.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local REFUSAL: string = "A box needs a size above 0"
local FEET: number = 1100

type Row = {
	name: string,
	box: { [string]: vector },
	posture: string?,
	moveMode: string?,
	overlaps: boolean,
}

local function box(center: vector, right: vector, up: vector, look: vector, size: vector): { [string]: vector }
	return { center = center, right = right, up = up, look = look, size = size }
end

return function (): (boolean, string | nil)
	local Hulls: any = Environment.load(HULLS)
	local Scene: any = Environment.load(SCENE)
	local radius: number = Scene.settings.radius
	local standing: number = Scene.settings.standing
	local xAxis: vector = vector.create(1, 0, 0)
	local yAxis: vector = vector.create(0, 1, 0)
	local zAxis: vector = vector.create(0, 0, 1)
	local root: number = math.sqrt(0.5)

	-- A 45° turn about Y, its corner pointed at the hull
	local turnedRight: vector = vector.create(root, 0, -root)
	local turnedLook: vector = vector.create(root, 0, root)

	-- A thin rod across the hull's top front edge, along (0, -1, 1), with its section turned 45° about its length,
	-- so the only axis that parts it from the hull is the edge's direction crossed with the rod's
	local length: vector = vector.create(0, -root, root)
	local across: vector = vector.create(root, 0.5, 0.5)
	local over: vector = vector.create(-root, 0.5, 0.5)
	local rod: vector = vector.create(0.2, 0.2, 10)
	local edge: vector = vector.create(0, FEET + standing, radius)

	local rows: { Row } = {
		{
			name = "a box around its middle",
			box = box(vector.create(0, FEET + 2, 0), xAxis, yAxis, zAxis, vector.create(1, 1, 1)),
			overlaps = true,
		},
		{
			name = "a box touching its side",
			box = box(vector.create(radius + 0.5, FEET + 2, 0), xAxis, yAxis, zAxis, vector.create(1, 1, 1)),
			overlaps = false,
		},
		{
			name = "a turned box whose corner reaches its side",
			box = box(vector.create(radius + 0.6, FEET + 2, 0), turnedRight, yAxis, turnedLook, vector.create(1, 1, 1)),
			overlaps = true,
		},
		{
			name = "a turned box whose corner stops short of its side",
			box = box(vector.create(radius + 0.8, FEET + 2, 0), turnedRight, yAxis, turnedLook, vector.create(1, 1, 1)),
			overlaps = false,
		},
		{
			name = "a rod cutting its top front edge",
			box = box(edge + vector.create(0, 0.05, 0.05), across, over, length, rod),
			overlaps = true,
		},
		{
			name = "a rod passing its top front edge, parted only by the crossed edges",
			box = box(edge + vector.create(0, 0.5, 0.5), across, over, length, rod),
			overlaps = false,
		},
		{
			name = "a box around a downed hull",
			box = box(vector.create(0, FEET + 1, 0), xAxis, yAxis, zAxis, vector.create(1, 1, 1)),
			posture = "Downed",
			overlaps = true,
		},
		{
			name = "a box around a Noclip hull",
			box = box(vector.create(0, FEET + 2, 0), xAxis, yAxis, zAxis, vector.create(1, 1, 1)),
			moveMode = "Noclip",
			overlaps = false,
		},
	}

	for _, row: Row in rows do
		local other: any = Scene.state(vector.create(0, FEET, 0), true)
		other.posture = row.posture or "Stand"
		other.moveMode = row.moveMode or "Walk"

		local world: any = Scene.world(Environment.load(CASTS)({}), { other })
		if Hulls.overlaps(row.box, world) ~= row.overlaps then
			return false, `Hulls.overlaps gave {not row.overlaps} for {row.name}, where {row.overlaps} was expected`
		end
	end

	local world: any = Scene.world(Environment.load(CASTS)({}), {})
	local flat: { [string]: vector } = box(vector.zero, xAxis, yAxis, zAxis, vector.create(1, 0, 1))
	local ran: boolean, message: any = pcall(Hulls.overlaps, flat, world)
	if ran then
		return false, "Hulls.overlaps took a box with no height"
	elseif not string.find(`{message}`, REFUSAL, 1, true) then
		return false, `Hulls.overlaps of a box with no height failed with something other than its refusal: {message}`
	end

	return true, nil
end
