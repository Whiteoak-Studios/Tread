--[[
    A report callback that throws is warned and stays connected, while the
    callbacks after it still run and the report returns to its caller
--]]

--!strict
local Environment = require("../../Environment")

local REPORTS: string = "src/Server/Reports.luau"
local DEPTH: number = 0.4 -- A stuck report's measurement, the depth in studs

return function (): (boolean, string | nil)
	local Reports = Environment.load(REPORTS)
	local thrown: number, after: number = 0, 0

	Reports.connect(function ()
		thrown += 1
		error("This report callback throws on purpose, to show the others still run")
	end)

	Reports.connect(function ()
		after += 1
	end)

	for _ = 1, 2 do
		local returned: boolean, problem: any = pcall(Reports.fire, nil, "stuck", DEPTH)
		if not returned then
			return false, `A throwing callback's error reached the report's caller: {problem}`
		end
	end

	if thrown ~= 2 then
		return false, `The throwing callback ran {thrown} times, not once a report`
	elseif after ~= 2 then
		return false, `The callback after the throwing one ran {after} times, not once a report`
	end

	return true, nil
end
