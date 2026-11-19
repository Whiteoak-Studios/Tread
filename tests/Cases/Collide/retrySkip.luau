--[[
    A walk makes no step up when every surface too steep to walk it met was
    a live hull topping out past a step above its feet, ending where it did
    with one, and keeps it for walls and for a hull a step can clear
--]]

--!strict
local Environment = require("../../Environment")

local COLLIDE: string = "src/Step/Collide.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local MATH: string = "src/Step/Math.luau"
local CONSTANTS: string = "src/Constants.luau"
local LEDGE_TOP: number = 4.7 -- Under a standing hull's top by less than a step, so a hull below it is stepped onto
local HULL_GAP: number = 0.3 -- Studs from the walker's hull to the first surface a one-tick walk meets
local WALL_GAP: number = 0.6 -- Studs from it to the second, which the slide along the first then meets
local THICKNESS: number = 1 -- A wall's

-- A part as the fixture casts take it
type Part = {
	name: string,
	center: vector,
	size: vector,
	tilt: number,
}

type Walk = {
	name: string,
	others: { vector }, -- The other live bodies' feet, every one standing
	from: vector, -- The walker's feet
	velocity: vector, -- Its level velocity on the ground each tick
	ticks: number,
	at: vector, -- Where it ends, as it did when every steep hit took the step up
	velocityAt: vector,
	on: number?, -- The other it ends standing on
	lifts: number, -- The step up's lift casts, each straight up
	sweeps: number, -- Every sweep it casts
}

return function (): (boolean, string | nil)
	local Collide: any = Environment.load(COLLIDE)
	local Scene: any = Environment.load(SCENE)
	local Math: any = Environment.load(MATH)
	local Constants: any = Environment.load(CONSTANTS)
	local skin: number = Constants.SKIN
	local radius: number = Scene.settings.radius
	local resting: number = skin -- Feet at rest on the floor, whose top is at 0

	local parts: { Part } = {
		{ name = "Floor", center = vector.create(0, -1, 0), size = vector.create(200, 2, 200), tilt = 0 },
		{ name = "Wall", center = vector.create(20.5, 4, -30), size = vector.create(THICKNESS, 8, 12), tilt = 0 },
		{
			name = "Ledge",
			center = vector.create(-5, LEDGE_TOP / 2, 30),
			size = vector.create(10, LEDGE_TOP, 8),
			tilt = 0,
		},
		{
			name = "Fence",
			center = vector.create(40, 4, 40 + radius + WALL_GAP + THICKNESS / 2),
			size = vector.create(12, 8, THICKNESS),
			tilt = 0,
		},
		{
			name = "Post",
			center = vector.create(70 + radius + HULL_GAP + THICKNESS / 2, 4, 40),
			size = vector.create(THICKNESS, 8, 12),
			tilt = 0,
		},
	}

	-- The fixture casts, counting every sweep and each lift among them
	local sweeps: number = 0
	local lifts: number = 0
	local collision: any = Environment.load(CASTS)(parts)
	local sweep: (center: vector, size: vector, direction: vector) -> any = collision.sweep
	collision.sweep = function (center: vector, size: vector, direction: vector): any
		sweeps += 1
		if direction.x == 0 and direction.z == 0 and direction.y > 0 then
			lifts += 1
		end

		return sweep(center, size, direction)
	end

	local walks: { Walk } = {
		{
			name = "into a standing hull on flat ground",
			others = { vector.create(-20, resting, 0) },
			from = vector.create(-26, resting, 0),
			velocity = vector.create(10, 0, 0),
			ticks = 10,
			at = vector.create(-22.80078125, 0.01953125, 0),
			velocityAt = vector.zero,
			lifts = 0,
			sweeps = 20,
		},
		{
			name = "off a ledge onto a hull whose top is within a step",
			others = { vector.create(radius, resting, 30) },
			from = vector.create(-6, LEDGE_TOP + skin, 30),
			velocity = vector.create(10, 0, 0),
			ticks = 12,
			at = vector.create(0, 5.0390625, 30),
			velocityAt = vector.create(10, 0, 0),
			on = 1,
			lifts = 1,
			sweeps = 27,
		},
		{
			name = "into a wall",
			others = {},
			from = vector.create(15, resting, -30),
			velocity = vector.create(10, 0, 0),
			ticks = 12,
			at = vector.create(18.58984375, 0.01953125, -30),
			velocityAt = vector.zero,
			lifts = 5,
			sweeps = 39,
		},
		{
			name = "into a standing hull, then along it into a wall",
			others = { vector.create(40 + 2 * radius + HULL_GAP, resting, 40) },
			from = vector.create(40, resting, 40),
			velocity = vector.create(12, 0, 20),
			ticks = 1,
			at = vector.create(40.279296875, 0.01953125, 40.580078125),
			velocityAt = vector.zero,
			lifts = 1,
			sweeps = 7,
		},
		{
			name = "into a wall, then along it into a standing hull",
			others = { vector.create(70, resting, 40 + 2 * radius + WALL_GAP) },
			from = vector.create(70, resting, 40),
			velocity = vector.create(12, 0, 20),
			ticks = 1,
			at = vector.create(70.279296875, 0.01953125, 40.580078125),
			velocityAt = vector.zero,
			lifts = 1,
			sweeps = 7,
		},
	}

	for _, walk: Walk in walks do
		local state: any = Scene.state(walk.from, true)
		local others: { any } = {}
		for _, feet: vector in walk.others do
			table.insert(others, Scene.state(feet, true))
		end

		local bodies: { any } = table.clone(others)
		table.insert(bodies, state)
		local world: any = Scene.world(collision, bodies)

		-- Each tick quantized, as the step ends
		sweeps, lifts = 0, 0
		local standingOn: any = nil
		for _ = 1, walk.ticks do
			state.velocity = walk.velocity
			standingOn = Collide.move(state, walk.velocity * world.delta, world)

			local at: vector = state.position
			local velocity: vector = state.velocity
			state.position = vector.create(Math.quantize(at.x), Math.quantize(at.y), Math.quantize(at.z))
			state.velocity = vector.create(
				Math.quantizeVelocity(velocity.x),
				Math.quantizeVelocity(velocity.y),
				Math.quantizeVelocity(velocity.z)
			)
		end

		local wantOn: any = walk.on and others[walk.on]
		if state.position ~= walk.at or state.velocity ~= walk.velocityAt or not state.grounded then
			local found: string = `at {state.position} moving {state.velocity}, grounded {state.grounded}`

			return false, `The walk {walk.name} ended {found}, where {walk.at} moving {walk.velocityAt} was expected`
		elseif standingOn ~= wantOn then
			local found: string = `standing on the other {standingOn ~= nil}`

			return false, `The walk {walk.name} ended {found}, where {wantOn ~= nil} was expected`
		elseif lifts ~= walk.lifts or sweeps ~= walk.sweeps then
			local found: string = `{lifts} lifts in {sweeps} sweeps`

			return false, `The walk {walk.name} cast {found}, where {walk.lifts} in {walk.sweeps} were expected`
		end
	end

	return true, nil
end
