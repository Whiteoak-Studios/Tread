--[[
    A sleeper moved again while it falls keeps only its newest move, as the
    server's hit test does: the second fall starts from where the first
    puts it at the second move's tick, and lies there from the second's
    arrival until the render time reaches that tick
--]]

--!strict
local Environment = require("../../Environment")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local MATH: string = "src/Step/Math.luau"
local SLOT: number = 31
local GENERATION: number = 1
local FIRST: number = 10
local MOVED: number = 14 -- The first move's tick
local AGAIN: number = 20 -- The second's, while the first still falls
local LAST: number = 45
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local LYING: vector = vector.create(0, 40, 0)
local FIRST_TO: vector = vector.create(0, 0, 0)
local SECOND_TO: vector = vector.create(8, 10, 0)
local CLOSE: number = 1e-3 -- Studs a drawn place may sit off its expected one

return function (): (boolean, string | nil)
	local Math: any = Environment.load(MATH)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local relay: number = viewer.rates.relay
	local word: number = viewer.word({ posture = "Downed" })

	-- Each move's reveal and record ride one block, as the first block carrying a reveal does
	local places: { [number]: vector } = { [FIRST] = LYING, [MOVED] = FIRST_TO, [AGAIN] = SECOND_TO }

	viewer.announce(SLOT, GENERATION, "A")

	local function send(tick: number)
		local place: vector? = places[tick]
		if place == nil then
			viewer.send({ tick = tick })
			return
		end

		viewer.send({
			tick = tick,
			reveals = { { slot = SLOT, generation = GENERATION, kind = "Sleeper" } },
			records = { { slot = SLOT, generation = GENERATION, position = place, word = word } },
		})
	end

	for tick: number = FIRST, MOVED - 1 do
		send(tick)
	end
	Interpolate.frame(0)

	-- Where the first fall puts it at the second move's tick, which the second starts from
	local turned: vector = Math.fall(LYING, FIRST_TO, viewer.gravity, (AGAIN - MOVED) / relay)
	if turned.y >= LYING.y or turned.y <= SECOND_TO.y then
		return false, `The fixture's second move at {AGAIN} doesn't fall from mid-fall, at {turned}`
	end

	local held: number, seconds: number = 0, 0
	for tick: number = MOVED, LAST do
		send(tick)
		Interpolate.frame(FRAME)

		local render: number = Interpolate.renderTime()
		local expected: vector = LYING
		if tick >= AGAIN and render < AGAIN then
			expected = turned
			held += 1
		elseif tick >= AGAIN then
			expected = Math.fall(turned, SECOND_TO, viewer.gravity, (render - AGAIN) / relay)
			seconds += 1
		elseif render >= MOVED then
			expected = Math.fall(LYING, FIRST_TO, viewer.gravity, (render - MOVED) / relay)
		end

		local drawn: boolean, state: any = viewer.pose(SLOT)
		if not drawn or vector.magnitude(state.position - expected) > CLOSE then
			return false, `At render time {render} the sleeper lay at {drawn and state.position}, not {expected}`
		end
	end

	if held == 0 or seconds == 0 then
		return false, `The case drew {held} times before the second move's tick and {seconds} after`
	end

	return true, nil
end
