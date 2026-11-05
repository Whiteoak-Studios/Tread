--[[
    Tread's wire and parity invariants: the layouts' version, sizes and
    precisions, and the step's quantum, skin and bounds, which the server,
    every client and every recorded clip must agree on bit for bit
--]]

--!strict
local CODEC_VERSION: number = 1 -- Raised whenever a wire layout changes, and carried in every keyframe
local PREFIX_BYTES: number = 1 -- The u8 length or count in front of a block of game fields or a list

-- The step state, quantized after every step to the precisions OwnerState carries
local POSITION_QUANTUM: number = 1 / 512 -- Studs a position's axes and the fall apex step by, each an i24
local VELOCITY_QUANTUM: number = 1 / 64 -- Studs a second a velocity steps by, each axis an i16
local VELOCITY_LIMIT: number = 2 ^ 15 * VELOCITY_QUANTUM -- 512 studs a second either way, what that i16 holds
local EYE_QUANTUM: number = 1 / 32 -- Studs the eased eye height and the mantle's rise step by, each a u8
local SKIN: number = 0.02 -- Studs collide-and-slide keeps between the hull and every surface
local MAX_BUMPS: number = 4 -- The most bumps one collide-and-slide move takes, each a hit and a slide
local CAST_REACH: number = 0.5 -- Studs a slide's cast reaches past its move, so a near miss keeps its skin too
local MIN_CREASE: number = 1e-3 -- How nearly parallel two surfaces may be before the line they meet on gives no way
local DEPENETRATION_FIRST: number = 1 / 16 -- Hull widths depenetration first tries a spot at, each next one twice that
local DEPENETRATION_STEPS: number = 5 -- The distances depenetration tries, the last one a whole hull width
local PLAY_BOUND: number = 8192 -- Studs from 0 a position's X and Z may reach either way, whatever the map's size

-- Angles, which a u16 or i16 counts in steps of the turn
local ANGLE_STEPS: number = 65536
local PITCH_LIMIT: number = ANGLE_STEPS // 4 -- A command's pitch either way, a quarter turn
local LEAN_STEPS: number = 127 -- A command's and a record's i8 lean, steps to the game's lean limit
local HEAD_STEPS: number = 127 -- A command's i8 head offset yaw and pitch, steps to the game's cone limits
local HEAD_LEVELS: number = 7 -- A record's signed 4-bit head offset yaw and pitch, steps to the cone limits
local RECORD_PITCH_STEPS: number = 127 -- A record's i8 pitch, steps to 90°

-- The Move, client to server once a relay tick
local MAX_COMMANDS: number = 8
local MOVE_REPEATS: number = 2 -- The commands each Move repeats before its new ones, so one lost Move costs nothing
local COMMAND_BYTES: number = 11 -- Tread's own fields in a command, before the game's
local ACK_MASK_BITS: number = 16 -- The relay sequences before the newest acknowledged one that a Move's mask covers
local FIRST_SEQUENCE: number = 1 -- The first relay sequence a viewer is sent, so an acknowledgment of 0 means none

-- The game's declared blocks, each the most bytes its largest packing may fill
local MAX_COMMAND_FIELDS: number = 64 -- A command's game fields
local MAX_SERVER_SET: number = 16 -- OwnerState's server-set block
local MAX_RULE_STATE: number = 32 -- OwnerState's rule-state block
local MAX_LOOK: number = 64 -- The slot-table fields, a character's look
local MAX_HELD: number = 16 -- The held-item fields

-- OwnerState, server to owner once a relay tick: Tread's fields, then the two game blocks behind their prefixes
local OWNER_STATE_BYTES: number = 41
local MAX_OWNER_STATE: number = OWNER_STATE_BYTES + PREFIX_BYTES + MAX_SERVER_SET + PREFIX_BYTES + MAX_RULE_STATE

