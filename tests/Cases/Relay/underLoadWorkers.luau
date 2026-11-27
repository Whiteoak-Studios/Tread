--[[
    The far rate under load's lowered band reaches the stand-in workers in
    the next run's tuning block, so on 1 and 2 workers every block digests as
    in process and the far target's records halve and come back on the same
    runs
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")
local UnderLoad = require("../../Fixtures/Relay/UnderLoad")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MOST_WORKERS: number = 2
local EXPECTED_FAR: string = "111010101111" -- As underLoadHalves pins it in process

return function (): (boolean, string | nil)
	local serial: UnderLoad.Ran = UnderLoad.drive(Environment.load(HARNESS), nil, UnderLoad.two)
	if serial.far ~= EXPECTED_FAR then
		return false, `In process the far target's records ran {serial.far}, not {EXPECTED_FAR}`
	end

	for workers: number = 1, MOST_WORKERS do
		local ran: UnderLoad.Ran = UnderLoad.drive(Layouts.harness(), workers, UnderLoad.two)
		if ran.far ~= serial.far or ran.near ~= serial.near then
			return false, `On {workers} workers the records ran {ran.near} and {ran.far}, not as in process`
		elseif ran.digest ~= serial.digest then
			return false, `On {workers} workers the blocks digest to {ran.digest}, not {serial.digest} as in process`
		elseif ran.halved ~= serial.halved or ran.over ~= serial.over then
			return false,
				`On {workers} workers the caps counted {ran.halved} lowered and {ran.over} over, not as in process`
		end
	end

	return true, nil
end
