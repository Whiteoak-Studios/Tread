--[[
    OwnerState, server to owner once a relay tick: the complete step state
    after the last command the server ran, Tread's own 42 B, then the game's
    server-set and rule-state blocks, each behind its u8 length
--]]

--!strict
--!native
local Bits = require(script.Parent.Bits)
local Command = require(script.Parent.Command)
local Constants = require(script.Parent.Parent.Constants)
local Fields = require(script.Parent.Fields)
local State = require(script.Parent.Parent.Step.State)
local StateWord = require(script.Parent.StateWord)

local POSITION_SCALE: number = 1 / Constants.POSITION_QUANTUM -- Steps a stud of a position axis, the apex and ground
local VELOCITY_SCALE: number = 1 / Constants.VELOCITY_QUANTUM
local EYE_SCALE: number = 1 / Constants.EYE_QUANTUM -- Steps a stud of the eye height and the mantle's rise
local YAW_SCALE: number = Constants.ANGLE_STEPS / (2 * math.pi)
local U8: number = 2 ^ 8 -- The values each unsigned width holds
local U16: number = 2 ^ 16
local I16: number = 2 ^ 15 -- Each signed width's values either side of 0
local I24: number = 2 ^ 23

-- Each move mode's place in its list, from 0, is its code
local MOVE_MODES: { State.MoveMode } = { "Walk", "Noclip", "Parked" }
local GROUNDED_AT: number = Constants.MOVE_MODE_BITS -- The mode byte's grounded bit, above the move mode's

type Layout = Fields.Layout
type Limits = Command.Limits
type State = State.State

local OwnerState = {}

-- A whole number from 0 below size, erroring naming the field it is for otherwise
local function unsigned(value: number, size: number, field: string): number
	if not (value % 1 == 0 and value >= 0 and value < size) then
		error(`OwnerState's {field} holds 0 below {size}, not {value}`)
	end

	return value
end

-- A value rounded to its steps at scale, as an i24 or i16's two's complement, erroring past what half holds either way
local function signed(value: number, scale: number, half: number, field: string): number
	local steps: number = math.round(value * scale)
	if not (steps >= -half and steps < half) then
		error(`OwnerState's {field} of {value} passes what its {half * 2} steps hold`)
	end

	return steps % (half * 2)
end

local function fromSigned(value: number, half: number): number
	if value >= half then
		return value - half * 2
	end

	return value
end

--[[
    Writes a state into data from offset and gives the bytes it filled, at
    most 92. Each of Tread's fields is rounded to its precision, which the
    step already holds it to, and it errors on one its width doesn't hold,
    or on a game field its declaration doesn't
--]]

function OwnerState.write(state: State, data: buffer, offset: number, layout: Layout, limits: Limits): number
	local position: vector = state.position
	local velocity: vector = state.velocity
	local moveMode: number? = table.find(MOVE_MODES, state.moveMode)
	if not moveMode then
		error(`OwnerState holds no {state.moveMode} move mode`)
	end

	local mode: number = moveMode - 1
	if state.grounded then
		mode = bit32.replace(mode, 1, GROUNDED_AT)
	end

	local lean: number = math.clamp(
		math.round(state.lean * Constants.LEAN_STEPS / limits.lean),
		-Constants.LEAN_STEPS,
		Constants.LEAN_STEPS
	)

	buffer.writeu16(data, offset, unsigned(state.command, U16, "command"))
	buffer.writeu16(data, offset + 2, unsigned(state.tick, U16, "tick"))
	buffer.writeu8(data, offset + 4, unsigned(state.depth, U8, "queue depth"))
	Bits.writeu24(data, offset + 5, signed(position.x, POSITION_SCALE, I24, "position"))
	Bits.writeu24(data, offset + 8, signed(position.y, POSITION_SCALE, I24, "position"))
	Bits.writeu24(data, offset + 11, signed(position.z, POSITION_SCALE, I24, "position"))
	buffer.writeu16(data, offset + 14, signed(velocity.x, VELOCITY_SCALE, I16, "velocity"))
	buffer.writeu16(data, offset + 16, signed(velocity.y, VELOCITY_SCALE, I16, "velocity"))
	buffer.writeu16(data, offset + 18, signed(velocity.z, VELOCITY_SCALE, I16, "velocity"))
	buffer.writeu16(data, offset + 20, math.round(state.facing * YAW_SCALE) % Constants.ANGLE_STEPS)
	buffer.writeu16(data, offset + 22, StateWord.pack(state))
	buffer.writeu8(data, offset + 24, unsigned(state.epoch, U8, "epoch"))
	buffer.writeu8(data, offset + 25, unsigned(state.platform, Constants.MAX_PLATFORMS + 1, "platform"))
	buffer.writeu8(data, offset + 26, mode)
	buffer.writei8(data, offset + 27, lean)
	buffer.writeu8(data, offset + 28, unsigned(math.round(state.eyeHeight * EYE_SCALE), U8, "eye height"))
	Bits.writeu24(data, offset + 29, signed(state.apex, POSITION_SCALE, I24, "apex"))
	Bits.writeu24(data, offset + 32, signed(state.groundHeight, POSITION_SCALE, I24, "ground height"))
	buffer.writeu8(data, offset + 35, unsigned(state.groundTicks, U8, "ground ticks"))
	buffer.writeu8(data, offset + 36, unsigned(state.airTicks, U8, "air ticks"))
	buffer.writeu8(data, offset + 37, unsigned(state.mantleTicks, U8, "mantle ticks"))
	buffer.writeu8(data, offset + 38, unsigned(state.slideCooldown, U8, "slide cooldown"))
	buffer.writeu8(data, offset + 39, unsigned(math.round(state.mantleRise * EYE_SCALE), U8, "mantle rise"))
	buffer.writeu16(data, offset + 40, unsigned(state.ladder, U16, "ladder"))

	-- The game's two blocks, each behind its length
	local at: number = offset + Constants.OWNER_STATE_BYTES
	local serverLength: number = Fields.write(layout.server, state.fields, data, at + Constants.PREFIX_BYTES)
	buffer.writeu8(data, at, serverLength)
	at += Constants.PREFIX_BYTES + serverLength

	local rulesLength: number = Fields.write(layout.rules, state.block, data, at + Constants.PREFIX_BYTES)
	buffer.writeu8(data, at, rulesLength)
	at += Constants.PREFIX_BYTES + rulesLength

	return at - offset
