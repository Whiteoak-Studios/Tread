--[[
    A Move with a game field outside its declaration, or game bytes past
    its fields, is refused whole, acknowledgments and good commands
    included, and reported as schema with the first failing field's index
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The tick stepped when the Moves arrive
local USES: number = 3 -- The fixture game's carried counter's index, which packs into bits 4 to 7 of the first byte
local USES_BITS: number = 0xF0 -- Those four bits all set, 15, past the counter's max of 9
local LAST: number = 11 -- The fixture game's last command field's index

-- The wire's game fields as a buffer of its own with every bit of mask set in its first byte
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

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)
	rig:send({ rig:command(START + 1) }, 5, 1, 150)

	-- The newer command fine and the older one with its counter at 15
	local move: any = rig:encode(rig:commands(START + 3, 2), 9, 3, 200)
	move.commands[2].fields = overflow(move.commands[2].fields, USES_BITS)
	rig:deliver()

	local schema: { number | string } = rig:reported("schema")
	if #schema ~= 1 or schema[1] ~= USES then
		return false, `A counter past its max was reported as {#schema} schema reports, not one naming field {USES}`
	end

	local sequence: number, mask: number = rig.Commands.acknowledged(rig.connection)
	if sequence ~= 5 or mask ~= 1 or rig.Commands.delay(rig.connection) ~= 150 then
		return false, `The refused Move's acknowledgments were taken: {sequence}, {mask}`
	elseif rig.Commands.depth(rig.connection) ~= 1 then
		return false, `{rig.Commands.depth(rig.connection)} commands wait, where only the earlier good Move's one does`
	end

	-- Game bytes one longer than their fields fill
	move = rig:encode({ rig:command(START + 4) }, 10, 0, 200)
	move.commands[1].fields = lengthened(move.commands[1].fields)
	rig:deliver()

	schema = rig:reported("schema")
	if #schema ~= 2 or schema[2] ~= LAST + 1 then
		return false, `Leftover game bytes were reported as {schema[2]}, not the index past the last field, {LAST + 1}`
	end

	for tick: number = START + 1, START + 4 do
		local _: any, standIn: boolean = rig:take(tick)
		if standIn ~= (tick ~= START + 1) then
			return false, `Tick {tick} ran {standIn and "a stand-in" or "a command"} after the refused Moves`
		end
	end

	return true, nil
end
