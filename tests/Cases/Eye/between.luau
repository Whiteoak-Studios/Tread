--[[
    Between two walls nearer than the game's clearance on either side, the
    cleared eye sits midway, though the body stands off the middle
--]]

--!strict
local Environment = require("../../Environment")

local EYE: string = "src/Step/Eye.luau"
local MATH: string = "src/Step/Math.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local FLOOR: number = 1100
local SKIN: number = 0.02
local GAP: number = 2.82 -- Between the walls' faces: room for the 2.78-stud hull, under twice the 1.45-stud clearance
local THICKNESS: number = 1
local HEIGHT: number = 8
local OFF_MIDDLE: number = 0.01 -- How far toward the right wall the body stands
local TOLERANCE: number = 1e-6 -- A vector holds float32, which rounds 0.01 by about 1e-8

return function (): (boolean, string | nil)
	local Eye: any = Environment.load(EYE)
	local Math: any = Environment.load(MATH)
	local Scene: any = Environment.load(SCENE)

	local reach: number = GAP / 2 + THICKNESS / 2 -- From the middle to each wall's center
	local size: vector = vector.create(THICKNESS, HEIGHT, HEIGHT)
	local walls: { any } = {
		{ name = "Left", center = vector.create(-reach, FLOOR + HEIGHT / 2, 0), size = size, tilt = 0 },
		{ name = "Right", center = vector.create(reach, FLOOR + HEIGHT / 2, 0), size = size, tilt = 0 },
	}

	local world: any = Scene.world(Environment.load(CASTS)(walls))
	local state: any = Scene.state(vector.create(OFF_MIDDLE, FLOOR + SKIN, 0), true)
	state.eyeHeight = Math.quantizeEye(Scene.settings.eyeStanding)

	local eye: vector = Eye.clear(state, world)
	if math.abs(eye.x) > TOLERANCE then
		return false, `the eye between the walls sat at x {eye.x}, where the middle, 0, was expected`
	end

	return true, nil
end
