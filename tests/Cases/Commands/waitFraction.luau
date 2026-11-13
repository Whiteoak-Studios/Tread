--[[
    A take's queue wait runs from the moment its command arrived to the
    tick that takes it, in simulation ticks with their fraction, held to
    ticks.queueWait
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The tick stepped before the first Move arrives
local QUARTER: number = 0.25 -- The share of a tick after START it arrives at
local FAR: number = 5 -- Ticks after its arrival the last command runs, past the cap
local QUEUE_WAIT: number = 3 -- Frontier Zero's ticks.queueWait
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

	-- Commands for the next two ticks, a quarter tick after START was taken
	now = (START + QUARTER) / rate
	rig:send(rig:commands(START + 2, 2))

	for ahead: number = 1, 2 do
		local command: any, standIn: boolean, wait: number = takeAt(START + ahead)
		local expected: number = ahead - QUARTER

		if standIn or command.number ~= START + ahead then
			return false, `Tick {START + ahead} did not run its own command`
		elseif math.abs(wait - expected) > CLOSE then
			return false,
				`Filed a quarter tick after {START}, the command for {START + ahead} waited {wait}, not {expected}`
		end
	end

	-- A command filed at the moment START + 2 was taken, for the tick FAR after it
	local filed: number = START + 2
	rig:send(rig:commands(filed + FAR, 1))

	for tick: number = filed + 1, filed + FAR - 1 do
		takeAt(tick)
	end

	local _: any, standIn: boolean, wait: number = takeAt(filed + FAR)
	if standIn then
		return false, `Tick {filed + FAR} ran a stand-in in place of its command`
	elseif wait ~= QUEUE_WAIT then
		return false, `The command that waited {FAR} ticks reported {wait}, not the cap of {QUEUE_WAIT}`
	end

	return true, nil
end