-- The state word's fields wider than a bit, beside its sprint, aim and heavy landing flags
local MODE_BITS: number = 3 -- The step's mode, with two values spare
local POSTURE_BITS: number = 2
local WATER_BITS: number = 2 -- Dry, wading, surface swim and head under
local COUNTER_BITS: number = 2 -- Each of the jump and land counters
local EPOCH_BITS: number = 2 -- The epoch's parity
local MOVE_MODE_BITS: number = 2 -- In OwnerState's mode byte, beside the grounded bit

-- The character record, encoded once per target per tick and copied to each viewer
local RECORD_BYTES: number = 16
local RECORD_POSITION_BITS: number = 20 -- The low bits of the record's u24 X and Z that hold the position
local RECORD_TOP_BITS: number = 24 - RECORD_POSITION_BITS -- The bits above them in each u24
local RECORD_QUANTUM: number = 1 / 64 -- Studs a record's or a footstep's X and Z step by
local RECORD_HEIGHT_QUANTUM: number = 1 / 32 -- Studs a record's or a footstep's u16 Y steps by
local HEIGHT_MIN: number = -1024 -- The bottom of the window that u16 Y spans, in studs
local HEIGHT_MAX: number = 1024 -- Its top
local SLOT_BITS: number = 12 -- The slot in the record's slot and generation u16
local GENERATION_BITS: number = 4 -- The generation beside it
local SLOTS: number = 2 ^ SLOT_BITS -- The character slots every kind shares
local PLATFORM_BITS: number = 7 -- The platform index the top bits of X and Z hold, beside a 1-bit selector
local MAX_PLATFORMS: number = 2 ^ PLATFORM_BITS - 1 -- Platform ids 1 up, since index 0 means world coordinates

-- The relay block, server to viewer, whose 896 B fit Volt's unreliable budget with its framing
local MAX_RELAY_BYTES: number = 896 -- The withheld block's bound too
local RELAY_HEADER_BYTES: number = 8 -- The sequence, the relay tick and the counts of its four sections
local REVEAL_BYTES: number = 3 -- A reveal-and-kind entry: slot and generation, then kind
local HIDE_BYTES: number = 2 -- A hide entry: slot and generation
local MAX_RELAY_RECORDS: number = (MAX_RELAY_BYTES - RELAY_HEADER_BYTES) // RECORD_BYTES -- Withheld blocks' too
local LOOK_ENTRY_BYTES: number = 3 -- A look entry's slot and generation and flags, before each present part
local MAX_LOOK_ENTRY: number = LOOK_ENTRY_BYTES + PREFIX_BYTES + MAX_LOOK + PREFIX_BYTES + MAX_HELD
local FOOTSTEP_BYTES: number = 10 -- X and Z u24, Y u16, then the ground material u16

local MAX_SLOT_ENTRIES: number = 255 -- The slot-table entries one Slots message carries

-- The moderator's feed: OwnerState behind its length, then a count and at most a Move's worth of command looks
local FEED_LOOK_BYTES: number = 6 -- One stepped command's yaw, pitch and head offset
local MAX_FEED: number = PREFIX_BYTES + MAX_OWNER_STATE + PREFIX_BYTES + MAX_COMMANDS * FEED_LOOK_BYTES

-- The keyframe a clip ring starts from, which never goes on the wire as it is
local KEYFRAME_HEADER_BYTES: number = 12 -- The version, the declarations' hash, the relay tick, sequence and count
local KEYFRAME_CHARACTER_BYTES: number = 1 + RECORD_BYTES + 2 * PREFIX_BYTES -- Kind, record, look and held prefixes
local KEYFRAME_PLATFORM_BYTES: number = 5 -- A called platform's id and its latest press tick

