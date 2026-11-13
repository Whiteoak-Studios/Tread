--[[
    A client's store keeps each slot's records of the last 32 relay ticks in
    one 768 B buffer made at its first keep: it finds each by its tick and
    life, a record 32 ticks newer takes its place, and an empty entry is none
--]]

--!strict
local Environment = require("../../Environment")

local CHANGE: string = "src/Codec/Change.luau"
local SLOTS: number = 4096
local SLOT: number = 37
local TICK: number = 1000
local DEPTH: number = 32
local SLOT_BYTES: number = 768 -- 32 entries of an 8 B tick and a 16 B record
local AT: number = 16 -- Where the kept records sit in the buffers they are kept from

-- A 16 B record of a life whose bytes past its id are all marker, at AT of a buffer
local function record(slot: number, generation: number, marker: number): buffer
	local data: buffer = buffer.create(AT + 16)
	buffer.fill(data, AT, marker)
	buffer.writeu16(data, AT, slot + generation * SLOTS)

	return data
end

return function (): (boolean, string | nil)
	local Change: any = Environment.load(CHANGE)
	local store: any = Change.store()
	local id: number = SLOT + 2 * SLOTS

	-- Whether the store holds the record at AT of data for id at tick, and the buffer it holds it in
	local function holds(tick: number, data: buffer): (boolean, buffer?)
		local found: buffer?, offset: number = Change.find(store, id, tick)
		if found == nil then
			return false, nil
		end

		return buffer.readstring(found, offset, 16) == buffer.readstring(data, AT, 16), found
	end

	local first: buffer = record(SLOT, 2, 0x11)
	local second: buffer = record(SLOT, 2, 0x22)
	Change.keep(store, TICK, first, AT)
	Change.keep(store, TICK + 1, second, AT)

	local kept: boolean, entries: buffer? = holds(TICK, first)
	if not kept or not holds(TICK + 1, second) then
		return false, "The store didn't give back the records kept at their ticks"
	elseif entries == nil or buffer.len(entries) ~= SLOT_BYTES then
		return false, `A slot's records take {entries and buffer.len(entries)} B, not {SLOT_BYTES}`
	end

	-- Ticks it holds no record of, another life of the slot, and a slot it never kept
	local misses: { { any } } = {
		{ "a tick before", id, TICK - 1 },
		{ "the tick 32 on, at the same entry", id, TICK + DEPTH },
		{ "another generation", SLOT + 3 * SLOTS, TICK },
		{ "another slot", SLOT + 1 + 2 * SLOTS, TICK },
	}

	for _, miss: { any } in misses do
		local found: buffer? = Change.find(store, miss[2], miss[3])
		if found ~= nil then
			return false, `The store gave a record for {miss[1]}`
		end
	end

	-- A record 32 ticks newer takes the entry, in the same buffer, and leaves the others
	local later: buffer = record(SLOT, 2, 0x33)
	Change.keep(store, TICK + DEPTH, later, AT)

	local overwritten: buffer? = Change.find(store, id, TICK)
	local again: boolean, reused: buffer? = holds(TICK + DEPTH, later)
	if overwritten ~= nil or not again then
		return false, "A record 32 ticks newer didn't take the older one's place"
	elseif reused ~= entries then
		return false, "The slot's records moved to a new buffer"
	elseif not holds(TICK + 1, second) then
		return false, "Overwriting one entry lost another"
	end

	-- A new life's record at its tick is that life's alone
	Change.keep(store, TICK + DEPTH + 1, record(SLOT, 3, 0x44), AT)
	if
		Change.find(store, id, TICK + DEPTH + 1) ~= nil
		or Change.find(store, SLOT + 3 * SLOTS, TICK + DEPTH + 1) == nil
	then
		return false, "A new life's record was found under the old life's id, or not under its own"
	end

	-- An entry nothing filled names no record, slot 0's generation 0 at tick 0 included
	local fresh: any = Change.store()
	Change.keep(fresh, 5, record(0, 1, 0x55), AT)
	if Change.find(fresh, 0, 0) ~= nil or Change.find(fresh, SLOTS, 5) == nil then
		return false, "An empty entry was found as slot 0's record at tick 0, or the kept one wasn't"
	end

	return true, nil
end
