--[[
    A disconnected change callback is never called again, one disconnected
    mid-fire by an earlier one is skipped, one connected mid-fire waits for
    the next change, and one that throws stops neither the rest nor the set
--]]

--!strict
local Environment = require("../../Environment")

local SLOTS: string = "src/Server/Slots.luau"

return function (): (boolean, string | nil)
	local Slots = Environment.load(SLOTS)
	local order: { string } = {}
	local disconnectLater: () -> () = function () end
	local added: boolean = false

	Slots.start(0)

	Slots.onChange(function ()
		table.insert(order, "throws")
		error("This change callback throws on purpose, to show the others still run")
	end)

	local disconnectGone: () -> () = Slots.onChange(function ()
		table.insert(order, "gone")
	end)

	Slots.onChange(function ()
		table.insert(order, "middle")
		disconnectLater()

		if not added then
			added = true
			Slots.onChange(function ()
				table.insert(order, "added")
			end)
		end
	end)

	disconnectLater = Slots.onChange(function ()
		table.insert(order, "later")
	end)

	disconnectGone()
	disconnectGone()

	local slot: number = Slots.take("Npc")
	local set: boolean, result: any = pcall(Slots.setEntry, slot, { kind = "Npc", rig = "A" })
	if not set then
		return false, `A throwing change callback's error reached setEntry's caller: {result}`
	elseif result ~= true then
		return false, "setEntry gave up its change for a throwing callback"
	end

	local first: string = table.concat(order, " ")
	if first ~= "throws middle" then
		return false, `The first change ran {first}, not the thrower and middle, with the disconnected ones skipped`
	end

	local _, entry: any = Slots.get(slot)
	if entry == nil or entry.kind ~= "Npc" then
		return false, "A throwing change callback undid the entry it was told of"
	end

	table.clear(order)
	Slots.release(slot)

	local second: string = table.concat(order, " ")
	if second ~= "throws middle added" then
		return false, `The second change ran {second}, not the thrower, middle and the callback added mid-fire`
	end

	return true, nil
end
