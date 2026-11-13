--[[
    A body no write names, such as an idle NPC, keeps its last sample for
    every time since, and when its writes resume the ticks between hold
    that sample; a tick spent in Noclip or Parked is one no read finds
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local IDLE: number = 5 -- Slots: an NPC that idles, one that keeps stepping, and one that flies in Noclip
local AWAKE: number = 6
local FLYER: number = 8
local STOPPED: number = 10 -- The idle NPC's last tick before it idles
local NEWEST: number = 30 -- The awake body's last tick before the idle NPC wakes
local WOKE: number = 35 -- The idle NPC's first tick after
local FLYER_FIRST: number = 21
local NOCLIP_FIRST: number = 24 -- The flyer's Noclip stretch, then its one Parked tick
local NOCLIP_LAST: number = 26
local PARKED: number = 27

type Read = { slot: number, time: number, x: number? }

-- Why any read differs from what it should be, or nil when each matches
local function check(History: any, reads: { Read }): string?
	for _, read: Read in reads do
		local sample = History.sampleAt(read.slot, read.time)
		local got: number? = sample and sample.position.x

		if got ~= read.x then
			return `Slot {read.slot} at {read.time} read x {got}, where {read.x} was due`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())

	local state = State.new()

	for tick: number = 1, NEWEST do
		state.position = vector.create(tick, 0, 0)
		History.write(AWAKE, tick, state, 0)

		if tick <= STOPPED then
			History.write(IDLE, tick, state, 0)
		end

		if tick >= FLYER_FIRST then
			if tick >= NOCLIP_FIRST and tick <= NOCLIP_LAST then
				state.moveMode = "Noclip"
			elseif tick == PARKED then
				state.moveMode = "Parked"
			end

			History.write(FLYER, tick, state, 0)
			state.moveMode = "Walk"
		end
	end

	local failure: string? = check(History, {
		{ slot = IDLE, time = 25, x = STOPPED }, -- Idle since tick 10, the history's oldest end
		{ slot = IDLE, time = NEWEST + 0.5, x = STOPPED },
		{ slot = IDLE, time = 9.5, x = nil }, -- Older than the history holds
		{ slot = FLYER, time = 23, x = 23 },
		{ slot = FLYER, time = 23.5, x = nil }, -- Into the Noclip stretch
		{ slot = FLYER, time = 25, x = nil },
		{ slot = FLYER, time = PARKED, x = nil },
		{ slot = FLYER, time = PARKED + 0.5, x = nil }, -- Out of the Parked tick
		{ slot = FLYER, time = 28.5, x = 28.5 },
		{ slot = FLYER, time = NEWEST, x = NEWEST },
	})

	if failure then
		return false, failure
	end

	-- The idle NPC wakes, and its ticks back to the history's oldest end hold its last sample
	for tick: number = NEWEST + 1, WOKE do
		state.position = vector.create(tick, 0, 0)
		History.write(AWAKE, tick, state, 0)
	end

	History.write(IDLE, WOKE, state, 0)

	failure = check(History, {
		{ slot = IDLE, time = 15, x = STOPPED },
		{ slot = IDLE, time = 20.5, x = STOPPED },
		{ slot = IDLE, time = WOKE - 1, x = STOPPED },
		{ slot = IDLE, time = WOKE - 0.5, x = (STOPPED + WOKE) / 2 },
		{ slot = IDLE, time = WOKE, x = WOKE },
		{ slot = IDLE, time = 14.5, x = nil },
	})

	if failure then
		return false, failure
	end

	return true, nil
end
