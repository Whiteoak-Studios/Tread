--[[
    The face's own top decides at a step's height: a 4-stud wall mantles, a
    ledge one 1/32 stud over the feet plus the step height mantles, and one
    exactly at the feet plus the step height is a step the walk climbs
--]]

--!strict
local Environment = require("../../Environment")

local STAIRS: string = "tests/Fixtures/Step/Stairs.luau"
local MANTLE: string = "src/Step/Mantle.luau"
local COURSE: string = "tests/Fixtures/Step/Course.luau"
local CONSTANTS: string = "src/Constants.luau"
local MATH: string = "src/Step/Math.luau"

local FACE: number = 10 -- The ledge's face, met walking along +X
local DEPTH: number = 6 -- The ledge's along X
local WALL: number = 4 -- The wall's height over the floor
local OVER: number = 1 / 32 -- How far past the step height the lowest ledge here that mantles stands, the rise's step

-- One ledge facing a body on the floor, and the posture the search must give, nil for no mantle
type Trial = {
	label: string,
	top: number,
	want: string?,
}

return function (): (boolean, string | nil)
	local Stairs: any = Environment.load(STAIRS)
	local Mantle: any = Environment.load(MANTLE)
	local Course: any = Environment.load(COURSE)
	local Constants: any = Environment.load(CONSTANTS)
	local Math: any = Environment.load(MATH)

	local feet: vector = vector.create(Math.quantize(FACE - Course.settings.radius - Constants.SKIN), Course.resting, 0)
	local step: number = feet.y + Course.settings.stepHeight

	local trials: { Trial } = {
		{ label = "a 4-stud wall", top = Course.floor + WALL, want = "Stand" },
		{ label = "a ledge 1/32 stud over a step", top = step + OVER, want = "Stand" },
		{ label = "a ledge exactly a step high", top = step },
	}

	for _, trial: Trial in trials do
		local world: any = Stairs.world({ Stairs.box("Ledge", FACE, FACE + DEPTH, trial.top) })
		local posture: string? = Mantle.find(Stairs.body(feet, Stairs.east), world)
		if posture ~= trial.want then
			return false, `Facing {trial.label}, the search gave {posture}, where {trial.want} was expected`
		end
	end

	return true, nil
end
