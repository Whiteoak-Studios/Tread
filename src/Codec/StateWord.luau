--[[
    The state word, the u16 a character record and OwnerState carry: mode,
    posture, sprint, aim, water level, the jump and land counters, heavy
    landing and the epoch's parity, low bit first in that order
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)
local State = require(script.Parent.Parent.Step.State)

-- Each value's place in its list, from 0, is its code. Mantle's is the fifth, and the code after it stays free for a
-- mounted mode
local MODES: { State.Mode } = { "Ground", "Air", "Swim", "Ladder", "Mantle" }
local POSTURES: { State.Posture } = { "Stand", "Crouch", "Downed" }
local WATER_LEVELS: { State.WaterLevel } = { "Dry", "Wading", "Surface", "Under" }

-- Each field's lowest bit, in packing order
local FLAG_BITS: number = 1
local MODE_AT: number = 0
local POSTURE_AT: number = MODE_AT + Constants.MODE_BITS
local SPRINT_AT: number = POSTURE_AT + Constants.POSTURE_BITS
local AIM_AT: number = SPRINT_AT + FLAG_BITS
local WATER_AT: number = AIM_AT + FLAG_BITS
local JUMPS_AT: number = WATER_AT + Constants.WATER_BITS
local LANDS_AT: number = JUMPS_AT + Constants.COUNTER_BITS
local HEAVY_AT: number = LANDS_AT + Constants.COUNTER_BITS
local EPOCH_AT: number = HEAVY_AT + FLAG_BITS

-- What the word holds of a step state, which a state or any table with these fields gives and takes
export type Word = {
	mode: State.Mode,
	posture: State.Posture,
	sprint: boolean,
	aim: boolean,
	waterLevel: State.WaterLevel,
	jumps: number, -- The 2-bit jump counter
	lands: number, -- The 2-bit land counter
	heavy: boolean,
	epoch: number, -- The full epoch, whose low 2 bits the word carries
}

local StateWord = {}

local function counter(value: number): number
	if bit32.extract(value, 0, Constants.COUNTER_BITS) ~= value then
		error(`A state word's counter holds 0 to 3, not {value}`)
	end

	return value
end

--[[
    Packs a state's word, erroring on a mode, posture or water level no code
    is given to and on a counter its 2 bits don't hold
--]]

function StateWord.pack(state: Word): number
	local mode: number? = table.find(MODES, state.mode)
	local posture: number? = table.find(POSTURES, state.posture)
	local water: number? = table.find(WATER_LEVELS, state.waterLevel)
	if not (mode and posture and water) then
		error(`A state word holds no {state.mode} mode, {state.posture} posture or {state.waterLevel} water level`)
	end

	local word: number = bit32.replace(0, mode - 1, MODE_AT, Constants.MODE_BITS)
	word = bit32.replace(word, posture - 1, POSTURE_AT, Constants.POSTURE_BITS)
	word = bit32.replace(word, state.sprint and 1 or 0, SPRINT_AT)
	word = bit32.replace(word, state.aim and 1 or 0, AIM_AT)
	word = bit32.replace(word, water - 1, WATER_AT, Constants.WATER_BITS)
	word = bit32.replace(word, counter(state.jumps), JUMPS_AT, Constants.COUNTER_BITS)
	word = bit32.replace(word, counter(state.lands), LANDS_AT, Constants.COUNTER_BITS)
	word = bit32.replace(word, state.heavy and 1 or 0, HEAVY_AT)
	word = bit32.replace(word, bit32.extract(state.epoch, 0, Constants.EPOCH_BITS), EPOCH_AT, Constants.EPOCH_BITS)

	return word
end

--[[
    Unpacks a word into into, its epoch as the word's 2-bit parity, which
    OwnerState's full epoch then replaces. It errors on a mode or posture
    code no value is given
--]]

function StateWord.unpack(word: number, into: Word)
	local mode: State.Mode? = MODES[bit32.extract(word, MODE_AT, Constants.MODE_BITS) + 1]
	local posture: State.Posture? = POSTURES[bit32.extract(word, POSTURE_AT, Constants.POSTURE_BITS) + 1]
	if not (mode and posture) then
		error(`{word} is no state word, since its mode or posture code has no value`)
	end

	into.mode = mode
	into.posture = posture
	into.sprint = bit32.extract(word, SPRINT_AT) == 1
	into.aim = bit32.extract(word, AIM_AT) == 1
	into.waterLevel = WATER_LEVELS[bit32.extract(word, WATER_AT, Constants.WATER_BITS) + 1]
	into.jumps = bit32.extract(word, JUMPS_AT, Constants.COUNTER_BITS)
	into.lands = bit32.extract(word, LANDS_AT, Constants.COUNTER_BITS)
	into.heavy = bit32.extract(word, HEAVY_AT) == 1
	into.epoch = bit32.extract(word, EPOCH_AT, Constants.EPOCH_BITS)
end

return StateWord
