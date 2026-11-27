--[[
    A lag switch holds every Move its window covers and lets them all go
    at its end as they were made, a relabeling bot sends its newest commands
    again in their place renumbered ahead, and each hold measures how far
    the server moved the body while it lasted
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local MAX_COMMANDS: number = 8 -- The most commands a Move carries, every one of them in a relabel's
local EVERY: number = 100
local PHASE: number = 10 -- The tick the window opens on
local LENGTH: number = 5 -- Ticks it lasts
local AHEAD: number = 7 -- Ticks past its clock the relabel renumbers by
local CLOSE: number = PHASE + LENGTH
local STEP: number = 0.5 -- Studs the server moves the body each tick of the hold
local SEED: number = 1

-- A bot with one cheat window, ticked past it, with an OwnerState moving its body on along X each tick
local function hold(harness: Harness.Loaded, kind: string): (Harness.Side, any)
	local side: Harness.Side = Harness.side()
	local cheat: any = { kind = kind, every = EVERY, phase = PHASE, lengths = { LENGTH }, ahead = { AHEAD } }
	local faults: any = { lag = 0, loss = 0, cheat = cheat }
	local bot: any = harness.Bot.new(side.network, harness.context, function () end, faults, SEED)

	for tick: number = 1, CLOSE do
		side.listeners.Owner(Harness.owner(harness, vector.create(tick * STEP, 0, 0), vector.zero, tick, tick))
		bot:tick(tick)
	end

	return side, bot
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local lead: number = harness.context.lead

	-- The lag switch: nothing goes while it is thrown, then every held Move in the order made, then the tick's own
	local switched: Harness.Side, switch: any = hold(harness, "lagSwitch")
	local before: number = PHASE - 1 -- Moves fired before the window opened

	if #switched.fired ~= before + LENGTH + 1 then
		return false, `The lag switch fired {#switched.fired} Moves, not {before} before, {LENGTH} held and 1 after`
	end

	for index: number = 1, LENGTH do
		local fired: Harness.Fired = switched.fired[before + index]
		local made: number = PHASE + index - 1

		if fired.command ~= made + lead or fired.flushes ~= switched.fired[before + 1].flushes then
			return false, `The held Move made on tick {made} carried command {fired.command}, or went in its own flush`
		end
	end

	local holds: { any } = switch:measure().holds
	local moved: number = LENGTH * STEP -- From the OwnerState the window opened on to the last before it closed
	if #holds ~= 1 or holds[1].ticks ~= LENGTH or math.abs(holds[1].moved - moved) > 1e-6 then
		return false, `The lag switch measured {#holds} holds, the first moving the body {holds[1] and holds[1].moved}`
	end

	-- The relabel: nothing goes while it holds, then one Move of its newest commands, numbered ahead of its clock
	local relabeled: Harness.Side, relabel: any = hold(harness, "relabel")
	local again: Harness.Fired = relabeled.fired[before + 1]
	local newest: number = CLOSE + lead + AHEAD

	if #relabeled.fired ~= before + 2 then
		return false, `The relabel fired {#relabeled.fired} Moves, not {before} before, its relabeled one and 1 after`
	elseif again.command ~= newest or #again.commands ~= MAX_COMMANDS then
		return false, `The relabeled Move's newest command is {again.command} of {#again.commands}, not {newest}`
	elseif again.commands[MAX_COMMANDS].number ~= newest - MAX_COMMANDS + 1 then
		return false, "The relabeled commands are not numbered down one at a time from the newest"
	elseif relabeled.fired[before + 2].command ~= CLOSE + lead then
		return false, "After the relabel the bot's own numbering did not run on from its clock"
	elseif #relabel:measure().holds ~= 1 then
		return false, "The relabel measured no hold"
	end

	switch:destroy()
	relabel:destroy()

	return true, nil
end
