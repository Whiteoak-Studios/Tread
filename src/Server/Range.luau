--[[
    The server's range query: where each player's and NPC's slot stands,
    and which of them are within a distance of a point
--]]

--!strict
local Slots = require(script.Parent.Slots)

-- Each slot's place, and a player's name, by slot
local Positions: { [number]: vector } = {}
local Names: { [number]: string } = {}

-- Whiteoak TODO: each query passes over every player or every NPC, which holds at 150 players; as servers approach
-- 300, a uniform grid of about 500-stud cells replaces the pass behind near and npcsNear
local PlayerSlots: { number } = {}
local NpcSlots: { number } = {}

-- The list each slot is in and its index there, so a leave or a move between lists is one swap
local Lists: { [number]: { number } } = {}
local Places: { [number]: number } = {}

local Range = {}

-- Takes a slot out of its list by moving the list's last slot into its place
local function unlist(slot: number)
	local list: { number }? = Lists[slot]
	if not list then
		return
	end

	local index: number = Places[slot]
	local last: number = list[#list]

	list[index] = last
	Places[last] = index
	list[#list] = nil

	Lists[slot] = nil
	Places[slot] = nil
end

-- The square of a query's range, which each squared distance is compared against, edge included
local function squared(range: number, caller: string): number
	-- NaN is the one number that differs from itself
	if type(range) ~= "number" or range ~= range or range < 0 then
		error(`{caller} takes a range of 0 studs or more, not {range}`, 3)
	end

	return range * range
end

--[[
    Puts a slot in the query at a place, or moves it there: a player's slot
    with its name, which near returns, and an NPC's with none, which
    npcsNear returns
--]]

function Range.set(slot: number, position: vector, name: string?)
	if not Slots.valid(slot) then
		error(`Range.set takes one of the slot table's slots, not {slot}`, 2)
	elseif name ~= nil and type(name) ~= "string" then
		error(`Range.set takes a player's name as a string, not a {typeof(name)}`, 2)
	end

	local list: { number } = name and PlayerSlots or NpcSlots
	if Lists[slot] ~= list then
		unlist(slot)
		table.insert(list, slot)

		Lists[slot] = list
		Places[slot] = #list
	end

	Positions[slot] = position
	Names[slot] = name
end

--[[
    Takes a slot out of the query, for a character that leaves, dies or
    falls asleep. A slot not in the query is left as it is
--]]

function Range.remove(slot: number)
	if not Slots.valid(slot) then
		error(`Range.remove takes one of the slot table's slots, not {slot}`, 2)
	end

	unlist(slot)

	Positions[slot] = nil
	Names[slot] = nil
end

--[[
    The names of the players within range of a point, the edge included
--]]

function Range.near(at: vector, range: number): { string }
	local limit: number = squared(range, "Range.near")
	local names: { string } = {}

	for _, slot: number in PlayerSlots do
		local offset: vector = Positions[slot] - at
		if vector.dot(offset, offset) <= limit then
			table.insert(names, Names[slot])
		end
	end

	return names
end

--[[
    The slots of the NPCs within range of a point, the edge included
--]]

function Range.npcsNear(at: vector, range: number): { number }
	local limit: number = squared(range, "Range.npcsNear")
	local slots: { number } = {}

	for _, slot: number in NpcSlots do
		local offset: vector = Positions[slot] - at
		if vector.dot(offset, offset) <= limit then
			table.insert(slots, slot)
		end
	end

	return slots
end

return Range
