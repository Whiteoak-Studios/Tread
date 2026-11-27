--[[
    A callback that disconnects a later one mid-fire stops it running that
    report, one that disconnects an earlier one leaves the run it had, and
    one connected mid-fire waits for the next report
--]]

--!strict
local Environment = require("../../Environment")

local REPORTS: string = "src/Server/Reports.luau"
local SECONDS: number = 0.5 -- A gap's measurement, its length

return function (): (boolean, string | nil)
	local Reports = Environment.load(REPORTS)
	local order: { string } = {}
	local disconnectLater: () -> () = function () end
	local disconnectEarlier: () -> () = function () end
	local added: boolean = false

	disconnectEarlier = Reports.connect(function ()
		table.insert(order, "earlier")
	end)

	Reports.connect(function ()
		table.insert(order, "middle")
		disconnectLater()
		disconnectEarlier()

		if not added then
			added = true
			Reports.connect(function ()
				table.insert(order, "added")
			end)
		end
	end)

	disconnectLater = Reports.connect(function ()
		table.insert(order, "later")
	end)

	Reports.fire(nil, "gap", SECONDS)

	local first: string = table.concat(order, " ")
	if first ~= "earlier middle" then
		return false, `The first report ran {first}, not earlier then middle with later skipped and nothing added`
	end

	table.clear(order)
	Reports.fire(nil, "gap", SECONDS)

	local second: string = table.concat(order, " ")
	if second ~= "middle added" then
		return false, `The second report ran {second}, not middle then the callback added mid-fire`
	end

	return true, nil
end