return {
	CODEC_VERSION = CODEC_VERSION,
	PREFIX_BYTES = PREFIX_BYTES,
	POSITION_QUANTUM = POSITION_QUANTUM,
	VELOCITY_QUANTUM = VELOCITY_QUANTUM,
	VELOCITY_LIMIT = VELOCITY_LIMIT,
	EYE_QUANTUM = EYE_QUANTUM,
	SKIN = SKIN,
	MAX_BUMPS = MAX_BUMPS,
	CAST_REACH = CAST_REACH,
	MIN_CREASE = MIN_CREASE,
	DEPENETRATION_FIRST = DEPENETRATION_FIRST,
	DEPENETRATION_STEPS = DEPENETRATION_STEPS,
	PLAY_BOUND = PLAY_BOUND,
	ANGLE_STEPS = ANGLE_STEPS,
	PITCH_LIMIT = PITCH_LIMIT,
	LEAN_STEPS = LEAN_STEPS,
	HEAD_STEPS = HEAD_STEPS,
	HEAD_LEVELS = HEAD_LEVELS,
	RECORD_PITCH_STEPS = RECORD_PITCH_STEPS,
	MAX_COMMANDS = MAX_COMMANDS,
	MOVE_REPEATS = MOVE_REPEATS,
	COMMAND_BYTES = COMMAND_BYTES,
	ACK_MASK_BITS = ACK_MASK_BITS,
	FIRST_SEQUENCE = FIRST_SEQUENCE,
	MAX_COMMAND_FIELDS = MAX_COMMAND_FIELDS,
	MAX_SERVER_SET = MAX_SERVER_SET,
	MAX_RULE_STATE = MAX_RULE_STATE,
	MAX_LOOK = MAX_LOOK,
	MAX_HELD = MAX_HELD,
	OWNER_STATE_BYTES = OWNER_STATE_BYTES,
	MAX_OWNER_STATE = MAX_OWNER_STATE,
	MODE_BITS = MODE_BITS,
	POSTURE_BITS = POSTURE_BITS,
	WATER_BITS = WATER_BITS,
	COUNTER_BITS = COUNTER_BITS,
	EPOCH_BITS = EPOCH_BITS,
	MOVE_MODE_BITS = MOVE_MODE_BITS,
	RECORD_BYTES = RECORD_BYTES,
	RECORD_POSITION_BITS = RECORD_POSITION_BITS,
	RECORD_TOP_BITS = RECORD_TOP_BITS,
	RECORD_QUANTUM = RECORD_QUANTUM,
	RECORD_HEIGHT_QUANTUM = RECORD_HEIGHT_QUANTUM,
	HEIGHT_MIN = HEIGHT_MIN,
	HEIGHT_MAX = HEIGHT_MAX,
	SLOT_BITS = SLOT_BITS,
	GENERATION_BITS = GENERATION_BITS,
	SLOTS = SLOTS,
	PLATFORM_BITS = PLATFORM_BITS,
	MAX_PLATFORMS = MAX_PLATFORMS,
	MAX_RELAY_BYTES = MAX_RELAY_BYTES,
	RELAY_HEADER_BYTES = RELAY_HEADER_BYTES,
	REVEAL_BYTES = REVEAL_BYTES,
	HIDE_BYTES = HIDE_BYTES,
	MAX_RELAY_RECORDS = MAX_RELAY_RECORDS,
	LOOK_ENTRY_BYTES = LOOK_ENTRY_BYTES,
	MAX_LOOK_ENTRY = MAX_LOOK_ENTRY,
	FOOTSTEP_BYTES = FOOTSTEP_BYTES,
	MAX_SLOT_ENTRIES = MAX_SLOT_ENTRIES,
	FEED_LOOK_BYTES = FEED_LOOK_BYTES,
	MAX_FEED = MAX_FEED,
	KEYFRAME_HEADER_BYTES = KEYFRAME_HEADER_BYTES,
	KEYFRAME_CHARACTER_BYTES = KEYFRAME_CHARACTER_BYTES,
	KEYFRAME_PLATFORM_BYTES = KEYFRAME_PLATFORM_BYTES,
}
