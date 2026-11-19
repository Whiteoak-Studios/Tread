--[[
    A jump under an overhang that faces down at 45° ends its rise on the
    tick the overhang cuts it short, though the slide along the overhang
    alone would keep half its upward speed, and the body falls the tick after
--]]

--!strict
local Environment = require("../../Environment")

local STEP: string = "src/Step/init.luau"
local CONSTANTS: string = "src/Constants.luau"
local MATH: string = "src/Step/Math.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"

local AT_X: number = -20 -- On the fixture floor, clear of its other parts
local AT_Z: number = 25
local TILT: number = 135 -- Degrees about Z, so the overhang's face looks down and along -X
local CLEARANCE: number = 0.3 -- Studs from the hull's top +X edge to the face, along the face's normal
local FACE_LENGTH: number = 6
local FACE_WIDTH: number = 8
local THICKNESS: number = 1

return function (): (boolean, string | nil)
	local Step: any = Environment.load(STEP)
	local Constants: any = Environment.load(CONSTANTS)
	local Math: any = Environment.load(MATH)
	local Scene: any = Environment.load(SCENE)
	local Casts: any = Environment.load(COLLISION)
	local Geometry: any = Environment.load(GEOMETRY)

	local settings: any = Scene.settings
	local resting: number = Math.quantize(Geometry.floor + Constants.SKIN)
	local radians: number = math.rad(TILT)
	local normal: vector = vector.create(-math.sin(radians), math.cos(radians), 0)

	-- The face lies CLEARANCE along its normal past the hull's top +X edge, which leads into it
	local edge: vector = vector.create(AT_X + settings.radius, resting + settings.standing, AT_Z)
	local face: vector = edge - normal * CLEARANCE
	local parts: { any } = table.clone(Geometry.parts)
	table.insert(parts, {
		name = "Overhang",
		center = face - normal * (THICKNESS / 2),
		size = vector.create(FACE_LENGTH, THICKNESS, FACE_WIDTH),
		tilt = TILT,
	})

	local world: any = Scene.world(Casts(parts))
	local jumper: any = Scene.state(vector.create(AT_X, resting, AT_Z), true)
	local press: any = {
		number = 1,
		forward = 0,
		right = 0,
		jump = true,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = true, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}

	Step.advance(jumper, press, world)

	local hit: number = jumper.position.y
	local rise: number = settings.jump * world.delta
	if hit - resting >= rise then
		return false, `The jump rose {hit - resting} studs, its whole tick, through the overhang`
	elseif jumper.velocity.y ~= 0 then
		return false, `The jump's tick under the overhang left an upward speed of {jumper.velocity.y}`
	elseif not (jumper.velocity.x < 0) then
		return false, `The overhang should push the body back along -X, and its velocity's x is {jumper.velocity.x}`
	end

	press.number += 1
	press.jump = false
	press.pressed.jump = false
	Step.advance(jumper, press, world)

	if not (jumper.position.y < hit) then
		return false, `The tick after the overhang cut the jump it stood at {jumper.position.y}, not under {hit}`
	end

	return true, nil
end
