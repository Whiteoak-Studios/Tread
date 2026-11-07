--[[
    The mantle's room check covers the hull at the arc's peak: under a roof
    with room for the standing hull at the rise and not at the peak, the
    arched mantle ends crouched, and with the arc at 0 the same one stands
--]]

--!strict
local Environment = require("../../Environment")

local STEP: string = "src/Step/init.luau"
local MANTLE: string = "src/Step/Mantle.luau"
local MATH: string = "src/Step/Math.luau"
local WORLD: string = "src/Step/World.luau"
local CONSTANTS: string = "src/Constants.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"

local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation, in Hz
local FLOOR: number = 1100
local FACE: number = 10 -- The ledge's face, met walking along +X
local LEDGE_HEIGHT: number = 3
local LEDGE_DEPTH: number = 6
local WIDTH: number = 6 -- The ledge's and the roof's along Z
local RISE: number = 3.03125 -- From feet resting on the floor to a skin over the ledge, on the rise's 1/32 steps
local SPARE: number = 0.25 -- Room over a standing head at the rise, inside the 0.5-stud arc
local THICKNESS: number = 1
local EAST: number = -math.pi / 2 -- A yaw that looks along +X

-- A box part by its center's X and Z, its bottom and top, its depth along X and its width along Z
local function box(name: string, x: number, bottom: number, top: number, depth: number): any
	return {
		name = name,
		center = vector.create(x, (bottom + top) / 2, 0),
		size = vector.create(depth, top - bottom, WIDTH),
		tilt = 0,
	}
end

return function (): (boolean, string | nil)
	local Step: any = Environment.load(STEP)
	local Mantle: any = Environment.load(MANTLE)
	local Math: any = Environment.load(MATH)
	local World: any = Environment.load(WORLD)
	local Constants: any = Environment.load(CONSTANTS)
	local Scene: any = Environment.load(SCENE)
	local Casts: any = Environment.load(COLLISION)

	local settings: any = Scene.settings
	local skin: number = Constants.SKIN
	local resting: number = Math.quantize(FLOOR + skin)
	local underside: number = resting + RISE + settings.standing + SPARE
	local ledgeX: number = FACE + LEDGE_DEPTH / 2

	local collision: any = Casts({
		box("Floor", 0, FLOOR - 2, FLOOR, 60),
		box("Ledge", ledgeX, FLOOR, FLOOR + LEDGE_HEIGHT, LEDGE_DEPTH),
		box("Roof", ledgeX, underside, underside + THICKNESS, LEDGE_DEPTH),
	})

	local function rules(): number
		return math.huge
	end

	local flat: any = table.clone(settings)
	flat.mantleArc = 0
	local arched: any = World.new(settings, SIMULATION_RATE, collision, nil, rules, true)
	local level: any = World.new(flat, SIMULATION_RATE, collision, nil, rules, true)

	-- A standing body a skin from the face, looking at it
	local function body(): any
		local state: any = Scene.state(vector.create(Math.quantize(FACE - settings.radius - skin), resting, 0), true)
		state.facing = EAST
		state.groundHeight = resting

		return state
	end

	local posture: string?, _: number, _: number, rise: number = Mantle.find(body(), arched)
	if posture ~= "Crouch" or rise ~= RISE then
		return false, `Under the roof the arched mantle gave {posture} with a rise of {rise}, not Crouch and {RISE}`
	end

	local levelPosture: string? = Mantle.find(body(), level)
	if levelPosture ~= "Stand" then
		return false, `With no arc the same mantle gave {levelPosture}, where the standing hull fits at the rise`
	end

	-- The arched path runs under the roof crouched and stands on the top, never meeting the roof
	local state: any = body()
	local order: any = {
		number = 1,
		forward = 0,
		right = 0,
		jump = true,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = true, crouch = false, sprint = false, aim = false },
		yaw = EAST,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}

	local ticks: number = math.round(settings.mantleTime / arched.delta)
	for _ = 1, ticks do
		Step.advance(state, order, arched)
		order.number += 1
		order.pressed.jump = false
	end

	if state.mode ~= "Ground" or state.posture ~= "Crouch" then
		return false, `The arched mantle under the roof ended {state.mode} {state.posture}, not on the ground crouched`
	elseif math.abs(state.position.y - (FLOOR + LEDGE_HEIGHT + skin)) > skin / 4 then
		return false, `The arched mantle under the roof ended at {state.position.y}, not a skin over the ledge`
	end

	return true, nil
end
