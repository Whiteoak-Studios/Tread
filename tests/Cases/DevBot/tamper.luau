--[[
    A tampering bot's Move on its window repeats the command the last Move
    carried newest with a different move, and every Move after it repeats
    that command as it first went
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local EVERY: number = 100
local PHASE: number = 10 -- The tick the tamper's window opens on
local TICKS: number = 12
local SEED: number = 1

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local side: Harness.Side = Harness.side()
	local cheat: any = { kind = "tamper", every = EVERY, phase = PHASE, lengths = { 1 }, ahead = { 1 } }
	local faults: any = { lag = 0, loss = 0, cheat = cheat }

	-- Steady forward, so every honest copy of a command carries the same move
	local bot: any = harness.Bot.new(side.network, harness.context, function (command: any, _: number, _: vector)
		command.forward = 1
	end, faults, SEED)

	side.listeners.Owner(Harness.owner(harness, vector.zero, vector.zero, 0, 0))
	for tick: number = 1, TICKS do
		bot:tick(tick)
	end

	local first: Harness.Wire = side.fired[PHASE - 1].commands[1] -- The command newest in the Move before the window
	local second: Harness.Wire = side.fired[PHASE].commands[2] -- Its second copy, on the window's tick
	local third: Harness.Wire = side.fired[PHASE + 1].commands[3] -- Its third, after it

	if first.number ~= second.number or second.number ~= third.number then
		return false, `The copies compared are of commands {first.number}, {second.number} and {third.number}`
	elseif first.moveX == second.moveX then
		return false, "The tamper's second copy carried the same move as the first"
	elseif third.moveX ~= first.moveX then
		return false, "The copy after the tamper's window carried the tampered move"
	end

	for index: number, fired: Harness.Fired in side.fired do
		if index ~= PHASE and #fired.commands >= 2 and fired.commands[2].moveX ~= fired.commands[1].moveX then
			return false, `The Move of tick {index}, outside the window, carried a differing copy`
		end
	end

	bot:destroy()

	return true, nil
end
