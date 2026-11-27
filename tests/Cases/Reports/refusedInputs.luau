--[[
    The report signal refuses a kind Tread never reports, a measurement or
    player of the wrong type and a callback that is no function, and a
    refused report reaches no callback
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local REPORTS: string = "src/Server/Reports.luau"
local COMMAND: number = 41

type Refusal = { label: string, by: string, call: () -> () }

return function (): (boolean, string | nil)
	local Reports = Environment.load(REPORTS)
	local called: number = 0

	Reports.connect(function ()
		called += 1
	end)

	local part: any = roblox.Instance.new("Part")

	local refusals: { Refusal } = {
		{
			label = "a kind Tread never reports",
			by = "Reports.fire",
			call = function ()
				Reports.fire(nil, "speedHack", COMMAND)
			end,
		},
		{
			label = "a missing measurement",
			by = "Reports.fire",
			call = function ()
				Reports.fire(nil, "late", nil)
			end,
		},
		{
			label = "a boolean measurement",
			by = "Reports.fire",
			call = function ()
				Reports.fire(nil, "late", true)
			end,
		},
		{
			label = "a table measurement",
			by = "Reports.fire",
			call = function ()
				Reports.fire(nil, "late", {})
			end,
		},
		{
			label = "an instance that is no Player",
			by = "Reports.fire",
			call = function ()
				Reports.fire(part, "late", COMMAND)
			end,
		},
		{
			label = "a table with no name as the player",
			by = "Reports.fire",
			call = function ()
				Reports.fire({}, "late", COMMAND)
			end,
		},
		{
			label = "a table whose name is no string",
			by = "Reports.fire",
			call = function ()
				Reports.fire({ Name = COMMAND }, "late", COMMAND)
			end,
		},
		{
			label = "a number as the player",
			by = "Reports.fire",
			call = function ()
				Reports.fire(COMMAND, "late", COMMAND)
			end,
		},
		{
			label = "a missing callback",
			by = "Reports.connect",
			call = function ()
				Reports.connect(nil)
			end,
		},
		{
			label = "a string as the callback",
			by = "Reports.connect",
			call = function ()
				Reports.connect("onReport")
			end,
		},
	}

	for _, refusal: Refusal in refusals do
		local ran: boolean, problem: any = pcall(refusal.call)
		if ran then
			return false, `{refusal.by} took {refusal.label}`
		elseif not tostring(problem):find(refusal.by, 1, true) then
			return false, `{refusal.label} failed with "{problem}", not {refusal.by}'s refusal`
		end
	end

	if called ~= 0 then
		return false, `A refused report reached a callback {called} times`
	end

	return true, nil
end
