--[[
    A sleeper's fall is drawn under the gravity the client's world gives each
    render tick, two u16 wraps into the server's ticks: an 18-stud drop under
    68.1 changed to 30 from 8 ticks after its move follows Math.fall under
    68.1 before that tick and under 30 from it, so it jumps up across the
    change and lands later, and a move after the change falls under 30
--]]

--!strict
local Environment = require("../../Environment")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local MATH: string = "src/Step/Math.luau"
local SLOT: number = 30
local GENERATION: number = 2
local WIRE: number = 2 ^ 16
local SERVER: number = 2 * WIRE -- The server's tick at the render clock's tick 0, past two wraps of the wire's u16
local FIRST: number = 10 -- The tick the sleeper is first revealed lying
local MOVED: number = 14 -- The tick the first move's reveal first rides
local CHANGE_AFTER: number = 8 -- Ticks after the move the gravity changes from, 0.4 s at 20 Hz
local AGAIN: number = 45 -- The tick the second move's reveal first rides, the first fall long done
local LAST: number = 80 -- The last tick sent
local REPEATS: number = 3 -- Blocks each reveal repeats on after its first, until acknowledged
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local CHANGED: number = 30 -- Studs/s², the gravity the change sets
local HIGH: vector = vector.create(0, 22, 0)
local LOW: vector = vector.create(0, 4, 0) -- 18 studs under HIGH
local LOWER: vector = vector.create(6, -14, 0) -- 18 studs under LOW
local CLOSE: number = 1e-3 -- Studs a drawn place may sit off its expected one
local DURING: number = 3 -- The fewest render times inside each stretch the case must draw

return function (): (boolean, string | nil)
	local Math: any = Environment.load(MATH)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local world: any = viewer.world
	local word: number = viewer.word({ posture = "Downed" })
	local relay: number = viewer.rates.relay
	local base: number = viewer.gravity
	local changeAt: number = MOVED + CHANGE_AFTER

	-- A block of the sleeper's: its reveal and record at a place while that reveal is unacknowledged, else empty
	local function block(tick: number, from: number, at: vector): { [string]: any }
		if tick < from or tick > from + REPEATS then
			return { tick = tick }
		end

		return {
			tick = tick,
			reveals = { { slot = SLOT, generation = GENERATION, kind = "Sleeper" } },
			records = { { slot = SLOT, generation = GENERATION, position = at, yaw = 0, word = word } },
		}
	end

	-- One tick: the clock where the handle would hold it, the block, then a frame
	local function step(tick: number, from: number, at: vector)
		world.clock = SERVER + tick
		viewer.send(block(tick, from, at))
		Interpolate.frame(FRAME)
	end

	-- Where the sleeper is drawn, or why it isn't drawn at all
	local function drawn(): (vector?, string?)
		local shown: boolean, state: any = viewer.pose(SLOT)
		if not shown then
			return nil, "The sleeper drew nothing"
		end

		return state.position, nil
	end

	viewer.announce(SLOT, GENERATION, "A")
	for tick: number = FIRST, FIRST + REPEATS do
		step(tick, FIRST, HIGH)
	end

	-- The change from its tick on, heard before the render clock reaches it
	viewer.World.setGravity(world, CHANGED, SERVER + changeAt)

	-- 1) The first fall: under 68.1 before the change's tick and 30 from it, at rest only once 30's fall is done
	local before: number, after: number, late: number = 0, 0, 0
	local lastBefore: number?, firstAfter: number? = nil, nil
	for tick: number = MOVED, AGAIN - 1 do
		step(tick, MOVED, LOW)

		local render: number = Interpolate.renderTime()
		local elapsed: number = (render - MOVED) / relay
		local under: number = base
		if render >= changeAt then
			under = CHANGED
		end

		local place: vector, fraction: number = Math.fall(HIGH, LOW, under, elapsed)
		local at: vector?, problem: string? = drawn()
		if not at then
			return false, `On the first fall: {problem}`
		elseif vector.magnitude(at - place) > CLOSE then
			return false, `At render time {render} the sleeper lay at {at}, not {place} under {under}`
		end

		local _, baseFraction: number = Math.fall(HIGH, LOW, base, elapsed)
		if elapsed > 0 and fraction < 1 and under == base then
			before += 1
			lastBefore = at.y
		elseif fraction < 1 and under == CHANGED then
			after += 1
			if firstAfter == nil then
				firstAfter = at.y
			end

			if baseFraction >= 1 then
				late += 1
			end
		end
	end

	if before < DURING or after < DURING or late < DURING then
		return false, `The first fall drew {before} times before the change, {after} after and {late} past {base}'s end`
	elseif not lastBefore or not firstAfter or firstAfter <= lastBefore then
		return false, `The sleeper went from {lastBefore} to {firstAfter} studs up across the change, not up`
	end

	-- 2) A move after the change falls under its gravity from the start
	local during: number = 0
	for tick: number = AGAIN, LAST do
		step(tick, AGAIN, LOWER)

		local render: number = Interpolate.renderTime()
		local place: vector, fraction: number = Math.fall(LOW, LOWER, CHANGED, (render - AGAIN) / relay)
		local at: vector?, problem: string? = drawn()
		if not at then
			return false, `On the second fall: {problem}`
		elseif vector.magnitude(at - place) > CLOSE then
			return false, `At render time {render} the second fall lay at {at}, not {place} under {CHANGED}`
		end

		if render > AGAIN and fraction < 1 then
			during += 1
		end
	end

	if during < DURING then
		return false, `The second fall was drawn {during} times inside it`
	end

	return true, nil
end
