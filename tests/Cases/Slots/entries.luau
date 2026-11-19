--[[
    A slot's entry is set and changed through setEntry and cleared by its
    release, each change reaching the callbacks with the entry before and
    after it, and the table keeps a copy of its own
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local SLOTS: string = "src/Server/Slots.luau"

type Change = { slot: number, generation: number, previous: any, current: any }

return function (): (boolean, string | nil)
	local Slots = Environment.load(SLOTS)
	local changes: { Change } = {}

	Slots.start(0)
	Slots.onChange(function (slot: number, generation: number, previous: any, current: any)
		table.insert(changes, { slot = slot, generation = generation, previous = previous, current = current })
	end)

	local slot: number, generation: number = Slots.take("Player")
	local _, unset: any = Slots.get(slot)
	if #changes ~= 0 or unset ~= nil then
		return false, "A take alone changed the slot table's entries"
	end

	local player: any = roblox.Instance.new("Player")
	local entry: { [string]: any } = { kind = "Player", rig = "A", player = player }

	if not Slots.setEntry(slot, entry) then
		return false, "A player's entry was refused"
	end

	local set: Change = changes[1]
	if #changes ~= 1 or set.slot ~= slot or set.generation ~= generation or set.previous ~= nil then
		return false, "Setting a first entry did not report the slot, its generation and no previous entry"
	elseif set.current.kind ~= "Player" or set.current.rig ~= "A" or set.current.player ~= player then
		return false, "Setting a first entry reported another entry than the one set"
	end

	entry.rig = "B"
	local _, copy: any = Slots.get(slot)
	if copy.rig ~= "A" then
		return false, "Changing the caller's table changed the entry the slot table holds"
	end

	Slots.setEntry(slot, { kind = "Sleeper", rig = "A" })

	local turned: Change = changes[2]
	if turned.previous.kind ~= "Player" or turned.current.kind ~= "Sleeper" or turned.current.player ~= nil then
		return false, "A change of entry did not report the player's entry before the sleeper's"
	elseif Slots.count("Player") ~= 0 or Slots.count("Sleeper") ~= 1 then
		return false, "A change of entry did not move the slot's count to its new kind"
	end

	Slots.release(slot)

	local freed: Change = changes[3]
	local freedGeneration: number, cleared: any = Slots.get(slot)
	if freed.previous.kind ~= "Sleeper" or freed.current ~= nil or freed.generation ~= generation then
		return false, "A release did not report the freed entry under its generation"
	elseif cleared ~= nil or freedGeneration ~= generation then
		return false, "A released slot still reads an entry, or another generation"
	elseif Slots.count("Sleeper") ~= 0 then
		return false, "A release did not take the slot off its kind's count"
	end

	local unannounced: number = Slots.take("Npc")
	Slots.release(unannounced)

	if #changes ~= 3 then
		return false, "Releasing a slot that never had an entry reported a change"
	end

	return true, nil
end
