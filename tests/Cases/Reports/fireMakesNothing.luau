--[[
    A report fired to callbacks that make nothing makes nothing itself: a
    thousand fires leave the heap's count the same to the byte, where any
    table made would raise it or wake the collector, which lowers it
--]]

--!strict
local Environment = require("../../Environment")

local REPORTS: string = "src/Server/Reports.luau"
local FIRES: number = 1000
local TICKS: number = 3 -- A standIn's measurement, the stand-ins in a row
local CALLBACKS: number = 2

return function (): (boolean, string | nil)
	local Reports = Environment.load(REPORTS)
	local calls: number = 0

	local function count()
		calls += 1
	end

	for _ = 1, CALLBACKS do
		Reports.connect(count)
	end

	-- One fire first, so whatever a first call sets up once is made before the count is read
	Reports.fire(nil, "standIn", TICKS)

	local before: number = collectgarbage("count")
	for _ = 1, FIRES do
		Reports.fire(nil, "standIn", TICKS)
	end
	local changed: number = collectgarbage("count") - before

	if calls ~= CALLBACKS * (FIRES + 1) then
		return false, `The callbacks ran {calls} times, not {CALLBACKS * (FIRES + 1)}`
	elseif changed ~= 0 then
		return false, `{FIRES} fires changed the heap's count by {changed} KB`
	end

	return true, nil
end
