--[[
    Going down, parking and noclip each end a mantle partway, dropping the
    body into the air with its progress and rise cleared, and noclip lets go
    of a ladder
--]]

--!strict
local Environment = require("../../Environment")

local COURSE: string = "tests/Fixtures/Step/Course.luau"
local WORLD: string = "src/Step/World.luau"
local PARTWAY: number = 3 -- Ticks into a mantle's path, short of its end
local LADDER_START: number = 193.5 -- Feet whose hull already reaches into the course's ladder

type Cut = {
	label: string,
	apply: (state: any) -> (),
}

return function (): (boolean, string | nil)
	local Course: any = Environment.load(COURSE)
	local World: any = Environment.load(WORLD)

	local cuts: { Cut } = {
		{
			label = "going down",
			apply = function (state: any)
				state.posture = "Downed"
			end,
		},
		{
			label = "parking",
			apply = function (state: any)
				state.moveMode = "Parked"
			end,
		},
		{
			label = "noclip",
			apply = function (state: any)
				state.moveMode = "Noclip"
			end,
		},
	}

	for _, cut: Cut in cuts do
		local world: any = Course.world()
		local state: any =
			Course.state(vector.create(Course.approach, Course.resting, Course.rows.exact.center.z), true)
		local order: any = Course.command()
		order.yaw = Course.east
		order.jump, order.pressed.jump = true, true

		Course.advance(state, world, order, PARTWAY)
		if state.mode ~= "Mantle" or state.mantleTicks ~= PARTWAY then
			return false, `before {cut.label} the body was {state.mode} at {state.mantleTicks} ticks of a mantle`
		end

		cut.apply(state)
		Course.advance(state, world, order, 1)
		if state.mode ~= "Air" or state.mantleTicks ~= 0 or state.mantleRise ~= 0 then
			local left: string = `{state.mode} at {state.mantleTicks} ticks and a rise of {state.mantleRise}`

			return false, `{cut.label} partway through a mantle left the body {left}`
		end
	end

	local world: any = Course.world()
	World.addLadder(world, Course.ladder.cframe, Course.ladder.size)
	local climber: any = Course.state(vector.create(LADDER_START, Course.resting, 0), true)
	local climb: any = Course.command()
	climb.yaw = Course.east
	climb.forward = 1

	Course.advance(climber, world, climb, 1)
	if climber.mode ~= "Ladder" then
		return false, `walking into the ladder left the body {climber.mode}`
	end

	climber.moveMode = "Noclip"
	Course.advance(climber, world, climb, 1)
	if climber.mode ~= "Air" or climber.ladder ~= 0 then
		return false, `noclip on a ladder left the body {climber.mode} on ladder {climber.ladder}`
	end

	return true, nil
end
