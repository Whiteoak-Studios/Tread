--[[
    A rise a ceiling cuts short ends on that tick: a jump from the ground and
    a rise in the air into one keep no upward speed and are lower the tick
    after, while the same jump in the open keeps its whole speed
--]]

--!strict
local Environment = require("../../Environment")

local STEP: string = "src/Step/init.luau"
local CONSTANTS: string = "src/Constants.luau"
local MATH: string = "src/Step/Math.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"

local UNDER_X: number = -20 -- On the fixture floor, clear of its other parts, where the ceiling goes
local UNDER_Z: number = 25
local OPEN_Z: number = 10 -- The same floor with nothing over it
local HEADROOM: number = 0.6 -- Studs from a standing head to the ceiling, under one tick of a jump's rise
local FLIGHT_ROOM: number = 0.3 -- Studs from the rising body's head to the ceiling
local FLIGHT_SPEED: number = 15 -- Studs a second the body in the air rises at
local CEILING_SIZE: number = 8
local CEILING_THICKNESS: number = 1

-- A command with no input, numbered 1, a jump pressed on it when asked
local function newCommand(jump: boolean): any
	return {
		number = 1,
		forward = 0,
		right = 0,
		jump = jump,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = jump, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

return function (): (boolean, string | nil)
	local Step: any = Environment.load(STEP)
	local Constants: any = Environment.load(CONSTANTS)
	local Math: any = Environment.load(MATH)
	local Scene: any = Environment.load(SCENE)
	local Casts: any = Environment.load(COLLISION)
	local Geometry: any = Environment.load(GEOMETRY)

	local settings: any = Scene.settings
	local skin: number = Constants.SKIN
	local resting: number = Math.quantize(Geometry.floor + skin)
	local underside: number = resting + settings.standing + HEADROOM

	local parts: { any } = table.clone(Geometry.parts)
	table.insert(parts, {
		name = "LowRoof",
		center = vector.create(UNDER_X, underside + CEILING_THICKNESS / 2, UNDER_Z),
		size = vector.create(CEILING_SIZE, CEILING_THICKNESS, CEILING_SIZE),
		tilt = 0,
	})

	local world: any = Scene.world(Casts(parts))
	local rise: number = settings.jump * world.delta

	-- 1) A jump from the ground into the roof: its hull stops a skin under it with no upward speed, then falls
	local jumper: any = Scene.state(vector.create(UNDER_X, resting, UNDER_Z), true)
	local press: any = newCommand(true)
	Step.advance(jumper, press, world)

	local hit: number = jumper.position.y
	local head: number = hit + settings.standing
	if jumper.velocity.y ~= 0 then
		return false, `The jump's tick into the roof left an upward speed of {jumper.velocity.y}`
	elseif hit >= resting + rise then
		return false, `The jump rose to {hit}, its whole tick, through a roof {HEADROOM} studs over its head`
	elseif head > underside - skin + Constants.POSITION_QUANTUM or head < underside - 2 * skin then
		return false, `The jump's head stopped at {head}, not a skin under the roof at {underside}`
	end

	press.number += 1
	press.pressed.jump = false
	Step.advance(jumper, press, world)
	if not (jumper.position.y < hit) then
		return false, `The tick after the jump hit the roof it stood at {jumper.position.y}, not under {hit}`
	end

	-- 2) A rise in the air into the same roof, from below it, the same way
	local flier: any = Scene.state(vector.create(UNDER_X, underside - settings.standing - FLIGHT_ROOM, UNDER_Z), false)
	flier.velocity = vector.create(0, FLIGHT_SPEED, 0)
	local still: any = newCommand(false)
	local from: number = flier.position.y
	Step.advance(flier, still, world)

	local reached: number = flier.position.y
	if flier.velocity.y ~= 0 then
		return false, `The rise into the roof left an upward speed of {flier.velocity.y}`
	elseif reached - from >= FLIGHT_ROOM then
		return false, `The rise went {reached - from} studs up, past the roof {FLIGHT_ROOM} studs over its head`
	end

	still.number += 1
	Step.advance(flier, still, world)
	if not (flier.position.y < reached) then
		return false, `The tick after the rise hit the roof it stood at {flier.position.y}, not under {reached}`
	end

	-- 3) The same jump with nothing over it rises its whole tick at its whole speed, and on up the next
	local open: any = Scene.state(vector.create(UNDER_X, resting, OPEN_Z), true)
	local openPress: any = newCommand(true)
	Step.advance(open, openPress, world)

	local jumped: number = open.position.y
	if open.velocity.y ~= settings.jump or jumped ~= Math.quantize(resting + rise) then
		return false,
			`The open jump moved to {jumped} at {open.velocity.y}, where its whole tick and speed was expected`
	end

	openPress.number += 1
	openPress.pressed.jump = false
	Step.advance(open, openPress, world)

	local falling: number = Math.quantizeVelocity(settings.jump - settings.gravity * world.delta)
	if not (open.position.y > jumped) or open.velocity.y ~= falling then
		return false,
			`The open jump's second tick moved to {open.position.y} at {open.velocity.y}, not on up at {falling}`
	end

	return true, nil
end
