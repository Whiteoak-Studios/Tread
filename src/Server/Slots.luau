--[[
    The server's slot table: the character slots every kind shares, each
    one's generation and entry, and the slots sleepers may never take
--]]

--!strict
local Constants = require(script.Parent.Parent.Constants)

local SLOTS: number = Constants.SLOTS
local GENERATIONS: number = 2 ^ Constants.GENERATION_BITS -- A generation wraps inside the record's bits beside the slot
local SLOT_BYTES: number = 2 -- Each free slot's u16 in the free ring
local KINDS: { [string]: boolean } = { Player = true, Npc = true, Sleeper = true, Body = true }
local RIGS: { [string]: boolean } = { A = true, B = true }

export type Kind = "Player" | "Npc" | "Sleeper" | "Body"
export type Rig = "A" | "B"

-- What the slot table holds for a taken slot: its kind, its rig mode, and the Player for a live player's slot only
export type Entry = {
	kind: Kind,
	rig: Rig,
	player: Player?,
}

type Callback = (slot: number, generation: number, previous: Entry?, current: Entry?) -> ()
type Listener = { callback: Callback, connected: boolean }

-- Each slot's generation, of its current life or its last
local Generations: buffer = buffer.create(SLOTS)

-- The free slots in the order they are given out: never-used ones lowest first, then each released slot behind
-- every slot freed before it, so a slot stays free as long as it can before its generation moves on
local Free: buffer = buffer.create(SLOTS * SLOT_BYTES)
local Head: number = 0 -- The ring index the next slot is taken from
local FreeCount: number = SLOTS

local Kinds: { [number]: Kind } = {} -- Each taken slot's kind, from its take until its release
local Entries: { [number]: Entry } = {} -- Each taken slot's entry, once one is set
local Counts: { [Kind]: number } = { Player = 0, Npc = 0, Sleeper = 0, Body = 0 }
local Listeners: { Listener } = {} -- The change callbacks, in the order they connected

local Reserve: number = 0 -- The slots sleepers may never take, the server settings' slots.reserve
local Started: boolean = false

for slot: number = 0, SLOTS - 1 do
	buffer.writeu16(Free, slot * SLOT_BYTES, slot)
end

local Slots = {}

--[[
    Holds back the slots sleepers may never take, the server settings'
    slots.reserve, before the first take. It runs once
--]]

function Slots.start(reserve: number)
	if Started then
		error("Slots.start runs once, and it has already run", 2)
	elseif type(reserve) ~= "number" or reserve % 1 ~= 0 or reserve < 0 or reserve > SLOTS then
		error(`Slots.start takes slots.reserve as a whole number from 0 to {SLOTS}, not {reserve}`, 2)
	end

	Reserve = reserve
	Started = true
end

--[[
    A free slot for a character of the kind, and the generation its new
    life carries. A player, NPC or body takes any free slot and errors,
    naming the reserve, when none is; a sleeper gets nil once sleepers hold
    every slot the reserve leaves them, or when none is free
--]]

function Slots.take(kind: Kind): (number?, number?)
	if not Started then
		error("Slots.take ran before Slots.start held back the reserve", 2)
	elseif not KINDS[kind] then
		error(`Slots.take takes a Player, Npc, Sleeper or Body, not {kind}`, 2)
	end

	if kind == "Sleeper" and (Counts.Sleeper >= SLOTS - Reserve or FreeCount == 0) then
		return nil, nil
	elseif FreeCount == 0 then
		local held: string = `slots.reserve holds back {Reserve}`
		error(`No slot is free for a {kind}: {held}, fewer than the players, NPCs and bodies held at once`, 2)
	end

	local slot: number = buffer.readu16(Free, Head * SLOT_BYTES)
	local generation: number = (buffer.readu8(Generations, slot) + 1) % GENERATIONS

	Head = (Head + 1) % SLOTS
	FreeCount -= 1

	buffer.writeu8(Generations, slot, generation)
	Kinds[slot] = kind
	Counts[kind] += 1

	return slot, generation
end

