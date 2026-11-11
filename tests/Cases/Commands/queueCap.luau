--[[
    The queue holds no more than ticks.ahead commands, and each take gives
    the ticks its command waited in the queue from its arrival to the tick
    that takes it, capped at ticks.queueWait
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The tick stepped when the commands arrive
local AHEAD: number = 5 -- Frontier Zero's ticks.ahead
local QUEUE_WAIT: number = 3 -- Its ticks.queueWait
local CLOSE: number = 1e-9

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local rate: number = rig.shared.rates.simulation
	local now: number = 0 -- Seconds on the clock Commands is handed

	rig.Commands.setClock(function (): number
		return now
	end)

	local function takeAt(tick: number): (any, boolean, number)
		now = tick / rate

		return rig:take(tick)
	end

	takeAt(START)

	-- A command for each of the next 5 ticks, then one for the tick after, as START is taken
	rig:send(rig:commands(START + AHEAD, AHEAD))
	rig:send(rig:commands(START + AHEAD + 1, 1))

	local depth: number = rig.Commands.depth(rig.connection)
	if depth ~= AHEAD then
		return false, `The queue holds {depth} commands, where it holds at most ticks.ahead, {AHEAD}`
	end

	for ahead: number = 1, AHEAD do
		local command: any, standIn: boolean, wait: number = takeAt(START + ahead)
		local expected: number = math.min(ahead, QUEUE_WAIT)

		if standIn or command.number ~= START + ahead then
			return false, `Tick {START + ahead} did not run its own command`
		elseif math.abs(wait - expected) > CLOSE then
			return false, `The command that ran {ahead} ticks after it arrived waited {wait}, not {expected}`
		end

		local left: number = rig.Commands.depth(rig.connection)
		if left ~= AHEAD - ahead then
			return false, `After tick {START + ahead} the queue holds {left}, not {AHEAD - ahead}`
		end
	end

	local _: any, standIn: boolean, wait: number = takeAt(START + AHEAD + 1)
	if not standIn or wait ~= 0 then
		return false, "The tick whose command was past the cap ran something other than a stand-in that waited 0"
	end

	return true, nil
end
