--[[
    A callback that disconnects itself and a later one, connects another and
    fires a report of its own runs that inner report on every callback still
    connected, the new one among them, while the outer report skips both it
    disconnected, and each later report runs the rest in the order they came
--]]

--!strict
local Environment = require("../../Environment")

local REPORTS: string = "src/Server/Reports.luau"
local SECONDS: number = 0.5 -- A gap's measurement, its length
local TICKS: number = 2 -- A late command's measurement, the ticks it came late

return function (): (boolean, string | nil)
	local Reports = Environment.load(REPORTS)
	local order: { string } = {}
	local disconnectSelf: () -> () = function () end
	local disconnectLater: () -> () = function () end
	local changed: boolean = false

	Reports.connect(function (_: any, kind: string)
		table.insert(order, `first {kind}`)
	end)

	disconnectSelf = Reports.connect(function (_: any, kind: string)
		table.insert(order, `second {kind}`)
		if changed then
			return
		end

		changed = true
		disconnectSelf()
		disconnectLater()

		Reports.connect(function (_: any, inner: string)
			table.insert(order, `added {inner}`)
		end)

		Reports.fire(nil, "late", TICKS)
	end)

	disconnectLater = Reports.connect(function (_: any, kind: string)
		table.insert(order, `later {kind}`)
	end)

	Reports.fire(nil, "gap", SECONDS)

	local first: string = table.concat(order, ", ")
	if first ~= "first gap, second gap, first late, added late" then
		return false, `The first report ran {first}`
	end

	-- Calling each disconnect again does nothing, and the reports after run the two left in their order
	disconnectSelf()
	disconnectLater()

	for _ = 1, 2 do
		table.clear(order)
		Reports.fire(nil, "gap", SECONDS)

		local ran: string = table.concat(order, ", ")
		if ran ~= "first gap, added gap" then
			return false, `A later report ran {ran}`
		end
	end

	return true, nil
end
