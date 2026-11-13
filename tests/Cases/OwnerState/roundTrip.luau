--[[
    OwnerState round-trips every field of the step state at its edges and
    its precision's step, with the game's server-set and rule-state blocks
    behind it, 92 B with both blocks at their bounds
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")

local OWNER_STATE: string = "src/Codec/OwnerState.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local STATE: string = "src/Step/State.luau"
local QUANTUM: number = 1 / 512
local FAR: number = (2 ^ 23 - 1) * QUANTUM -- The farthest an i24 at 1/512 stud reaches up
local VELOCITY_STEP: number = 1 / 64
local EYE_STEP: number = 1 / 32
local YAW_STEP: number = 2 * math.pi / 65536
local CLOSE: number = 1e-9
local WORD: number = 2 ^ 32 - 1

type Row = { name: string, set: { [string]: any } }

local ROWS: { Row } = {
	{ name = "a state at rest", set = {} },
	{
		name = "every field at its top",
		set = {
			command = 65535,
			tick = 65535,
			depth = 255,
			position = vector.create(FAR, FAR, FAR),
			velocity = vector.create(512 - VELOCITY_STEP, 512 - VELOCITY_STEP, 512 - VELOCITY_STEP),
			facing = 2 * math.pi - YAW_STEP,
			mode = "Mantle",
			posture = "Downed",
			sprint = true,
			aim = true,
			waterLevel = "Under",
			jumps = 3,
			lands = 3,
			heavy = true,
			epoch = 255,
			platform = 127,
			moveMode = "Parked",
			grounded = true,
			lean = 20,
			eyeHeight = 255 * EYE_STEP,
			apex = FAR,
			groundHeight = FAR,
			groundTicks = 255,
			airTicks = 255,
			mantleTicks = 255,
			slideCooldown = 255,
			mantleRise = 255 * EYE_STEP,
			ladder = 65535,
		},
	},
	{
		name = "every signed field at its bottom",
		set = {
			position = vector.create(-FAR - QUANTUM, -FAR - QUANTUM, -FAR - QUANTUM),
			velocity = vector.create(-512, -512, -512),
			lean = -20,
			apex = -FAR - QUANTUM,
			groundHeight = -FAR - QUANTUM,
			moveMode = "Noclip",
		},
	},
	{
		name = "every field a step from 0",
		set = {
			command = 1,
			tick = 1,
			depth = 1,
			position = vector.create(QUANTUM, -QUANTUM, QUANTUM),
			velocity = vector.create(VELOCITY_STEP, -VELOCITY_STEP, VELOCITY_STEP),
			facing = YAW_STEP,
			epoch = 1,
			platform = 1,
			lean = 20 / 127,
			eyeHeight = EYE_STEP,
			apex = QUANTUM,
			groundHeight = -QUANTUM,
			groundTicks = 1,
			airTicks = 1,
			mantleTicks = 1,
			slideCooldown = 1,
			mantleRise = EYE_STEP,
			ladder = 1,
		},
	},
}

-- Every value of a list the given word fills
local function words(declarations: { { [string]: any } }, value: number): { [string]: any }
	local values: { [string]: any } = {}
	for _, field: { [string]: any } in declarations do
		values[field.name] = value
	end

	return values
end

return function (): (boolean, string | nil)
	local OwnerState: any = Environment.load(OWNER_STATE)
	local Fields: any = Environment.load(FIELDS)
	local State: any = Environment.load(STATE)
	local layout: any = Fields.compile(Game.fields)
	local data: buffer = buffer.create(100)

	for _, row: Row in ROWS do
		for _, edge: string in { "low", "high" } do
			local state: { [string]: any } = State.new()
			for key: string, value: any in row.set do
				state[key] = value
			end

			state.fields = (Game :: any)[edge].server
			state.block = (Game :: any)[edge].rules

			local bytes: number = OwnerState.write(state, data, 3, layout, Game.limits)
			local blocks: number = Fields.write(layout.server, state.fields, buffer.create(64), 0)
				+ Fields.write(layout.rules, state.block, buffer.create(64), 0)
			if bytes ~= 42 + 2 + blocks then
				return false, `{row.name} filled {bytes} B, where its 42 B and blocks fill {42 + 2 + blocks}`
			end

			local into: { [string]: any } = State.new()
			OwnerState.read(data, 3, bytes, into, layout, Game.limits)

			local differs: string? = Same(state, into, `{row.name}, {edge}`, CLOSE)
			if differs then
				return false, differs
			end
		end
	end

	-- Both game blocks at their bounds: 42 + 1 + 16 + 1 + 32 = 92 B
	local largest: any = Fields.compile(Game.largest)
	local state: { [string]: any } = State.new()
	state.fields = words(Game.largest.server, WORD)
	state.block = words(Game.largest.rules, WORD)

	local bytes: number = OwnerState.write(state, data, 0, largest, Game.limits)
	if bytes ~= 92 then
		return false, `OwnerState with both blocks at their bounds filled {bytes} B, not 92`
	end

	local into: { [string]: any } = State.new()
	OwnerState.read(data, 0, bytes, into, largest, Game.limits)
	local differs: string? = Same(state, into, "the largest OwnerState")
	if differs then
		return false, differs
	end

	-- Without a layout the blocks stay packed, and Tread's own fields still read
	local bare: { [string]: any } = State.new()
	OwnerState.read(data, 0, bytes, bare, nil, Game.limits)
	if next(bare.fields) ~= nil or next(bare.block) ~= nil then
		return false, "A read without a layout unpacked the game's blocks"
	end

	return true, nil
end
