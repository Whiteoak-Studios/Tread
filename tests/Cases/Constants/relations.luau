--[[
    The relations the layouts rest on hold between the constants: what each
    block, record and entry fills, and the range each field's bits cover
--]]

--!strict
local Environment = require("../../Environment")

local CONSTANTS: string = "src/Constants.luau"

type Relation = { relation: string, holds: boolean }

return function (): (boolean, string | nil)
	local constants: { [string]: number } = Environment.load(CONSTANTS)

	local recordsFill: number = constants.RELAY_HEADER_BYTES + constants.MAX_RELAY_RECORDS * constants.RECORD_BYTES
	local largestReveal: number = constants.REVEAL_BYTES + constants.MAX_LOOK_ENTRY + constants.RECORD_BYTES

	local relations: { Relation } = {
		{
			relation = "the header and 55 records fill 888 B of the 896 B relay block, and a 56th passes it",
			holds = recordsFill == 888
				and recordsFill <= constants.MAX_RELAY_BYTES
				and recordsFill + constants.RECORD_BYTES > constants.MAX_RELAY_BYTES,
		},

		{
			relation = "12 bits of slot hold the 4,096 slots, and slot and generation fill the record's u16",
			holds = 2 ^ constants.SLOT_BITS == constants.SLOTS
				and constants.SLOTS == 4096
				and constants.SLOT_BITS + constants.GENERATION_BITS == 16,
		},

		{
			relation = "20 bits at 1/64 stud cover the ±8,192-stud play bound",
			holds = 2 ^ constants.RECORD_POSITION_BITS * constants.RECORD_QUANTUM == 2 * constants.PLAY_BOUND,
		},

		{
			relation = "the record's u16 Y at 1/32 stud spans its window from -1,024 to 1,024 studs",
			holds = 2 ^ 16 * constants.RECORD_HEIGHT_QUANTUM == constants.HEIGHT_MAX - constants.HEIGHT_MIN,
		},

		{
			relation = "OwnerState's i24 position at 1/512 stud reaches the play bound",
			holds = 2 ^ 23 * constants.POSITION_QUANTUM >= constants.PLAY_BOUND,
		},

		{
			relation = "OwnerState's i16 velocity at 1/64 stud a second reaches 512 studs a second",
			holds = constants.VELOCITY_LIMIT == 512,
		},

		{
			relation = "the 4 bits above the position in X and Z hold a 7-bit platform index and a 1-bit selector",
			holds = constants.RECORD_POSITION_BITS + constants.RECORD_TOP_BITS == 24
				and constants.PLATFORM_BITS + 1 == 2 * constants.RECORD_TOP_BITS
				and constants.MAX_PLATFORMS == 127,
		},

		{
			relation = "slot and generation, X, Z, Y, yaw, pitch, the state word and the last byte fill the 16 B record",
			holds = 2 + 3 + 3 + 2 + 2 + 1 + 2 + 1 == constants.RECORD_BYTES,
		},

		{
			relation = "the state word's fields and its three flags fill its u16, the mode's bits with two values spare",
			holds = constants.MODE_BITS
						+ constants.POSTURE_BITS
						+ constants.WATER_BITS
						+ 2 * constants.COUNTER_BITS
						+ constants.EPOCH_BITS
						+ 3
					== 16
				and 2 ^ constants.MODE_BITS - 6 == 2,
		},

		{
			relation = "OwnerState's own fields fill 38 B, and with both game blocks at their bounds 88 B",
			holds = 2 + 2 + 1 + 3 * 3 + 3 * 2 + 2 + 2 + 1 + 1 + 1 + 1 + 1 + 3 + 1 + 1 + 1 + 1 + 2
					== constants.OWNER_STATE_BYTES
				and constants.MAX_OWNER_STATE == 88,
		},

		{
			relation = "a command's own fields fill 11 B, and its pitch limit is a quarter turn",
			holds = 1 + 1 + 2 + 2 + 2 + 1 + 1 + 1 == constants.COMMAND_BYTES
				and constants.PITCH_LIMIT * 4 == constants.ANGLE_STEPS,
		},

		{
			relation = "a look entry is 4 B with one part's prefix and at most 85 B with both parts",
			holds = constants.LOOK_ENTRY_BYTES + constants.PREFIX_BYTES == 4 and constants.MAX_LOOK_ENTRY == 85,
		},

		{
			relation = "a reveal with both look parts and its record is at most 104 B, and 8 fit beside the header",
			holds = largestReveal == 104
				and constants.RELAY_HEADER_BYTES + 8 * largestReveal <= constants.MAX_RELAY_BYTES
				and constants.RELAY_HEADER_BYTES + 9 * largestReveal > constants.MAX_RELAY_BYTES,
		},

		{
			relation = "a footstep entry's X, Z, Y and ground material fill its 10 B",
			holds = 3 + 3 + 2 + 2 == constants.FOOTSTEP_BYTES,
		},

		{
			relation = "the moderator's feed is at most 138 B",
			holds = constants.MAX_FEED == 138,
		},

		{
			relation = "a keyframe opens with 12 B, and each character takes 19 B and each platform 5 B",
			holds = 2 + 4 + 2 + 2 + 2 == constants.KEYFRAME_HEADER_BYTES
				and constants.KEYFRAME_CHARACTER_BYTES == 19
				and 1 + 4 == constants.KEYFRAME_PLATFORM_BYTES,
		},

		{
			relation = "the whole slot table goes out in at most 17 messages",
			holds = math.ceil(constants.SLOTS / constants.MAX_SLOT_ENTRIES) == 17,
		},

		{
			relation = "every i8 step count is the 127 an i8 holds each way, and the nibble's head levels its 7",
			holds = constants.LEAN_STEPS == 2 ^ 7 - 1
				and constants.HEAD_STEPS == 2 ^ 7 - 1
				and constants.RECORD_PITCH_STEPS == 2 ^ 7 - 1
				and constants.HEAD_LEVELS == 2 ^ 3 - 1,
		},
	}

	for _, row: Relation in relations do
		if not row.holds then
			return false, `The layouts rest on {row.relation}, which the constants break`
		end
	end

	return true, nil
end
