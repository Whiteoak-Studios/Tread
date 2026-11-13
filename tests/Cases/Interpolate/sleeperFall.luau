--[[
    A sleeper record at a new place for the same life is a move, drawn as a
    fall under step.gravity from the block's relay tick: where it lay until
    the render time reaches the tick, along Math.fall after, its yaw on the
    shortest arc by the fall's fraction, then at the new place. The move's
    reveal repeating changes nothing, and a level move shows at its tick
--]]

--!strict
local Environment = require("../../Environment")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local MATH: string = "src/Step/Math.luau"
local SLOT: number = 30
local GENERATION: number = 2
local FIRST: number = 10 -- The tick the sleeper is first revealed lying
local MOVED: number = 14 -- The tick the move's reveal first rides
local LAST: number = 40 -- The last tick sent before the level move
local LEVEL: number = 50 -- The level move's tick
local REPEATS: number = 3 -- Blocks each reveal repeats on after its first, until acknowledged
local AFTER_LEVEL: number = 60 -- The last tick sent after it
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local FROM: vector = vector.create(0, 20, 0)
local TO: vector = vector.create(4, 4, 2)
local BESIDE: vector = vector.create(10, 4, 2) -- The level move's place, at TO's height
local FROM_YAW: number = 0.2 -- Radians, so the shortest arc to TO_YAW crosses 0
local TO_YAW: number = -0.2
local CLOSE: number = 1e-3 -- Studs or radians a drawn value may sit off its expected one
local TURN: number = 2 * math.pi
local DURING: number = 3 -- The fewest render times inside the fall the case must draw

-- The signed shorter way round from b to a, radians
local function arc(a: number, b: number): number
	return (a - b + math.pi) % TURN - math.pi
end

return function (): (boolean, string | nil)
	local Math: any = Environment.load(MATH)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local word: number = viewer.word({ posture = "Downed" })

	-- A block of the sleeper's: its reveal and record at a place while that reveal is unacknowledged, else empty
	local function block(tick: number, from: number, at: vector, yaw: number): { [string]: any }
		if tick < from or tick > from + REPEATS then
			return { tick = tick }
		end

		return {
			tick = tick,
			reveals = { { slot = SLOT, generation = GENERATION, kind = "Sleeper" } },
			records = { { slot = SLOT, generation = GENERATION, position = at, yaw = yaw, word = word } },
		}
	end

	-- Whether the sleeper is drawn at a place and yaw, and why not
	local function at(place: vector, yaw: number): string?
		local drawn: boolean, state: any = viewer.pose(SLOT)
		if not drawn then
			return "The sleeper drew nothing"
		elseif vector.magnitude(state.position - place) > CLOSE or math.abs(arc(state.facing, yaw)) > CLOSE then
			local where: string = `{state.position} facing {state.facing}`
			return `At render time {Interpolate.renderTime()} the sleeper lay at {where}, not {place} facing {yaw}`
		elseif state.posture ~= "Downed" or state.velocity ~= vector.zero then
			return "The falling sleeper wasn't drawn lying at rest"
		end

		return nil
	end

	viewer.announce(SLOT, GENERATION, "A")

	for tick: number = FIRST, FIRST + REPEATS do
		viewer.send(block(tick, FIRST, FROM, FROM_YAW))
	end

	Interpolate.frame(0)

	-- 1) The move's reveal, repeated until acknowledged, then the render time running through the fall
	local before: number, during: number, landed: number = 0, 0, 0
	for tick: number = MOVED, LAST do
		viewer.send(block(tick, MOVED, TO, TO_YAW))
		Interpolate.frame(FRAME)

		local render: number = Interpolate.renderTime()
		local place: vector, fraction: number =
			Math.fall(FROM, TO, viewer.gravity, (render - MOVED) / viewer.rates.relay)
		if render < MOVED then
			place, fraction = FROM, 0
			before += 1
		elseif fraction < 1 then
			during += 1
		else
			landed += 1
		end

		local problem: string? = at(place, FROM_YAW + arc(TO_YAW, FROM_YAW) * fraction)
		if problem then
			return false, problem
		end
	end

	if before == 0 or during < DURING or landed == 0 then
		return false, `The case drew {before} times before the fall, {during} during it and {landed} after`
	elseif #viewer.reveals ~= 1 then
		return false, `The sleeper's reveals and their repeats told {#viewer.reveals} reveals, not 1`
	end

	-- 2) A move to a place no lower shows at once, at its own tick and not before
	local early: number, shown: number = 0, 0
	for tick: number = LAST + 1, AFTER_LEVEL do
		viewer.send(block(tick, LEVEL, BESIDE, TO_YAW))
		Interpolate.frame(FRAME)

		local place: vector = BESIDE
		if Interpolate.renderTime() < LEVEL then
			place = TO
			early += 1
		else
			shown += 1
		end

		local problem: string? = at(place, TO_YAW)
		if problem then
			return false, problem
		end
	end

	if early == 0 or shown == 0 then
		return false, `The level move was drawn {early} times before its tick and {shown} after`
	end

	return true, nil
end
