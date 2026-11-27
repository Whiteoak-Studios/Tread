--[[
    A lossy bot drops about its share of Moves, the same ones for the same
    seed and others for another, and every Move it does not drop is sent
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local TICKS: number = 400
local LOSS: number = 0.25
local SPREAD: number = 0.08 -- How far from the loss the share dropped may land over TICKS Moves
local SEED: number = 7
local OTHER_SEED: number = 8

-- The ticks a bot of that seed lost its Move on, and how many it sent
local function lost(harness: Harness.Loaded, seed: number): ({ number }, number, number)
	local side: Harness.Side = Harness.side()
	local faults: any = { lag = 0, loss = LOSS, cheat = nil }
	local bot: any = harness.Bot.new(side.network, harness.context, function () end, faults, seed)
	local ticks: { number } = {}
	local dropped: number = 0

	for tick: number = 1, TICKS do
		bot:tick(tick)

		if bot:measure().dropped > dropped then
			dropped = bot:measure().dropped
			table.insert(ticks, tick)
		end
	end

	bot:destroy()

	return ticks, #side.fired, bot:measure().sent
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()

	local ticks: { number }, fired: number, sent: number = lost(harness, SEED)
	local again: { number } = lost(harness, SEED)
	local other: { number } = lost(harness, OTHER_SEED)
	local share: number = #ticks / TICKS

	if math.abs(share - LOSS) > SPREAD then
		return false, `A bot losing {LOSS} of its Moves lost {share} of {TICKS}`
	elseif fired + #ticks ~= TICKS or sent ~= fired then
		return false, `Of {TICKS} Moves {fired} were fired and {#ticks} lost, and the bot counted {sent} sent`
	elseif table.concat(again, ",") ~= table.concat(ticks, ",") then
		return false, "The same seed lost other Moves"
	elseif table.concat(other, ",") == table.concat(ticks, ",") then
		return false, "Another seed lost the very same Moves"
	end

	return true, nil
end
