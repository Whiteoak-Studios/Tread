--[[
    Relay blocks with change records for the client cases: a 16 B record of
    Record's fields, its change against a baseline, and a block's bytes from
    its reveals, hides, whole records and changes, in the relay's layout
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local WIRE: number = 2 ^ 16 -- The values a block's u16 sequence and tick hold
local CHANGE_MOST: number = 4 + 16 -- Past the longest change record, its header and every field

local globals: any = Environment.load(GLOBALS)
local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
local Block: any = globals.require(tread.Codec.Block)
local Change: any = globals.require(tread.Codec.Change)
local Constants: any = globals.require(tread.Constants)
local Record: any = globals.require(tread.Codec.Record)

-- One block: its sequence and tick, reveals and hides as Block's, and its whole records and changes each a buffer
export type Spec = {
	sequence: number,
	tick: number,
	reveals: { any }?,
	hides: { any }?,
	records: { buffer }?,
	changes: { buffer }?,
}

local Changes = {}

--[[
    A 16 B record of Record's fields by name, every one but slot,
    generation and position optional, at Frontier Zero's limits
--]]

function Changes.record(fields: { [string]: any }): buffer
	local record: { [string]: any } = Record.new()
	for name: string, value: any in fields do
		record[name] = value
	end

	local data: buffer = buffer.create(Constants.RECORD_BYTES)
	Record.write(record, data, 0, Game.limits)

	return data
end

--[[
    A record's change against its baseline base relay ticks older, exactly
    as long as it goes, erroring on one that must go whole
--]]

function Changes.change(current: buffer, baseline: buffer, base: number): buffer
	local scratch: buffer = buffer.create(CHANGE_MOST)
	local bytes: number = Change.write(current, 0, baseline, 0, base, scratch, 0)
	if bytes == 0 then
		error(`The change {base} relay ticks back must go whole`)
	end

	local exact: buffer = buffer.create(bytes)
	buffer.copy(exact, 0, scratch, 0, bytes)

	return exact
end

--[[
    A relay block's bytes, exactly as long as Volt hands them over: its
    reveals, hides, whole records in order and then its changes in order
--]]

function Changes.block(spec: Spec): buffer
	local block: any = Block.new()
	block.sequence = spec.sequence % WIRE
	block.tick = spec.tick % WIRE

	local reveals: { any } = spec.reveals or {}
	local hides: { any } = spec.hides or {}
	block.reveals, block.revealCount = reveals, #reveals
	block.hides, block.hideCount = hides, #hides

	local records: { buffer } = spec.records or {}
	local recordData: buffer = buffer.create(math.max(#records, 1) * Constants.RECORD_BYTES)
	for index: number, record: buffer in records do
		buffer.copy(recordData, (index - 1) * Constants.RECORD_BYTES, record)
		block.records[index] = (index - 1) * Constants.RECORD_BYTES
	end

	block.recordData, block.recordCount = recordData, #records

	local changes: { buffer } = spec.changes or {}
	local changeData: buffer = buffer.create(math.max(#changes, 1) * CHANGE_MOST)
	local filled: number = 0
	for index: number, change: buffer in changes do
		buffer.copy(changeData, filled, change)
		block.changeOffsets[index] = filled
		block.changeLengths[index] = buffer.len(change)
		filled += buffer.len(change)
	end

	block.changeData, block.changeCount = changeData, #changes

	local data: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	local bytes: number = Block.write(block, data)
	local exact: buffer = buffer.create(bytes)
	buffer.copy(exact, 0, data, 0, bytes)

	return exact
end

return Changes
