--[[
    Under budgets of 0, stats gives each cap's count as its change since the
    last read: the NPCs that waited, a slice cut, the viewer turns left, the
    runs over and the runs lowered, worked out by hand, and 0 read again
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local UNDER_LOAD: { runs: number, scale: number } = { runs = 2, scale = 0.5 }
local BASE: number = 1000 -- Seconds, anti-ESP's stand-in clock's first reading
local LATE: number = 100 -- Seconds the stand-in moves at each read while a slice is cut, past the rig's 60 s slice

-- Each bot's x and z, clear of the fixture's obstacles, eight turn viewers, so a relay budget of 0 leaves a quarter,
-- two, every run; and three NPCs, which a budget of 0 makes wait together on alternate ticks from the first
local BOTS: { { number } } = {
	{ -24, -6 },
	{ -18, -6 },
	{ -12, -6 },
	{ -6, -6 },
	{ -24, 6 },
	{ -18, 6 },
	{ -12, 6 },
	{ -6, 6 },
}
local NPCS: { { number } } = { { 2, -12 }, { 2, 0 }, { 2, 12 } }

-- One read's expected counts, after its ticks
type Expected = {
	ticks: number,
	npcsWaited: number,
	antiEspCut: number,
	relayLeft: number,
	relayOver: number,
	farHalved: number,
}

local FIELDS: { string } = { "ticks", "npcsWaited", "antiEspCut", "relayLeft", "relayOver", "farHalved" }

-- Tick 1: the NPCs wait, two turns left in a run over. Tick 2: the NPCs step and its slice is cut, and its run, the
-- second over, lowers the farthest band. Ticks 3 to 5: the NPCs wait on 3 and 5, and three runs taken lowered
local READS: { Expected } = {
	{ ticks = 1, npcsWaited = 3, antiEspCut = 0, relayLeft = 2, relayOver = 1, farHalved = 0 },
	{ ticks = 1, npcsWaited = 0, antiEspCut = 1, relayLeft = 2, relayOver = 1, farHalved = 0 },
	{ ticks = 3, npcsWaited = 6, antiEspCut = 0, relayLeft = 6, relayOver = 3, farHalved = 3 },
}

-- A read with nothing since the last
local NONE: Expected = { ticks = 0, npcsWaited = 0, antiEspCut = 0, relayLeft = 0, relayOver = 0, farHalved = 0 }

local CUT: number = 2 -- The read whose ticks run with anti-ESP's stand-in clock late at every read

-- Why a read's counts differ from those expected, or nil when each matches
local function mismatch(read: any, expected: any, label: string): string?
	for _, name: string in FIELDS do
		if read[name] ~= expected[name] then
			return `{label} gave {name} {read[name]}, not {expected[name]}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.npcs.budget = 0
		settings.relay = { changes = true, budget = 0 }
		settings.tiers.underLoad = UNDER_LOAD
	end)

	-- Anti-ESP's own environment holds the os its start takes its clock from, so the stand-in is put there first
	local AntiEsp: any = rig:require(rig.tread.Server.AntiEsp)
	local clock: { now: number, step: number } = { now = BASE, step = 0 }
	local scope: any = getfenv(AntiEsp.start)
	scope.os = {
		clock = function (): number
			local now: number = clock.now
			clock.now += clock.step

			return now
		end,
	}

	local server: any = rig:start()
	for index: number, at: { number } in BOTS do
		server:create(rig.mock:addBot(`Bot{index}`), rig:at(at[1], at[2]))
	end

	for _, at: { number } in NPCS do
		server:createNpc(rig:at(at[1], at[2]))
	end

	local opened: string? = mismatch(server:stats(), NONE, "The read before any tick")
	if opened then
		return false, opened
	end

	for index: number, expected: Expected in READS do
		if index == CUT then
			clock.step = LATE
		end

		rig:tick(expected.ticks)
		clock.step = 0

		local wrong: string? = mismatch(server:stats(), expected, `Read {index}`)
		if wrong then
			return false, wrong
		end
	end

	-- Straight after another read, with nothing between, every count is 0
	local again: string? = mismatch(server:stats(), NONE, "A read straight after another")
	if again then
		return false, again
	end

	return true, nil
end
