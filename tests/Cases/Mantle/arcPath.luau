--[[
    The mantle's path arches over the top, at Frontier Zero's values and with
    the arc at 0: no move ahead below the rise, a peak at the rise and the
    arc, the end on the last tick, each tick's velocity its move over a tick,
    and no turn of a right angle or more between two ticks' moves
--]]

--!strict
local Environment = require("../../Environment")

local COURSE: string = "tests/Fixtures/Step/Course.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local MANTLE: string = "src/Step/Mantle.luau"
local MATH: string = "src/Step/Math.luau"
local WORLD: string = "src/Step/World.luau"

local RISE: number = 4.03125 -- A 4-stud reach's rise from feet resting on the course floor, at 1100.01953125
local TICKS: number = 10 -- Frontier Zero's 0.5 s mantle at 20 Hz
local RIGHT_ANGLE: number = 90
local DEGREES: number = 180 / math.pi

-- The angle in degrees between two moves
local function turn(a: vector, b: vector): number
	local lengths: number = math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) * math.sqrt(b.x * b.x + b.y * b.y + b.z * b.z)
	local cosine: number = math.clamp((a.x * b.x + a.y * b.y + a.z * b.z) / lengths, -1, 1)

	return math.acos(cosine) * DEGREES
end

--[[
    Mantles the course's exact row in a world and checks the path tick by
    tick. Gives back why it failed, or nil, with the largest turn between
    two ticks' moves and the tick the feet peak on
--]]

local function walkPath(Course: any, Mantle: any, Math: any, world: any, arc: number): (string?, number, number)
	local row: any = Course.rows.exact
	local state: any = Course.state(vector.create(Course.approach, Course.resting, row.center.z), true)
	state.facing = Course.east

	local start: number = state.position.y
	local ending: vector? = Mantle.ending(state, world)
	local posture: string?, x: number, z: number, rise: number = Mantle.find(state, world)
	if posture ~= "Stand" or rise ~= RISE or ending == nil then
		return `the search gave {posture} with a rise of {rise}, where Stand and {RISE} were expected`, 0, 0
	elseif ending.y ~= start + RISE then
		return `the path's end stood {ending.y - start} over the start, not the rise`, 0, 0
	end

	local order: any = Course.command()
	order.yaw = Course.east
	order.jump, order.pressed.jump = true, true

	local places: { vector } = { vector.create(x, start, z) }
	local delta: number = world.delta
	for tick: number = 1, TICKS - 1 do
		Course.advance(state, world, order, 1)
		if state.mode ~= "Mantle" then
			return `the path left Mantle on its tick {tick}`, 0, 0
		end

		local at: vector = state.position
		local move: vector = at - places[#places]
		local velocity: vector = state.velocity
		if
			velocity.x ~= Math.quantizeVelocity(move.x / delta)
			or velocity.y ~= Math.quantizeVelocity(move.y / delta)
			or velocity.z ~= Math.quantizeVelocity(move.z / delta)
		then
			return `the velocity on tick {tick} was {velocity}, not its move {move} over a tick`, 0, 0
		end

		table.insert(places, at)
	end

	Course.advance(state, world, order, 1)
	if state.mode ~= "Ground" or state.posture ~= "Stand" then
		return `the path ended in {state.mode} {state.posture}, not standing on the ground`, 0, 0
	elseif state.position.x ~= ending.x or state.position.z ~= ending.z then
		return `the path ended at {state.position}, where the search put its end at {ending}`, 0, 0
	end

	-- The last tick's own place, before the ground snap stood the feet on the top
	table.insert(places, ending)

	local peak: number, peakTick: number = -math.huge, 0
	local largest: number = 0
	for tick: number = 1, #places - 1 do
		local at: vector = places[tick + 1]
		local up: number = at.y - start
		if up < RISE and (at.x ~= x or at.z ~= z) then
			return `the feet went ahead to {at} on tick {tick}, {up} over the start, below the rise`, 0, 0
		elseif up > peak then
			peak, peakTick = up, tick
		end

		if tick > 1 then
			largest = math.max(largest, turn(places[tick] - places[tick - 1], at - places[tick]))
		end
	end

	local top: number = Math.quantize(RISE + arc)
	if peak ~= top then
		return `the feet peaked {peak} over the start, where the rise and the arc make {top}`, 0, 0
	elseif not (largest < RIGHT_ANGLE) then
		return `the path turned {largest}° between two ticks, a right angle or more`, 0, 0
	end

	return nil, largest, peakTick
end

return function (): (boolean, string | nil)
	local Course: any = Environment.load(COURSE)
	local Casts: any = Environment.load(COLLISION)
	local Mantle: any = Environment.load(MANTLE)
	local Math: any = Environment.load(MATH)
	local World: any = Environment.load(WORLD)

	if Course.ticks ~= TICKS then
		return false, `the course's mantle runs {Course.ticks} ticks, where Frontier Zero's {TICKS} were expected`
	end

	local arched: any = Course.world()
	local failure: string?, _: number, peakTick: number =
		walkPath(Course, Mantle, Math, arched, Course.settings.mantleArc)
	if failure then
		return false, `At Frontier Zero's arc: {failure}`
	elseif peakTick <= 1 or peakTick >= TICKS then
		return false, `At Frontier Zero's arc the feet peaked on tick {peakTick}, not inside the path`
	end

	-- The same path with no arc keeps to the rise once it is over the top
	local flat: any = table.clone(Course.settings)
	flat.mantleArc = 0
	local level: any = World.new(flat, 1 / arched.delta, Casts(Course.parts), Course.water, function (): number
		return math.huge
	end, true)

	local levelFailure: string? = walkPath(Course, Mantle, Math, level, 0)
	if levelFailure then
		return false, `With no arc: {levelFailure}`
	end

	return true, nil
end
