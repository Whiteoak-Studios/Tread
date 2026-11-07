--[[
    The queue holds no more than ticks.ahead commands, and each take gives
    the whole ticks its command waited in the queue before its own, capped
    at ticks.queueWait
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The tick stepped when the commands arrive
local AHEAD: number = 5 -- Frontier Zero's ticks.ahead
local QUEUE_WAIT: number = 3 -- Its ticks.queueWait

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)

	-- A command for each of the next 5 ticks, then one for the tick after
	rig:send(rig:commands(START + AHEAD, AHEAD))
	rig:send(rig:commands(START + AHEAD + 1, 1))

	local depth: number = rig.Commands.depth(rig.connection)
	if depth ~= AHEAD then
		return false, `The queue holds {depth} commands, where it holds at most ticks.ahead, {AHEAD}`
	end

	for ahead: number = 1, AHEAD do
		local command: any, standIn: boolean, wait: number = rig:take(START + ahead)
		local expected: number = math.min(ahead - 1, QUEUE_WAIT)

		if standIn or command.number ~= START + ahead then
			return false, `Tick {START + ahead} did not run its own command`
		elseif wait ~= expected then
			return false, `The command that ran {ahead} ticks after it arrived waited {wait}, not {expected}`
		end

		local left: number = rig.Commands.depth(rig.connection)
		if left ~= AHEAD - ahead then
			return false, `After tick {START + ahead} the queue holds {left}, not {AHEAD - ahead}`
		end
	end

	local _: any, standIn: boolean, wait: number = rig:take(START + AHEAD + 1)
	if not standIn or wait ~= 0 then
		return false, "The tick whose command was past the cap ran something other than a stand-in that waited 0"
	end

	return true, nil
end
