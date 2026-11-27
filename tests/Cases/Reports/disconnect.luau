--[[
    A disconnected report callback is never called again, the others still
    are, and calling a disconnect a second time does nothing
--]]

--!strict
local Environment = require("../../Environment")

local REPORTS: string = "src/Server/Reports.luau"
local TICKS: number = 3 -- A standIn's measurement, the stand-ins in a row

return function (): (boolean, string | nil)
	local Reports = Environment.load(REPORTS)
	local gone: number, kept: number = 0, 0

	local disconnect: () -> () = Reports.connect(function ()
		gone += 1
	end)

	Reports.connect(function ()
		kept += 1
	end)

	Reports.fire(nil, "standIn", TICKS)
	disconnect()
	Reports.fire(nil, "standIn", TICKS)

	if gone ~= 1 then
		return false, `A disconnected callback was called {gone} times, not once before its disconnect`
	elseif kept ~= 2 then
		return false, `The callback left connected was called {kept} times, not twice`
	end

	local again: boolean, problem: any = pcall(disconnect)
	if not again then
		return false, `A second disconnect threw: {problem}`
	end

	Reports.fire(nil, "standIn", TICKS)

	if gone ~= 1 or kept ~= 3 then
		return false, "A second disconnect changed which callbacks are called"
	end

	return true, nil
end
