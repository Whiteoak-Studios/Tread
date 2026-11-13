--[[
    The history holds history.seconds of relay ticks back from the newest
    tick written: 1 s at 20 Hz answers 20 ticks back and nil just past it,
    a slot answers nothing before its first sample, a time past the newest
    answers the newest, and a shorter setting holds less
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local LONG: number = 1 -- Slots
local LATE: number = 2
local NEWEST: number = 40 -- The last relay tick written
local LATE_FIRST: number = 35 -- The late slot's first
local SHORT_SECONDS: number = 0.5

type Read = { time: number, x: number? }

-- Writes the slot from its first tick to the newest, each tick's sample at its tick along X
local function fill(History: any, State: any, slot: number, first: number)
	local state = State.new()

	for tick: number = first, NEWEST do
		state.position = vector.create(tick, 0, 0)
		History.write(slot, tick, state, 0)
	end
end

-- Why a slot's reads differ from what they should be, or nil when each matches
local function check(History: any, slot: number, reads: { Read }): string?
	for _, read: Read in reads do
		local sample = History.sampleAt(slot, read.time)
		local got: number? = sample and sample.position.x

		if got ~= read.x then
			return `Slot {slot} at {read.time} read x {got}, where {read.x} was due`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())

	fill(History, State, LONG, 1)
	fill(History, State, LATE, LATE_FIRST)

	local failure: string? = check(History, LONG, {
		{ time = NEWEST - 20, x = NEWEST - 20 }, -- 1 s back, the oldest end
		{ time = NEWEST - 20.001, x = nil },
		{ time = NEWEST - 19.5, x = NEWEST - 19.5 },
		{ time = NEWEST, x = NEWEST }, -- The newest end
		{ time = NEWEST + 0.75, x = NEWEST }, -- Past it, held and never extrapolated
		{ time = NEWEST + 20, x = NEWEST },
	})

	failure = failure
		or check(History, LATE, {
			{ time = LATE_FIRST - 0.5, x = nil },
			{ time = LATE_FIRST, x = LATE_FIRST },
		})

	if failure then
		return false, failure
	end

	local ShortHistory: any = Environment.load(HISTORY)
	local server = Example.server()
	server.history.seconds = SHORT_SECONDS
	ShortHistory.start(Example.shared(), server)
	fill(ShortHistory, State, LONG, 1)

	failure = check(ShortHistory, LONG, {
		{ time = NEWEST - 10, x = NEWEST - 10 }, -- Half a second back at 20 Hz
		{ time = NEWEST - 10.5, x = nil },
	})

	if failure then
		return false, `With {SHORT_SECONDS} s of history: {failure}`
	end

	return true, nil
end
