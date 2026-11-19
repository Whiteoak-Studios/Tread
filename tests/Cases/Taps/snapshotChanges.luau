--[[
    The changes onReliable reports between two snapshots carry one into the
    other both ways, each change's value before it walking back and after it
    walking on, and a callback that throws stops none of them
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local FIRST_LOOK: { [string]: any } = { head = 3 }
local SECOND_LOOK: { [string]: any } = { head = 4, torso = 5 }
local HELD: { [string]: any } = { item = 9 }

-- One slot as a snapshot or a change holds it, its parts as strings so two compare by value
type Slot = {
	generation: number,
	kind: string,
	rig: string,
	look: string,
	held: string,
}

-- A decoded snapshot's slots, by slot
local function slotsOf(decoded: any): { [number]: Slot }
	local slots: { [number]: Slot } = {}

	for _, entry: any in decoded.slots do
		slots[entry.slot] = {
			generation = entry.generation,
			kind = entry.kind,
			rig = entry.rig,
			look = buffer.tostring(entry.look),
			held = buffer.tostring(entry.held),
		}
	end

	return slots
end

-- A change's slot entry as a snapshot's slot, nil for a free slot
local function entryOf(entry: any): Slot?
	if entry == nil then
		return nil
	end

	return {
		generation = entry.generation,
		kind = entry.kind,
		rig = entry.rig,
		look = buffer.tostring(entry.look),
		held = buffer.tostring(entry.held),
	}
end

-- Applies one change to a state by slot, its value before it when back, else its value after
local function apply(state: { [number]: Slot }, change: any, back: boolean): string?
	local value: any = change.current
	if back then
		value = change.previous
	end

	if change.kind == "slot" then
		state[change.slot] = entryOf(value)
	elseif change.kind == "look" or change.kind == "held" then
		local slot: Slot? = state[change.slot]
		if not slot then
			return `A {change.kind} change named slot {change.slot}, which was free then`
		end

		slot[change.kind] = buffer.tostring(value)
	end

	return nil
end

-- Names the first slot where two states differ, or nil when they hold the same
local function differ(expected: { [number]: Slot }, actual: { [number]: Slot }): string?
	for slot: number, entry: Slot in expected do
		local other: Slot? = actual[slot]
		if not other then
			return `slot {slot} is missing`
		end

		for key: string, value: any in entry :: any do
			if (other :: any)[key] ~= value then
				return `slot {slot}'s {key} differs`
			end
		end
	end

	for slot: number in actual do
		if not expected[slot] then
			return `slot {slot} is there, where it should be free`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Tread: any = rig:require(rig.tread)
	local Record: any = rig:require(rig.tread.Codec.Record)
	local version: number = Tread.CODEC_VERSION

	local first: any = server:create(rig.mock:addBot("First"), rig:at(0, 0))
	first:setOutfit(FIRST_LOOK)
	rig:tick(2)

	local changes: { any } = {}
	local stopThrowing: () -> () = server:onReliable(function ()
		error("This change callback throws on purpose, to show the others still hear")
	end)
	local stop: () -> () = server:onReliable(function (change: any)
		table.insert(changes, change)
	end)

	if pcall(server.onReliable, server, 7) then
		return false, "onReliable took a number"
	end

	local before: { [number]: Slot } = slotsOf(Tread.decode(version, "snapshot", server:snapshot()))
	if not before[first._slot] or before[first._slot].kind ~= "Player" or before[first._slot].look == "" then
		return false, "The first snapshot did not hold the dressed character"
	end

	-- A join, a new look, a held item the next relay run packs, a death and its body, a sleep, and the ends
	local second: any = server:create(rig.mock:addBot("Second"), rig:at(6, 0))
	first:setOutfit(SECOND_LOOK)
	first:setHeld(HELD)
	rig:tick(1)

	local body: any = second:die(roblox.Vector3.new(0, 0, -2))
	second:destroy()
	first:sleep()
	first:destroy()
	rig:tick(1)

	body:destroy()
	rig:tick(1)

	local after: { [number]: Slot } = slotsOf(Tread.decode(version, "snapshot", server:snapshot()))

	local kinds: { [string]: number } = {}
	for _, change: any in changes do
		kinds[change.kind] = (kinds[change.kind] or 0) + 1
	end

	if not kinds.slot or not kinds.look or not kinds.held or kinds.death ~= 1 then
		return false, "The changes did not take in a slot, a look, a held item and one death"
	end

	for _, change: any in changes do
		if change.kind == "death" then
			local dying: number = Record.id(second._slot, second._generation)
			local push: any = change.current.push
			if change.slot ~= second._slot or change.current.character ~= dying or change.previous ~= nil then
				return false, "The death change named another dying character, or a value before it"
			elseif typeof(push) ~= "Vector3" or push ~= roblox.Vector3.new(0, 0, -1) then
				return false, `The death change's push is {push}, not the attack's direction`
			end
		end
	end

	-- Back from the second snapshot to the first
	local walked: { [number]: Slot } = slotsOf(Tread.decode(version, "snapshot", server:snapshot()))
	for index: number = #changes, 1, -1 do
		local failure: string? = apply(walked, changes[index], true)
		if failure then
			return false, failure
		end
	end

	local differs: string? = differ(before, walked)
	if differs then
		return false, `Walking back from the second snapshot left a state whose {differs} from the first`
	end

	-- On from the first to the second
	for _, change: any in changes do
		local failure: string? = apply(before, change, false)
		if failure then
			return false, failure
		end
	end

	differs = differ(after, before)
	if differs then
		return false, `Walking on from the first snapshot left a state whose {differs} from the second`
	end

	stop()
	stopThrowing()
	local heard: number = #changes
	server:createNpc(rig:at(10, 10))

	if #changes ~= heard then
		return false, "A disconnected change callback still heard"
	end

	return true, nil
end