-- Runs where a callback's error was raised, so its warning keeps the callback's stack
local function warnFailure(message: any)
	warn(`A slot change callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

--[[
    Tells every change callback of a slot's change. Each runs under its own
    xpcall, so one that throws is warned with its stack and never stops the
    others or the call that changed the slot
--]]

local function changed(slot: number, previous: Entry?, current: Entry?)
	local generation: number = buffer.readu8(Generations, slot)

	-- A copy, so a callback connected mid-fire waits for the next change and one disconnected mid-fire is skipped
	for _, listener: Listener in table.clone(Listeners) do
		if listener.connected then
			xpcall(listener.callback, warnFailure, slot, generation, previous, current)
		end
	end
end

--[[
    Sets a taken slot's entry and tells every change callback. A slot
    turning sleeper keeps its slot and generation, so it stays inside the
    sleepers' share as a take does: past it, nothing changes and this is
    false
--]]

function Slots.setEntry(slot: number, entry: Entry): boolean
	local kind: Kind? = Kinds[slot]
	if kind == nil then
		error(`Slots.setEntry takes a taken slot, not {slot}`, 2)
	elseif type(entry) ~= "table" then
		error(`Slots.setEntry takes an entry table, not a {typeof(entry)}`, 2)
	elseif not KINDS[entry.kind] then
		error(`Slots.setEntry takes an entry whose kind is Player, Npc, Sleeper or Body, not {entry.kind}`, 2)
	elseif not RIGS[entry.rig] then
		error(`Slots.setEntry takes an entry whose rig is A or B, not {entry.rig}`, 2)
	end

	local player: Player? = entry.player
	if player ~= nil and not (typeof(player) == "Instance" and player:IsA("Player")) then
		error(`Slots.setEntry takes an entry whose player is a Player or nil, not a {typeof(player)}`, 2)
	end

	if entry.kind == "Sleeper" and kind ~= "Sleeper" and Counts.Sleeper >= SLOTS - Reserve then
		return false
	end

	-- A copy of its own, so a later change to the caller's table never changes what the slot table holds
	local previous: Entry? = Entries[slot]
	local current: Entry = { kind = entry.kind, rig = entry.rig, player = player }

	Counts[kind] -= 1
	Counts[current.kind] += 1
	Kinds[slot] = current.kind
	Entries[slot] = current

	changed(slot, previous, current)

	return true
end

--[[
    A slot's generation, of its current life or its last, and its entry,
    nil while the slot is free or before one is set
--]]

function Slots.get(slot: number): (number, Entry?)
	if not Slots.valid(slot) then
		error(`Slots.get takes a slot from 0 to {SLOTS - 1}, not {slot}`, 2)
	end

	return buffer.readu8(Generations, slot), Entries[slot]
end

--[[
    How many slots a kind holds now, such as the sleepers held that a
    refused sleep reports
--]]

function Slots.count(kind: Kind): number
	local count: number? = Counts[kind]
	if count == nil then
		error(`Slots.count takes a Player, Npc, Sleeper or Body, not {kind}`, 2)
	end

	return count
end

--[[
    Frees a taken slot, which goes behind every slot already free, and
    tells every change callback when the slot had an entry
--]]

function Slots.release(slot: number)
	local kind: Kind? = Kinds[slot]
	if kind == nil then
		error(`Slots.release takes a taken slot, not {slot}`, 2)
	end

	local previous: Entry? = Entries[slot]

	Counts[kind] -= 1
	Kinds[slot] = nil
	Entries[slot] = nil

	buffer.writeu16(Free, ((Head + FreeCount) % SLOTS) * SLOT_BYTES, slot)
	FreeCount += 1

	if previous then
		changed(slot, previous, nil)
	end
end

--[[
    Calls back on every change to the slot table with the slot, its
    generation, and its entry before and after, nil for a free slot.
    Returns the closure that disconnects the callback
--]]

function Slots.onChange(callback: Callback): () -> ()
	if type(callback) ~= "function" then
		error(`Slots.onChange takes a function, not a {typeof(callback)}`, 2)
	end

	local listener: Listener = { callback = callback, connected = true }
	table.insert(Listeners, listener)

	return function ()
		listener.connected = false

		local index: number? = table.find(Listeners, listener)
		if index then
			table.remove(Listeners, index)
		end
	end
end

--[[
    Whether a value names one of the table's slots, a whole number from 0
    to one less than the slot count
--]]

function Slots.valid(slot: number): boolean
	return type(slot) == "number" and slot % 1 == 0 and slot >= 0 and slot < SLOTS
end

return Slots
