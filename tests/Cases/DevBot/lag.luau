--[[
    A lagged bot holds each Move its lag in ticks and then sends it in the
    order made, numbering its commands that much further ahead so they
    still reach their ticks, and stops sending held Moves once destroyed
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local LAG: number = 3
local TICKS: number = 10
local SEED: number = 1

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local side: Harness.Side = Harness.side()
	local context: any = harness.context
	local faults: any = { lag = LAG, loss = 0, cheat = nil }
	local bot: any = harness.Bot.new(side.network, context, function () end, faults, SEED)

	for tick: number = 1, LAG do
		bot:tick(tick)
	end

	if #side.fired ~= 0 then
		return false, `A bot lagged {LAG} ticks fired {#side.fired} Moves in its first {LAG} ticks`
	end

	for tick: number = LAG + 1, TICKS do
		bot:tick(tick)
	end

	-- Each tick's Move goes LAG ticks after it was made, in order, and the last LAG still wait
	if #side.fired ~= TICKS - LAG or bot:measure().held ~= TICKS then
		return false, `After {TICKS} ticks {#side.fired} Moves went and {bot:measure().held} were held`
	end

	for index: number, fired: Harness.Fired in side.fired do
		local made: number = index -- The tick the Move was made on
		if fired.command ~= made + context.lead + LAG then
			return false, `The Move made on tick {made} carried command {fired.command}`
		end
	end

	bot:destroy()

	local before: number = #side.fired
	local ok: boolean = pcall(bot.tick, bot, TICKS + LAG)
	if ok or #side.fired ~= before then
		return false, "A destroyed bot ticked, or sent the Moves it still held"
	end

	return true, nil
end
