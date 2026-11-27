--[[
    The state word packs every mode, posture, water level, counter value,
    flag and epoch parity into its bits low first, in their order, and
    unpacks each back, the epoch as its parity
--]]

--!strict
local Environment = require("../../Environment")

local STATE_WORD: string = "src/Codec/StateWord.luau"
local MODES: { string } = { "Ground", "Air", "Swim", "Ladder", "Mantle" }
local POSTURES: { string } = { "Stand", "Crouch", "Downed" }
local WATER_LEVELS: { string } = { "Dry", "Wading", "Surface", "Under" }

local function word(): { [string]: any }
	return {
		mode = "Ground",
		posture = "Stand",
		sprint = false,
		aim = false,
		waterLevel = "Dry",
		jumps = 0,
		lands = 0,
		heavy = false,
		epoch = 0,
	}
end

return function (): (boolean, string | nil)
	local StateWord: any = Environment.load(STATE_WORD)

	-- Mode in bits 0 to 2, posture 3 and 4, sprint 5, aim 6, water 7 and 8, jumps 9 and 10, lands 11 and 12,
	-- heavy 13 and the epoch's parity 14 and 15
	local all: { [string]: any } = {
		mode = "Mantle",
		posture = "Downed",
		sprint = true,
		aim = true,
		waterLevel = "Under",
		jumps = 3,
		lands = 2,
		heavy = true,
		epoch = 255,
	}
	local expected: number = 4 + 2 * 8 + 32 + 64 + 3 * 128 + 3 * 512 + 2 * 2048 + 8192 + 3 * 16384
	if StateWord.pack(all) ~= expected then
		return false, `Every field set packed to {StateWord.pack(all)}, where its bits make {expected}`
	elseif StateWord.pack(word()) ~= 0 then
		return false, "A word at rest packed to other than 0"
	end

	local into: { [string]: any } = word()
	StateWord.unpack(expected, into)
	for key: string, value: any in all do
		local back: any = into[key]
		if key == "epoch" then
			value = 3
		end

		if back ~= value then
			return false, `{key} unpacked as {back}, where it was packed as {value}`
		end
	end

	-- Every value of each field alone round-trips, and touches no other field's bits
	local fields: { [string]: { any } } = {
		mode = MODES,
		posture = POSTURES,
		waterLevel = WATER_LEVELS,
		jumps = { 0, 1, 2, 3 },
		lands = { 0, 1, 2, 3 },
		sprint = { false, true },
		aim = { false, true },
		heavy = { false, true },
		epoch = { 0, 1, 2, 3, 4, 254, 255 },
	}

	for key: string, values: { any } in fields do
		for _, value: any in values do
			local state: { [string]: any } = word()
			state[key] = value

			local back: { [string]: any } = word()
			StateWord.unpack(StateWord.pack(state), back)
			if key == "epoch" then
				state.epoch = value % 4
			end

			for field: string, packed: any in state do
				if back[field] ~= packed then
					return false, `{key} at {value} unpacked {field} as {back[field]}, not {packed}`
				end
			end
		end
	end

	return true, nil
end
