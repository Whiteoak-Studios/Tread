--[[
    A 0.5-stud curb right in front of a 4-stud wall is no mantle while the
    curb is the face, however high the wall behind it reaches; standing on
    the curb facing the wall, the mantle is found
--]]

--!strict
local Environment = require("../../Environment")

local STAIRS: string = "tests/Fixtures/Step/Stairs.luau"
local MANTLE: string = "src/Step/Mantle.luau"
local COURSE: string = "tests/Fixtures/Step/Course.luau"
local CONSTANTS: string = "src/Constants.luau"
local MATH: string = "src/Step/Math.luau"

local FACE: number = 10 -- The curb's face, met walking along +X
local CURB: number = 0.5 -- The curb's height over the floor
local CURB_DEPTH: number = 1 -- Along X, so the wall stands under where a mantle would land from the floor
local WALL: number = 4 -- The wall's height over the floor
local WALL_DEPTH: number = 6

return function (): (boolean, string | nil)
	local Stairs: any = Environment.load(STAIRS)
	local Mantle: any = Environment.load(MANTLE)
	local Course: any = Environment.load(COURSE)
	local Constants: any = Environment.load(CONSTANTS)
	local Math: any = Environment.load(MATH)

	local radius: number = Course.settings.radius
	local skin: number = Constants.SKIN
	local wallFace: number = FACE + CURB_DEPTH
	local world: any = Stairs.world({
		Stairs.box("Curb", FACE, wallFace, Course.floor + CURB),
		Stairs.box("Wall", wallFace, wallFace + WALL_DEPTH, Course.floor + WALL),
	})

	local floor: vector = vector.create(Math.quantize(FACE - radius - skin), Course.resting, 0)
	local before: string? = Mantle.find(Stairs.body(floor, Stairs.east), world)
	if before ~= nil then
		return false, `Facing the curb from the floor, the search found a mantle {before} onto the wall behind it`
	end

	local curb: vector =
		vector.create(Math.quantize(wallFace - radius - skin), Math.quantize(Course.floor + CURB + skin), 0)
	local on: string? = Mantle.find(Stairs.body(curb, Stairs.east), world)
	if on ~= "Stand" then
		return false, `Standing on the curb facing the wall, the search gave {on}, where Stand was expected`
	end

	return true, nil
end
