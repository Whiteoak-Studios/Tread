--[[
    The state word refuses a mode, posture or water level it gives no code
    and a counter past its 2 bits, and a word whose mode or posture code no
    value has
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local STATE_WORD: string = "src/Codec/StateWord.luau"

local function word(key: string, value: any): { [string]: any }
	local made: { [string]: any } = {
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
	made[key] = value

	return made
end

return function (): (boolean, string | nil)
	local StateWord: any = Environment.load(STATE_WORD)

	local packs: { { [string]: any } } = {
		word("mode", "Mounted"),
		word("posture", "Prone"),
		word("waterLevel", "Deep"),
		word("jumps", 4),
		word("lands", -1),
		word("jumps", 1.5),
	}

	for index: number, state: { [string]: any } in packs do
		local refused: boolean, why: string = Refuses("state word", StateWord.pack, state)
		if not refused then
			return false, `State {index} was packed: {why}`
		end
	end

	-- Mode codes 5 and 7 have no mode, the first kept for a mounted one and 6 the crouch slide's, and posture code
	-- 3 has none
	for _, packed: number in { 5, 7, 3 * 8 } do
		local refused: boolean, why: string = Refuses("is no state word", StateWord.unpack, packed, word("mode", "Air"))
		if not refused then
			return false, `The word {packed} was unpacked: {why}`
		end
	end

	return true, nil
end
