--[[
    OwnerState refuses a field its width doesn't hold rather than send a
    state the owner would replay from wrongly, and a read refuses bytes
    that aren't an OwnerState or blocks their declarations don't hold
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local OWNER_STATE: string = "src/Codec/OwnerState.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local STATE: string = "src/Step/State.luau"

type Row = { key: string, value: any, text: string }

local ROWS: { Row } = {
	{ key = "command", value = 65536, text = "command holds 0 below 65536" },
	{ key = "tick", value = -1, text = "tick holds" },
	{ key = "depth", value = 256, text = "queue depth holds" },
	{ key = "epoch", value = 256, text = "epoch holds" },
	{ key = "platform", value = 128, text = "platform holds" },
	{ key = "groundTicks", value = 256, text = "ground ticks holds" },
	{ key = "airTicks", value = 1.5, text = "air ticks holds" },
	{ key = "mantleTicks", value = 256, text = "mantle ticks holds" },
	{ key = "ladder", value = 65536, text = "ladder holds" },
	{ key = "eyeHeight", value = 8, text = "eye height holds" }, -- 256 steps of 1/32, past the u8
	{ key = "mantleRise", value = -1 / 32, text = "mantle rise holds" },
	{ key = "position", value = vector.create(16384, 0, 0), text = "position of 16384" },
	{ key = "velocity", value = vector.create(0, 512, 0), text = "velocity of 512" },
	{ key = "apex", value = -16384.01, text = "apex of" },
	{ key = "groundHeight", value = 20000, text = "ground height of" },
	{ key = "moveMode", value = "Flying", text = "no Flying move mode" },
	{ key = "mode", value = "Mounted", text = "state word" },
}

return function (): (boolean, string | nil)
	local OwnerState: any = Environment.load(OWNER_STATE)
	local Fields: any = Environment.load(FIELDS)
	local State: any = Environment.load(STATE)
	local layout: any = Fields.compile(Game.fields)
	local data: buffer = buffer.create(100)

	for _, row: Row in ROWS do
		local state: { [string]: any } = State.new()
		state.fields = Game.low.server
		state.block = Game.low.rules
		state[row.key] = row.value

		local refused: boolean, why: string = Refuses(row.text, OwnerState.write, state, data, 0, layout, Game.limits)
		if not refused then
			return false, `A state with {row.key} at {row.value} was written: {why}`
		end
	end

	-- A rule-state value its declaration doesn't hold
	local state: { [string]: any } = State.new()
	state.fields = Game.low.server
	state.block = table.clone(Game.low.rules)
	state.block.sprintLock = 21
	local refused: boolean, why: string =
		Refuses("fields.rules field 2", OwnerState.write, state, data, 0, layout, Game.limits)
	if not refused then
		return false, `A rule state past its declaration was written: {why}`
	end

	-- A good OwnerState to break
	state.block = Game.high.rules
	local bytes: number = OwnerState.write(state, data, 0, layout, Game.limits)

	type Read = { name: string, length: number, patch: ((data: buffer) -> ())?, text: string }
	local reads: { Read } = {
		{ name = "42 B", length = 42, text = "too short" },
		{ name = "a byte longer", length = bytes + 1, text = "doesn't end" },
		{ name = "a byte shorter", length = bytes - 1, text = "doesn't end" },
		{
			name = "a server-set block past the end",
			length = bytes,
			patch = function (copy: buffer)
				buffer.writeu8(copy, 41, 200)
			end,
			text = "server-set block of 200 B passes",
		},
		{
			name = "a move mode code of 3",
			length = bytes,
			patch = function (copy: buffer)
				buffer.writeu8(copy, 26, 3)
			end,
			text = "mode byte 3",
		},
		{
			name = "a mode byte bit past grounded",
			length = bytes,
			patch = function (copy: buffer)
				buffer.writeu8(copy, 26, 8)
			end,
			text = "mode byte 8",
		},
		{
			name = "platform 128",
			length = bytes,
			patch = function (copy: buffer)
				buffer.writeu8(copy, 25, 128)
			end,
			text = "platform 128",
		},
		{
			-- The rule-state block's sinceJump byte is fine, so break its sprintLock: 6 bits from bit 8, raw 63 is 43
			name = "a rule state past its declaration",
			length = bytes,
			patch = function (copy: buffer)
				local at: number = 41 + 1 + 2 + 1 + 1
				buffer.writeu8(copy, at, bit32.replace(buffer.readu8(copy, at), 63, 0, 6))
			end,
			text = "rule-state block fails at its field 2",
		},
	}

	for _, read: Read in reads do
		local copy: buffer = buffer.create(100)
		buffer.copy(copy, 0, data, 0, 100)
		if read.patch then
			read.patch(copy)
		end

		local into: { [string]: any } = State.new()
		refused, why = Refuses(read.text, OwnerState.read, copy, 0, read.length, into, layout, Game.limits)
		if not refused then
			return false, `OwnerState with {read.name} was read: {why}`
		end
	end

	return true, nil
end
