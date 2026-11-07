--[[
    A frozen client sends nothing for its window and never sends it later,
    a crouched bot loses its Moves in a row, and each opens its window again
    every so many ticks, at its seeded phase
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local EVERY: number = 20
local PHASE: number = 3
local FREEZE: number = 8
local DROPS: number = 4
local TICKS: number = 60 -- Three windows each
local SEED: number = 1

-- The ticks a bot with one cheat lost its Move on
local function dropped(harness: Harness.Loaded, kind: string, length: number): ({ number }, Harness.Side)
	local side: Harness.Side = Harness.side()
	local cheat: any = { kind = kind, every = EVERY, phase = PHASE, lengths = { length }, ahead = { 1 } }
	local faults: any = { lag = 0, loss = 0, cheat = cheat }
	local bot: any = harness.Bot.new(side.network, harness.context, function () end, faults, SEED)
	local ticks: { number } = {}

	for tick: number = 1, TICKS do
		local before: number = bot:measure().dropped
		bot:tick(tick)

		if bot:measure().dropped > before then
			table.insert(ticks, tick)
		end
	end

	bot:destroy()

	return ticks, side
end

-- The ticks each window of a length drops, from the phase on, every EVERY
local function windows(length: number): string
	local ticks: { number } = {}
	for start: number = PHASE, TICKS, EVERY do
		for tick: number = start, start + length - 1 do
			table.insert(ticks, tick)
		end
	end

	return table.concat(ticks, ",")
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()

	local frozen: { number }, frozenSide: Harness.Side = dropped(harness, "freeze", FREEZE)
	if table.concat(frozen, ",") ~= windows(FREEZE) then
		return false, `A freeze dropped the Moves of ticks {table.concat(frozen, ",")}, not {windows(FREEZE)}`
	elseif #frozenSide.fired + #frozen ~= TICKS then
		return false, `A freeze fired {#frozenSide.fired} Moves and dropped {#frozen} of {TICKS}, so some went later`
	end

	local crouched: { number } = dropped(harness, "crouchLoss", DROPS)
	if table.concat(crouched, ",") ~= windows(DROPS) then
		return false, `A crouched bot lost the Moves of ticks {table.concat(crouched, ",")}, not {windows(DROPS)}`
	end

	return true, nil
end
