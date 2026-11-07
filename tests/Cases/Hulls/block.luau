--[[
    Hulls.block tests a hull where it stands against the other live hulls:
    overlap blocks, touching does not, and its own, a downed one and a Noclip
    one never do
--]]

--!strict
local Environment = require("../../Environment")

local HULLS: string = "src/Step/Hulls.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local QUANTUM: number = 1 / 512 -- A step's positions are whole quanta, which a vector's float32 holds exactly
local FEET: number = 1100 + 10 * QUANTUM -- Feet at rest on a floor at 1,100, quantized

type Row = {
	name: string,
	other: vector, -- The other body's feet
	posture: string?,
	otherMode: string?,
	ownMode: string?,
	ownPosture: string?,
	blocked: boolean,
}

return function (): (boolean, string | nil)
	local Hulls: any = Environment.load(HULLS)
	local Scene: any = Environment.load(SCENE)
	local width: number = 2 * Scene.settings.radius
	local standing: number = Scene.settings.standing
	local crouched: number = Scene.settings.crouched

	local rows: { Row } = {
		{ name = "a hull overlapping it", other = vector.create(2, FEET, 0), blocked = true },
		{ name = "a hull a quantum into its side", other = vector.create(width - QUANTUM, FEET, 0), blocked = true },
		{
			name = "a hull a quantum clear of its side",
			other = vector.create(width + QUANTUM, FEET, 0),
			blocked = false,
		},
		{ name = "a hull on its head", other = vector.create(2, FEET + standing, 0), blocked = false },
		{ name = "a hull sunk into its head", other = vector.create(2, FEET + standing - 0.1, 0), blocked = true },
		{ name = "a downed hull", other = vector.create(2, FEET, 0), posture = "Downed", blocked = false },
		{ name = "a Noclip hull", other = vector.create(2, FEET, 0), otherMode = "Noclip", blocked = false },
		{ name = "a hull, from a Parked body", other = vector.create(2, FEET, 0), ownMode = "Parked", blocked = false },
		{
			name = "a hull a quantum over its crouched head",
			other = vector.create(2, FEET + crouched + QUANTUM, 0),
			ownPosture = "Crouch",
			blocked = false,
		},
		{
			name = "a hull in its crouched head",
			other = vector.create(2, FEET + crouched - 0.1, 0),
			ownPosture = "Crouch",
			blocked = true,
		},
	}

	for _, row: Row in rows do
		local state: any = Scene.state(vector.create(0, FEET, 0), true)
		local other: any = Scene.state(row.other, true)
		state.moveMode = row.ownMode or "Walk"
		state.posture = row.ownPosture or "Stand"
		other.moveMode = row.otherMode or "Walk"
		other.posture = row.posture or "Stand"

		local world: any = Scene.world(Environment.load(CASTS)({}), { state, other })
		if Hulls.block(state, world) ~= row.blocked then
			return false, `Hulls.block gave {not row.blocked} for {row.name}, where {row.blocked} was expected`
		end
	end

	-- Alone in the world, a body never blocks itself
	local alone: any = Scene.state(vector.create(0, FEET, 0), true)
	if Hulls.block(alone, Scene.world(Environment.load(CASTS)({}), { alone })) then
		return false, "Hulls.block found a body blocked by its own hull"
	end

	return true, nil
end
