--[[
    A death gives the dying life's newest record's age in seconds, by the
    newest tick the clock estimates when it arrives, and an infinite age
    for a life this viewer was never sent a record of
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local DRAWN: number = 50
local UNSEEN: number = 51
local GENERATION: number = 1
local BODY: number = 60
local UNSEEN_BODY: number = 61
local FIRST: number = 10
local NEWEST: number = 12 -- The dying life's newest record's tick
local LATER: number = 15 -- A later block with nothing of the dying life in it
local WAIT: number = 0.5 -- Seconds of frames after that block before the death arrives
local CLOSE: number = 1e-9

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local Record: any = viewer.Record

	for _, slot: number in { DRAWN, UNSEEN, BODY, UNSEEN_BODY } do
		viewer.announce(slot, GENERATION, "A")
	end

	for tick: number = FIRST, NEWEST do
		local reveals: { any }? = nil
		if tick == FIRST then
			reveals = { { slot = DRAWN, generation = GENERATION, kind = "Player" } }
		end

		viewer.send({
			tick = tick,
			reveals = reveals,
			records = { { slot = DRAWN, generation = GENERATION, position = vector.create(tick, 0, 0) } },
		})
	end

	viewer.send({ tick = LATER })
	Interpolate.frame(WAIT)

	-- The clock estimates the newest tick as the later block's and the relay ticks since it came
	local expected: number = (LATER + WAIT * viewer.rates.relay - NEWEST) / viewer.rates.relay
	local _, _, _, age: number = Interpolate.death(Record.id(DRAWN, GENERATION), Record.id(BODY, GENERATION), 0, 0, 0)
	if math.abs(age - expected) > CLOSE then
		return false, `The death gave an age of {age} s, not {expected}`
	end

	local _, _, _, never: number =
		Interpolate.death(Record.id(UNSEEN, GENERATION), Record.id(UNSEEN_BODY, GENERATION), 0, 0, 0)
	if never ~= math.huge then
		return false, `A death of a life never sent gave an age of {never} s`
	end

	return true, nil
end
