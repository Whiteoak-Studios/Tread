--[[
    One Move command: the step's command to and from the fields Volt sends,
    Tread's own at their wire precisions and the game's declared fields
    packed behind them
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)
local Fields = require(script.Parent.Fields)
local State = require(script.Parent.Parent.Step.State)

local MOVE_STEPS: number = Constants.MOVE_STEPS
local YAW_SCALE: number = Constants.ANGLE_STEPS / (2 * math.pi) -- Steps a radian of yaw
local PITCH_SCALE: number = Constants.PITCH_LIMIT / (math.pi / 2) -- Steps a radian of pitch, a quarter turn at 90°

-- Each button's bit in a command's buttons
local JUMP: number = 0
local CROUCH: number = 1
local SPRINT: number = 2
local AIM: number = 3

type Command = State.Command
type Layout = Fields.Layout

-- A command as Volt's Move sends it, the shape Tread's schema gives Command
export type Wire = {
	moveX: number,
	moveZ: number,
	buttons: number,
	yaw: number,
	pitch: number,
	lean: number,
	headYaw: number,
	headPitch: number,
	fields: buffer, -- The game's declared fields, packed
}

-- The game's limits that lean and the head offset count their steps to, both in degrees, from the step's settings
export type Limits = {
	lean: number,
	headCone: number,
}

-- Packs the game's command fields before their exact length is known
local Scratch: buffer = buffer.create(Constants.MAX_COMMAND_FIELDS)

local Command = {}

--[[
    A command at rest, every button up, with an empty table for the game's
    fields
--]]

function Command.new(): Command
	return {
		number = 0,
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

--[[
    A wire command at rest, which a Move fills and reuses
--]]

function Command.wire(): Wire
	return {
		moveX = 0,
		moveZ = 0,
		buttons = 0,
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = buffer.create(0),
	}
end

-- Rounds value to whole steps at scale a unit, inside limit steps either way
local function steps(value: number, scale: number, limit: number): number
	return math.clamp(math.round(value * scale), -limit, limit)
end

local function flag(on: boolean, position: number): number
	return on and 2 ^ position or 0
end

--[[
    Writes a command into a wire command: its move axes, look, lean and head
    offset rounded to their steps, each clamped to its limit, and the game's
    fields packed against the layout, which errors on a value the
    declarations don't hold
--]]

function Command.write(command: Command, wire: Wire, layout: Layout, limits: Limits)
	wire.moveX = steps(command.right, MOVE_STEPS, MOVE_STEPS)
	wire.moveZ = steps(command.forward, MOVE_STEPS, MOVE_STEPS)
	wire.buttons = flag(command.jump, JUMP)
		+ flag(command.crouch, CROUCH)
		+ flag(command.sprint, SPRINT)
		+ flag(command.aim, AIM)
	wire.yaw = math.round(command.yaw * YAW_SCALE) % Constants.ANGLE_STEPS
	wire.pitch = steps(command.pitch, PITCH_SCALE, Constants.PITCH_LIMIT)
	wire.lean = steps(command.lean, Constants.LEAN_STEPS / limits.lean, Constants.LEAN_STEPS)
	wire.headYaw = steps(command.headYaw, Constants.HEAD_STEPS / limits.headCone, Constants.HEAD_STEPS)
	wire.headPitch = steps(command.headPitch, Constants.HEAD_STEPS / limits.headCone, Constants.HEAD_STEPS)

	-- Volt sends a buffer field whole, so the wire's buffer is the packing's exact length
	-- Whiteoak TODO: a game whose command fields change length from one command to the next makes a buffer at each
	-- change; keep one buffer per length on each wire if G5 shows the client paying for it
	local length: number = Fields.write(layout.command, command.fields, Scratch, 0)
	if buffer.len(wire.fields) ~= length then
		wire.fields = buffer.create(length)
	end

	buffer.copy(wire.fields, 0, Scratch, 0, length)
end

--[[
    Reads a wire command into into: Tread's own fields from their steps,
    and with a layout the game's fields too, giving the index of the first
    one that fails, as Fields.read does, or nil. Without a layout the game's
    fields stay packed in the wire's buffer. Its number and presses are the
    caller's
--]]

function Command.read(wire: Wire, into: Command, layout: Layout?, limits: Limits): number?
	local buttons: number = wire.buttons

	into.right = wire.moveX / MOVE_STEPS
	into.forward = wire.moveZ / MOVE_STEPS
	into.jump = bit32.extract(buttons, JUMP) == 1
	into.crouch = bit32.extract(buttons, CROUCH) == 1
	into.sprint = bit32.extract(buttons, SPRINT) == 1
	into.aim = bit32.extract(buttons, AIM) == 1
	into.yaw = wire.yaw / YAW_SCALE
	into.pitch = wire.pitch / PITCH_SCALE
	into.lean = wire.lean * limits.lean / Constants.LEAN_STEPS
	into.headYaw = wire.headYaw * limits.headCone / Constants.HEAD_STEPS
	into.headPitch = wire.headPitch * limits.headCone / Constants.HEAD_STEPS

	if not layout then
		return nil
	end

	return Fields.read(layout.command, wire.fields, 0, buffer.len(wire.fields), into.fields)
end

return Command