end

--[[
    Reads the length bytes of OwnerState from offset into into, and with a
    layout the game's two blocks into its fields and block too. Without one
    the blocks stay packed in data. It errors on bytes that aren't an
    OwnerState, and on a game block its declarations don't hold
--]]

function OwnerState.read(data: buffer, offset: number, length: number, into: State, layout: Layout?, limits: Limits)
	local finish: number = offset + length
	if not (length >= Constants.OWNER_STATE_BYTES + 2 * Constants.PREFIX_BYTES and finish <= buffer.len(data)) then
		error(`OwnerState of {length} B from byte {offset} is too short or passes its {buffer.len(data)} B buffer`)
	end

	local serverAt: number = offset + Constants.OWNER_STATE_BYTES + Constants.PREFIX_BYTES
	local serverLength: number = buffer.readu8(data, serverAt - Constants.PREFIX_BYTES)
	local rulesAt: number = serverAt + serverLength + Constants.PREFIX_BYTES
	if rulesAt > finish then
		error(`OwnerState's server-set block of {serverLength} B passes its {length} B`)
	end

	local rulesLength: number = buffer.readu8(data, rulesAt - Constants.PREFIX_BYTES)
	if rulesAt + rulesLength ~= finish then
		error(`OwnerState's rule-state block of {rulesLength} B doesn't end its {length} B`)
	end

	local mode: number = buffer.readu8(data, offset + 26)
	local moveMode: State.MoveMode? = MOVE_MODES[bit32.extract(mode, 0, Constants.MOVE_MODE_BITS) + 1]
	local platform: number = buffer.readu8(data, offset + 25)
	if not moveMode or mode >= 2 ^ (GROUNDED_AT + 1) or platform > Constants.MAX_PLATFORMS then
		error(`OwnerState's mode byte {mode} or platform {platform} holds no value`)
	end

	into.command = buffer.readu16(data, offset)
	into.tick = buffer.readu16(data, offset + 2)
	into.depth = buffer.readu8(data, offset + 4)
	into.position = vector.create(
		fromSigned(Bits.readu24(data, offset + 5), I24) / POSITION_SCALE,
		fromSigned(Bits.readu24(data, offset + 8), I24) / POSITION_SCALE,
		fromSigned(Bits.readu24(data, offset + 11), I24) / POSITION_SCALE
	)
	into.velocity = vector.create(
		buffer.readi16(data, offset + 14) / VELOCITY_SCALE,
		buffer.readi16(data, offset + 16) / VELOCITY_SCALE,
		buffer.readi16(data, offset + 18) / VELOCITY_SCALE
	)
	into.facing = buffer.readu16(data, offset + 20) / YAW_SCALE

	-- The word gives the epoch's parity, and the full epoch follows it
	StateWord.unpack(buffer.readu16(data, offset + 22), into)
	into.epoch = buffer.readu8(data, offset + 24)
	into.platform = platform
	into.moveMode = moveMode
	into.grounded = bit32.extract(mode, GROUNDED_AT) == 1
	into.lean = buffer.readi8(data, offset + 27) * limits.lean / Constants.LEAN_STEPS
	into.eyeHeight = buffer.readu8(data, offset + 28) / EYE_SCALE
	into.apex = fromSigned(Bits.readu24(data, offset + 29), I24) / POSITION_SCALE
	into.groundHeight = fromSigned(Bits.readu24(data, offset + 32), I24) / POSITION_SCALE
	into.groundTicks = buffer.readu8(data, offset + 35)
	into.airTicks = buffer.readu8(data, offset + 36)
	into.mantleTicks = buffer.readu8(data, offset + 37)
	into.slideCooldown = buffer.readu8(data, offset + 38)
	into.mantleRise = buffer.readu8(data, offset + 39) / EYE_SCALE
	into.ladder = buffer.readu16(data, offset + 40)

	if not layout then
		return
	end

	local failed: number? = Fields.read(layout.server, data, serverAt, serverLength, into.fields)
	if failed then
		error(`OwnerState's server-set block fails at its field {failed}`)
	end

	failed = Fields.read(layout.rules, data, rulesAt, rulesLength, into.block)
	if failed then
		error(`OwnerState's rule-state block fails at its field {failed}`)
	end
end

return OwnerState
