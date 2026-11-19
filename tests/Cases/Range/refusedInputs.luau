--[[
    The range query refuses a slot outside the slot table, a name that is
    no string and a range that is negative, NaN or no number, and a refused
    set leaves the query as it was
--]]

--!strict
local Environment = require("../../Environment")

local RANGE: string = "src/Server/Range.luau"
local CONSTANTS: string = "src/Constants.luau"
local STUDS: number = 10

type Refusal = { label: string, by: string, call: () -> () }

return function (): (boolean, string | nil)
	local Range = Environment.load(RANGE)
	local count: number = Environment.load(CONSTANTS).SLOTS
	local origin: vector = vector.create(0, 0, 0)

	local refusals: { Refusal } = {
		{
			label = "a missing slot",
			by = "Range.set",
			call = function ()
				Range.set(nil :: any, origin, "Refused")
			end,
		},
	}

	local slots: { any } = { -1, count, 1.5, 0 / 0, "3", false }
	for _, slot: any in slots do
		table.insert(refusals, {
			label = `the slot {slot}`,
			by = "Range.set",
			call = function ()
				Range.set(slot, origin, "Refused")
			end,
		})

		table.insert(refusals, {
			label = `the slot {slot} to remove`,
			by = "Range.remove",
			call = function ()
				Range.remove(slot)
			end,
		})
	end

	table.insert(refusals, {
		label = "a number as the name",
		by = "Range.set",
		call = function ()
			Range.set(0, origin, 7 :: any)
		end,
	})

	local ranges: { any } = { -1, -math.huge, 0 / 0, `{STUDS}`, false }
	for _, range: any in ranges do
		table.insert(refusals, {
			label = `the range {range}`,
			by = "Range.near",
			call = function ()
				Range.near(origin, range)
			end,
		})

		table.insert(refusals, {
			label = `the range {range} for NPCs`,
			by = "Range.npcsNear",
			call = function ()
				Range.npcsNear(origin, range)
			end,
		})
	end

	for _, refusal: Refusal in refusals do
		local ran: boolean, problem: any = pcall(refusal.call)
		if ran then
			return false, `{refusal.by} took {refusal.label}`
		elseif not tostring(problem):find(refusal.by, 1, true) then
			return false, `{refusal.label} failed with "{problem}", not {refusal.by}'s refusal`
		end
	end

	if #Range.near(origin, math.huge) ~= 0 or #Range.npcsNear(origin, math.huge) ~= 0 then
		return false, "A refused set left a slot in the query"
	end

	return true, nil
end
