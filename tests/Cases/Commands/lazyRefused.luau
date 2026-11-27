--[[
    With lazy decode on as off, a Move whose bad command sits beside spares
    the ring holds the same of, differs from its first copy, or lies outside
    the window is refused whole with the same index, and the ring untouched
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The tick stepped when the Moves arrive
local BEHIND: number = 8 -- Frontier Zero's ticks the ring holds at and before the newest stepped
local USES: number = 3 -- The fixture game's carried counter's index, which packs into bits 4 to 7 of the first byte
local USES_BITS: number = 0xF0 -- Those four bits all set, 15, past the counter's max of 9
local LAST: number = 11 -- The fixture game's last command field's index
local SEQUENCE: number = 5 -- The good Move's acknowledgments and delay, which every refused one must leave
local MASK: number = 1
local DELAY: number = 150

-- The schema index each refused Move below reports
local REFUSED: { number } = { USES, LAST + 1, USES, USES, USES }

-- How far Commands.skipped rises at each refused Move with lazy decode on: the spares the ring holds the same of
local RISES: { number } = { 2, 2, 1, 0, 0 }

-- The wire's game fields as a buffer of their own with every bit of mask set in the first byte
local function overflow(fields: buffer, mask: number): buffer
	local bytes: buffer = buffer.create(buffer.len(fields))
	buffer.copy(bytes, 0, fields)
	buffer.writeu8(bytes, 0, bit32.bor(buffer.readu8(bytes, 0), mask))

	return bytes
end

-- The wire's game fields with one byte of 0 behind them
local function lengthened(fields: buffer): buffer
	local bytes: buffer = buffer.create(buffer.len(fields) + 1)
	buffer.copy(bytes, 0, fields)

	return bytes
end

-- Hands the rig's Move over and gives how far Commands.skipped rose
local function deliver(rig: Intake.Intake): number
	local before: number = rig.Commands.skipped()
	rig:deliver()

	return rig.Commands.skipped() - before
end

--[[
    The refused Moves after one good one, each spoiled after it is encoded,
    then the good commands again. Gives each refused Move's rise, and the
    reason when something besides the schema reports changed
--]]

local function stream(rig: Intake.Intake): ({ number }, string?)
	local rises: { number } = {}

	rig:take(START)
	rig:send(rig:commands(START + 2, 2), SEQUENCE, MASK, DELAY)

	-- 1) A first copy of 103 that fails, with 102 and 101 the same behind it
	local move: any = rig:encode(rig:commands(START + 3, 3), SEQUENCE + 1, 0, DELAY + 1)
	move.commands[1].fields = overflow(move.commands[1].fields, USES_BITS)
	table.insert(rises, deliver(rig))

	-- 2) 102 and 101 the same, then a first copy of 100, after its tick, with a byte past its fields
	move = rig:encode(rig:commands(START + 2, 3), SEQUENCE + 2, 0, DELAY + 1)
	move.commands[3].fields = lengthened(move.commands[3].fields)
	table.insert(rises, deliver(rig))

	-- 3) A good first copy of 103, a copy of 102 that differs in fields that fail, and 101 the same
	move = rig:encode(rig:commands(START + 3, 3), SEQUENCE + 3, 0, DELAY + 1)
	move.commands[2].fields = overflow(move.commands[2].fields, USES_BITS)
	table.insert(rises, deliver(rig))

	-- 4) 107 past the ahead limit failing, before 106 past it and a good first copy of 105
	move = rig:encode(rig:commands(START + 7, 3), SEQUENCE + 4, 0, DELAY + 1)
	move.commands[1].fields = overflow(move.commands[1].fields, USES_BITS)
	table.insert(rises, deliver(rig))

	-- 5) A command older than the ring holds, failing
	move = rig:encode(rig:commands(START - BEHIND, 1), SEQUENCE + 5, 0, DELAY + 1)
	move.commands[1].fields = overflow(move.commands[1].fields, USES_BITS)
	table.insert(rises, deliver(rig))

	local sequence: number, mask: number = rig.Commands.acknowledged(rig.connection)
	if sequence ~= SEQUENCE or mask ~= MASK or rig.Commands.delay(rig.connection) ~= DELAY then
		return rises, `A refused Move's acknowledgments were taken: {sequence}, {mask}`
	elseif rig.Commands.depth(rig.connection) ~= 2 then
		return rises, `{rig.Commands.depth(rig.connection)} commands wait, where only the good Move's two do`
	end

	-- The ring is as the good Move left it, so 103 files as a first copy and every tick runs its own command
	rig:send(rig:commands(START + 3, 3))

	for tick: number = START + 1, START + 3 do
		local command: any, standIn: boolean = rig:take(tick)
		if standIn then
			return rises, `Tick {tick} ran a stand-in after the refused Moves`
		elseif command.number ~= tick then
			return rises, `Tick {tick} ran command {command.number}, not its own`
		end
	end

	-- The stand-in at START and the gap 101 ends are the stream's own, and anything else came of a refused Move
	for _, heard: Intake.Heard in rig.heard do
		if heard.kind ~= "schema" and heard.kind ~= "standIn" and heard.kind ~= "gap" then
			return rises, `A refused Move or the good one after them reported {heard.kind} {heard.measurement}`
		end
	end

	return rises, nil
end

return function (): (boolean, string | nil)
	local on: Intake.Intake = Intake.new()
	local off: Intake.Intake = Intake.new()
	off.Commands.useLazy(false)

	for _, rig: Intake.Intake in { on, off } do
		local state: string = rig.Commands.lazyOn() and "on" or "off"
		local rises: { number }, broken: string? = stream(rig)
		if broken then
			return false, `With lazy decode {state}: {broken}`
		end

		local schema: { number | string } = rig:reported("schema")
		if #schema ~= #REFUSED then
			return false, `With lazy decode {state}, {#schema} Moves were refused, not {#REFUSED}`
		end

		for index: number, field: number in REFUSED do
			if schema[index] ~= field then
				return false, `With lazy decode {state}, refused Move {index} named field {schema[index]}, not {field}`
			end

			local rise: number = rig == on and RISES[index] or 0
			if rises[index] ~= rise then
				return false,
					`With lazy decode {state}, refused Move {index} raised skipped by {rises[index]}, not {rise}`
			end
		end
	end

	return true, nil
end
