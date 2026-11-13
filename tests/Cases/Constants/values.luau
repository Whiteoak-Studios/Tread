--[[
    Every constant in src/Constants.luau is a number holding the value the
    design's layouts give it, and the module holds none this case lacks
--]]

--!strict
local Environment = require("../../Environment")

local CONSTANTS: string = "src/Constants.luau"

-- Each constant's value, as the layout it bounds gives it
local EXPECTED: { [string]: number } = {
	CODEC_VERSION = 1,
	PREFIX_BYTES = 1,
	POSITION_QUANTUM = 1 / 512,
	VELOCITY_QUANTUM = 1 / 64,
	VELOCITY_LIMIT = 512,
	EYE_QUANTUM = 1 / 32,
	EYE_BITS = 8,
	TIMER_LIMIT = 255,
	EXACT_EVERY = 10,
	SKIN = 0.02,
	MAX_BUMPS = 4,
	CAST_REACH = 0.5,
	MIN_CREASE = 1e-3,
	DEPENETRATION_FIRST = 1 / 1024,
	DEPENETRATION_STEPS = 11,
	PLAY_BOUND = 8192,
	ANGLE_STEPS = 65536,
	PITCH_LIMIT = 16384,
	LEAN_STEPS = 127,
	HEAD_STEPS = 127,
	HEAD_LEVELS = 7,
	RECORD_PITCH_STEPS = 127,
	MAX_COMMANDS = 8,
	MOVE_REPEATS = 2,
	COMMAND_BYTES = 11,
	MOVE_STEPS = 127,
	ACK_MASK_BITS = 16,
	FIRST_SEQUENCE = 1,
	MAX_COMMAND_FIELDS = 64,
	MAX_SERVER_SET = 16,
	MAX_RULE_STATE = 32,
	MAX_LOOK = 64,
	MAX_HELD = 16,
	OWNER_STATE_BYTES = 42,
	MAX_OWNER_STATE = 92,
	MODE_BITS = 3,
	POSTURE_BITS = 2,
	WATER_BITS = 2,
	COUNTER_BITS = 2,
	EPOCH_BITS = 2,
	MOVE_MODE_BITS = 2,
	RECORD_BYTES = 16,
	RECORD_POSITION_BITS = 20,
	RECORD_TOP_BITS = 4,
	RECORD_QUANTUM = 1 / 64,
	RECORD_HEIGHT_QUANTUM = 1 / 32,
	HEIGHT_MIN = -1024,
	HEIGHT_MAX = 1024,
	SLOT_BITS = 12,
	GENERATION_BITS = 4,
	SLOTS = 4096,
	PLATFORM_BITS = 7,
	MAX_PLATFORMS = 127,
	MAX_RELAY_BYTES = 896,
	RELAY_HEADER_BYTES = 9,
	REVEAL_BYTES = 3,
	HIDE_BYTES = 2,
	MAX_RELAY_RECORDS = 55,
	LOOK_ENTRY_BYTES = 3,
	MAX_LOOK_ENTRY = 85,
	FOOTSTEP_BYTES = 10,
	MAX_WATCHERS = 31,
	CHANGE_HEADER_BYTES = 4,
	CHANGE_DEPTH = 32,
	TAP_BLOCK_BYTES = 65535,
	PLAYER_RAYS = 6,
	LYING_RAYS = 3,
	MAX_SLOT_ENTRIES = 255,
	PUSH_STEPS = 127,
	FEED_LOOK_BYTES = 6,
	MAX_FEED = 142,
	KEYFRAME_HEADER_BYTES = 12,
	KEYFRAME_CHARACTER_BYTES = 19,
	KEYFRAME_PLATFORM_BYTES = 5,
	FNV_OFFSET = 0x811C9DC5,
	FNV_PRIME = 0x01000193,
}

return function (): (boolean, string | nil)
	local constants: { [string]: any } = Environment.load(CONSTANTS)

	for name: string, value: number in EXPECTED do
		local held: any = constants[name]
		if type(held) ~= "number" then
			return false, `{name} is a {type(held)}, not a number`
		end

		if held ~= value then
			return false, `{name} is {held}, where its layout gives {value}`
		end
	end

	for name: string in constants do
		if EXPECTED[name] == nil then
			return false, `{name} is a constant this case gives no value for`
		end
	end

	return true, nil
end
