--[[
    Bot.new refuses a lag that is not whole ticks from 0, a loss outside
    0 up to 1 and a cheat with no windows, and a destroyed bot disconnects
    every listener and refuses to tick, send or be destroyed again
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local SEED: number = 1

-- Faults no bot may be built with, each with what makes it wrong
local REFUSED: { { faults: any, why: string } } = {
	{ faults = { lag = -1, loss = 0 }, why = "a lag below 0" },
	{ faults = { lag = 1.5, loss = 0 }, why = "a lag of part of a tick" },
	{ faults = { lag = 0, loss = 1 }, why = "a loss of every Move" },
	{ faults = { lag = 0, loss = -0.1 }, why = "a loss below 0" },
	{ faults = { lag = 0, loss = 0 / 0 }, why = "a loss that is no number" },
	{
		faults = {
			lag = 0,
			loss = 0,
			cheat = { kind = "freeze", every = 0, phase = 0, lengths = { 1 }, ahead = { 1 } },
		},
		why = "a cheat whose windows never come round",
	},
	{
		faults = { lag = 0, loss = 0, cheat = { kind = "freeze", every = 10, phase = 0, lengths = {}, ahead = { 1 } } },
		why = "a cheat whose windows have no length",
	},
}

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()

	for _, refused in REFUSED do
		local side: Harness.Side = Harness.side()
		if pcall(harness.Bot.new, side.network, harness.context, nil, refused.faults, SEED) then
			return false, `Bot.new took {refused.why}`
		end
	end

	local side: Harness.Side = Harness.side()
	local bot: any = harness.Bot.new(side.network, harness.context, nil, nil, SEED)

	-- A bot with no program sends nothing of its own
	bot:tick(1)
	if #side.fired ~= 0 then
		return false, `A bot with no program fired {#side.fired} Moves on its tick`
	end

	bot:destroy()

	if next(side.listeners) ~= nil then
		return false, "A destroyed bot left a listener connected"
	elseif pcall(bot.tick, bot, 2) then
		return false, "A destroyed bot ticked"
	elseif pcall(bot.send, bot, {}, 0) then
		return false, "A destroyed bot sent"
	elseif pcall(bot.destroy, bot) then
		return false, "A bot was destroyed twice"
	end

	return true, nil
end
