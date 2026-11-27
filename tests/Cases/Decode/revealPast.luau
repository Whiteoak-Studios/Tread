--[[
    Decode gives each reveal of a relay block its past, oldest first, each
    record's age in relay ticks beside it decoded as a record is, and an
    empty past for a reveal that carries none
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local CLOSE: number = 1e-9
local SLOT: number = 40
local GENERATION: number = 7
local AGES: { number } = { 6, 3, 1 } -- The player's past, oldest first

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = globals.require(tread.Codec.Block)
	local Constants: any = globals.require(tread.Constants)
	local Decode: any = globals.require(tread.Codec.Decode)
	local Record: any = globals.require(tread.Codec.Record)
	local version: number = Constants.CODEC_VERSION
	local entry: number = Constants.PAST_BYTES

	-- The past's records in one pool, each also decoded alone as the record layout, the shape its entry gives it
	local pool: buffer = buffer.create(#AGES * entry)
	local expected: { { [string]: any } } = {}
	for index: number, age: number in AGES do
		local record: { [string]: any } = Record.new()
		record.slot, record.generation = SLOT, GENERATION
		record.position = vector.create(10 * index, 2, -5 * index)
		record.yaw = index / 2
		record.word = index -- Air, then Swim, then Ladder

		local one: buffer = buffer.create(Constants.RECORD_BYTES)
		Record.write(record, one, 0, Game.limits)
		buffer.writeu8(pool, (index - 1) * entry, age)
		buffer.copy(pool, (index - 1) * entry + 1, one)

		expected[index] = { age = age, record = Decode.decode(version, "record", one) }
	end

	-- A player's reveal with that past, a player's and a sleeper's with none, and the player's newest record whole
	local block: any = Block.new()
	block.sequence, block.tick = 11, 12
	block.reveals = {
		{ slot = SLOT, generation = GENERATION, kind = "Player", pastCount = #AGES, pastAt = 0 },
		{ slot = SLOT + 1, generation = GENERATION, kind = "Player" },
		{ slot = SLOT + 2, generation = GENERATION, kind = "Sleeper" },
	}
	block.revealCount, block.pastData = 3, pool
	block.recordData, block.records, block.recordCount = pool, { (#AGES - 1) * entry + 1 }, 1

	local scratch: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	local length: number = Block.write(block, scratch)
	local relay: buffer = buffer.create(length)
	buffer.copy(relay, 0, scratch, 0, length)

	local decoded: { [string]: any } = Decode.decode(version, "relay", relay)
	local reveals: { { [string]: any } } = {
		{ slot = SLOT, generation = GENERATION, kind = "Player", past = expected },
		{ slot = SLOT + 1, generation = GENERATION, kind = "Player", past = {} },
		{ slot = SLOT + 2, generation = GENERATION, kind = "Sleeper", past = {} },
	}

	local differs: string? = Same(reveals, decoded.reveals, "reveals", CLOSE)
	if differs then
		return false, differs
	end

	-- The newest past record by its own values, and the block's whole record, the same bytes, decoded alike
	local newest: { [string]: any } = decoded.reveals[1].past[#AGES]
	if newest.age ~= 1 or newest.record.position ~= vector.create(30, 2, -15) or newest.record.mode ~= "Ladder" then
		local found: string = `{newest.age} ticks old at {newest.record.position} in {newest.record.mode}`
		return false, `The newest past record decoded {found}, not 1 tick old at (30, 2, -15) on a ladder`
	end

	differs = Same(newest.record, decoded.records[1], "whole record", CLOSE)
	if #decoded.records ~= 1 then
		return false, `The block decoded {#decoded.records} whole records, not its 1`
	elseif differs then
		return false, differs
	end

	return true, nil
end
