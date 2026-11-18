--[[
    S10's probe reads each relay run's time with its tick's finish added, a
    finish of no run it holds adding nothing, the tick still held left out,
    and the relay's times alone with no finish kept
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

-- The relay's ring: ticks 5 to 8, each its own whole seconds less 4
local RELAY_TICKS: { number } = { 5, 6, 7, 8 }
local RELAY_TIMES: { number } = { 1, 2, 3, 4 }
local HELD: number = 8 -- The tick whose finish is still to come

-- The finishes' ring: a stale one for tick 2, then ticks 6 and 7
local FINISH_TICKS: { number } = { 2, 6, 7, 0 }
local FINISH_TIMES: { number } = { 0.125, 0.5, 0.25, 0 }

local WITH_FINISHES: string = "1000,2500,3250" -- Milliseconds, tick 8 left out while held
local UNHELD: string = "1000,2500,3250,4000"
local ALONE: string = "1000,2000,3000,4000"

-- A ring as the tick loop keeps one, holding the first count of the times and ticks given
local function ring(times: { number }, ticks: { number }, count: number): any
	return {
		name = "relay",
		times = times,
		ticks = ticks,
		beats = table.create(#times, 0),
		held = count,
		head = count % #times,
		last = times[count] or 0,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local Spectators: any = loaded.require(dataModel:GetService("ServerScriptService").Server.Spectators)

	local relay: any = ring(RELAY_TIMES, RELAY_TICKS, #RELAY_TICKS)
	local finishes: any = ring(FINISH_TIMES, FINISH_TICKS, 3)
	local empty: any = ring(table.create(4, 0), table.create(4, 0), 0)

	local held: string = table.concat(Spectators.relayTimes(relay, finishes, HELD), ",")
	local unheld: string = table.concat(Spectators.relayTimes(relay, finishes, nil), ",")
	local alone: string = table.concat(Spectators.relayTimes(relay, empty, nil), ",")

	if held ~= WITH_FINISHES then
		return false, `The relay's runs with their finishes, tick {HELD} held, read {held} ms, not {WITH_FINISHES}`
	elseif unheld ~= UNHELD then
		return false, `With no tick held they read {unheld} ms, not {UNHELD}`
	elseif alone ~= ALONE then
		return false, `With no finish kept they read {alone} ms, not {ALONE}`
	end

	return true, nil
end
