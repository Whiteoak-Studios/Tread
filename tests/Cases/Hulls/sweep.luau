--[[
    Hulls.sweep meets the nearest live hull along a box's move with its face's
    normal, and skips a hull it starts in, a downed one, and every one while
    the box's own body is Noclip
--]]

--!strict
local Environment = require("../../Environment")

local HULLS: string = "src/Step/Hulls.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local FEET: number = 1100
local TOLERANCE: number = 1e-6 -- Past float32's rounding of the hull's size, which a vector holds

type Row = {
	name: string,
	others: { vector }, -- The other bodies' feet
	downed: boolean?, -- Whether the first other is downed
	noclip: boolean?, -- Whether the moving body is Noclip
	from: vector, -- The moving body's feet
	direction: vector,
	distance: number, -- math.huge for none
	normal: vector,
	body: number?, -- Which other it meets
}

return function (): (boolean, string | nil)
	local Hulls: any = Environment.load(HULLS)
	local Scene: any = Environment.load(SCENE)
	local width: number = 2 * Scene.settings.radius
	local standing: number = Scene.settings.standing
	local size: vector = vector.create(width, standing, width)
	local east: vector = vector.create(10, 0, 0)

	local rows: { Row } = {
		{
			name = "a hull ahead",
			others = { vector.create(5, FEET, 0) },
			from = vector.create(0, FEET, 0),
			direction = east,
			distance = 5 - width,
			normal = vector.create(-1, 0, 0),
			body = 1,
		},
		{
			name = "the nearer of two hulls",
			others = { vector.create(8, FEET, 0), vector.create(5, FEET, 0) },
			from = vector.create(0, FEET, 0),
			direction = east,
			distance = 5 - width,
			normal = vector.create(-1, 0, 0),
			body = 2,
		},
		{
			name = "a head below",
			others = { vector.create(1, FEET, 0) },
			from = vector.create(0, FEET + standing + 2, 0),
			direction = vector.create(0, -10, 0),
			distance = 2,
			normal = vector.create(0, 1, 0),
			body = 1,
		},
		{
			name = "a hull beside the move",
			others = { vector.create(5, FEET, 0) },
			from = vector.create(0, FEET, 0),
			direction = vector.create(0, 0, 10),
			distance = math.huge,
			normal = vector.zero,
		},
		{
			name = "a hull past the move's end",
			others = { vector.create(20, FEET, 0) },
			from = vector.create(0, FEET, 0),
			direction = east,
			distance = math.huge,
			normal = vector.zero,
		},
		{
			name = "a hull it starts in",
			others = { vector.create(1, FEET, 0) },
			from = vector.create(0, FEET, 0),
			direction = east,
			distance = math.huge,
			normal = vector.zero,
		},
		{
			name = "a downed hull",
			others = { vector.create(5, FEET, 0) },
			downed = true,
			from = vector.create(0, FEET, 0),
			direction = east,
			distance = math.huge,
			normal = vector.zero,
		},
		{
			name = "a hull, moving Noclip",
			others = { vector.create(5, FEET, 0) },
			noclip = true,
			from = vector.create(0, FEET, 0),
			direction = east,
			distance = math.huge,
			normal = vector.zero,
		},
	}

	for _, row: Row in rows do
		local state: any = Scene.state(row.from, true)
		local bodies: { any } = { state }
		local others: { any } = {}

		for _, feet: vector in row.others do
			local other: any = Scene.state(feet, true)
			table.insert(others, other)
			table.insert(bodies, other)
		end

		if row.downed then
			others[1].posture = "Downed"
		end

		if row.noclip then
			state.moveMode = "Noclip"
		end

		local world: any = Scene.world(Environment.load(CASTS)({}), bodies)
		local center: vector = row.from + vector.create(0, standing / 2, 0)
		local distance: number, normal: vector, body: any = Hulls.sweep(state, center, size, row.direction, world)
		local wantBody: any = row.body and others[row.body]

		local wrongDistance: boolean = math.abs(distance - row.distance) > TOLERANCE
			and not (distance == math.huge and row.distance == math.huge)
		if wrongDistance or normal ~= row.normal or body ~= wantBody then
			local found: string = `Hulls.sweep past {row.name} gave {distance} and {normal}`
			local wanted: string = `{row.distance} and {row.normal}`

			return false, `{found}, where {wanted} were expected`
		end
	end

	return true, nil
end
