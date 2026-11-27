--[[
    A command's own fields write to their wire steps at each edge and a
    step inside it, clamp past their limits, and read back at Move's
    precision, and the game's fields ride its buffer at their exact length
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")

local COMMAND: string = "src/Codec/Command.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local TURN: number = 2 * math.pi
local YAW_STEP: number = TURN / 65536
local PITCH_STEP: number = (math.pi / 2) / 16384
local CLOSE: number = 1e-9 -- How near an angle read back must come to the step it was written at

type Row = { field: string, value: any, wire: string, steps: number }

-- One of Tread's own fields set on a command at rest each, and the wire value it writes
local ROWS: { Row } = {
	{ field = "right", value = 1, wire = "moveX", steps = 127 },
	{ field = "right", value = -1, wire = "moveX", steps = -127 },
	{ field = "right", value = 1 / 127, wire = "moveX", steps = 1 },
	{ field = "right", value = 1.5, wire = "moveX", steps = 127 }, -- Clamped to a full input
	{ field = "forward", value = -1, wire = "moveZ", steps = -127 },
	{ field = "forward", value = 126 / 127, wire = "moveZ", steps = 126 },
	{ field = "jump", value = true, wire = "buttons", steps = 1 },
	{ field = "crouch", value = true, wire = "buttons", steps = 2 },
	{ field = "sprint", value = true, wire = "buttons", steps = 4 },
	{ field = "aim", value = true, wire = "buttons", steps = 8 },
	{ field = "yaw", value = 0, wire = "yaw", steps = 0 },
	{ field = "yaw", value = YAW_STEP, wire = "yaw", steps = 1 },
	{ field = "yaw", value = TURN - YAW_STEP, wire = "yaw", steps = 65535 },
	{ field = "yaw", value = TURN, wire = "yaw", steps = 0 }, -- A whole turn wraps to 0
	{ field = "yaw", value = -YAW_STEP, wire = "yaw", steps = 65535 },
	{ field = "pitch", value = math.pi / 2, wire = "pitch", steps = 16384 },
	{ field = "pitch", value = -math.pi / 2, wire = "pitch", steps = -16384 },
	{ field = "pitch", value = PITCH_STEP, wire = "pitch", steps = 1 },
	{ field = "pitch", value = 2, wire = "pitch", steps = 16384 }, -- Clamped to 90°
	{ field = "lean", value = 20, wire = "lean", steps = 127 }, -- At the fixture's 20° limit
	{ field = "lean", value = -20, wire = "lean", steps = -127 },
	{ field = "lean", value = 20 / 127, wire = "lean", steps = 1 },
	{ field = "lean", value = 45, wire = "lean", steps = 127 },
	{ field = "headYaw", value = 75, wire = "headYaw", steps = 127 }, -- At the fixture's 75° cone
	{ field = "headYaw", value = -75 / 127, wire = "headYaw", steps = -1 },
	{ field = "headPitch", value = -75, wire = "headPitch", steps = -127 },
	{ field = "headPitch", value = -90, wire = "headPitch", steps = -127 },
}

return function (): (boolean, string | nil)
	local Command: any = Environment.load(COMMAND)
	local Fields: any = Environment.load(FIELDS)
	local layout: any = Fields.compile(Game.fields)

	for index: number, row: Row in ROWS do
		local command: { [string]: any } = Command.new()
		command.fields = Game.low.command
		command[row.field] = row.value

		local wire: { [string]: any } = Command.wire()
		Command.write(command, wire, layout, Game.limits)
		if wire[row.wire] ~= row.steps then
			return false, `Row {index}: {row.field} at {row.value} wrote {row.wire} {wire[row.wire]}, not {row.steps}`
		end

		-- What reads back writes the same steps again, so both realms run one command
		local read: { [string]: any } = Command.new()
		Command.read(wire, read, layout, Game.limits)

		local again: { [string]: any } = Command.wire()
		Command.write(read, again, layout, Game.limits)
		local differs: string? = Same(wire, again, `row {index} written again`)
		if differs then
			return false, differs
		end
	end

	-- Every field at once, read back at Move's precision
	local command: { [string]: any } = Command.new()
	command.right, command.forward = -1, 1
	command.jump, command.crouch, command.sprint, command.aim = true, true, true, true
	command.yaw, command.pitch = TURN - YAW_STEP, -math.pi / 2
	command.lean, command.headYaw, command.headPitch = -20, 75, -75
	command.fields = Game.high.command

	local wire: { [string]: any } = Command.wire()
	Command.write(command, wire, layout, Game.limits)

	local read: { [string]: any } = Command.new()
	local failed: number? = Command.read(wire, read, layout, Game.limits)
	if failed then
		return false, `A command's game fields read back refused at field {failed}`
	end

	read.pressed = command.pressed
	local differs: string? = Same(command, read, "command", CLOSE)
	if differs then
		return false, differs
	end

	-- The wire's buffer is the packing's exact length, kept while that length holds and replaced when it changes
	local packed: buffer = wire.fields
	if buffer.len(packed) ~= Game.bytes.command then
		return false, `The highest game fields rode a {buffer.len(packed)} B buffer, not their {Game.bytes.command} B`
	end

	Command.write(command, wire, layout, Game.limits)
	if wire.fields ~= packed then
		return false, "Game fields of the same length made a new buffer"
	end

	command.fields = Game.low.command
	Command.write(command, wire, layout, Game.limits)
	if wire.fields == packed or buffer.len(wire.fields) ~= 10 then
		return false, `Shorter game fields rode a {buffer.len(wire.fields)} B buffer, where they fill 10 B`
	end

	-- Without a layout, the game's fields stay packed and Tread's own still read
	local bare: { [string]: any } = Command.new()
	local untouched: { [string]: any } = bare.fields
	if Command.read(wire, bare, nil, Game.limits) ~= nil or bare.fields ~= untouched or next(untouched) ~= nil then
		return false, "A read without a layout touched the game's fields"
	elseif bare.right ~= -1 or bare.forward ~= 1 then
		return false, "A read without a layout lost Tread's own fields"
	end

	return true, nil
end
