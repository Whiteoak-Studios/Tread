--[[
    Every slot's first life carries generation 1, a released slot keeps its
    last life's, and each retake raises it by one, wrapping inside its bits
--]]

--!strict
local Environment = require("../../Environment")

local SLOTS: string = "src/Server/Slots.luau"
local CONSTANTS: string = "src/Constants.luau"
local SLOT: number = 5
local FIRST: number = 1
local LIVES: number = 3 -- Laps of every generation the slot runs through

return function (): (boolean, string | nil)
	local Slots = Environment.load(SLOTS)
	local constants: { [string]: number } = Environment.load(CONSTANTS)
	local generations: number = 2 ^ constants.GENERATION_BITS

	Slots.start(0)

	for _ = 1, constants.SLOTS do
		local slot: number?, generation: number? = Slots.take("Player")
		if generation ~= FIRST then
			return false, `Slot {slot}'s first life carries generation {generation}, not {FIRST}`
		end
	end

	Slots.release(SLOT)

	local kept: number = Slots.get(SLOT)
	if kept ~= FIRST then
		return false, `A released slot reads generation {kept}, not its last life's {FIRST}`
	end

	local previous: number = FIRST
	for _ = 1, LIVES * generations do
		local slot: number?, generation: number? = Slots.take("Player")
		local expected: number = (previous + 1) % generations

		if slot ~= SLOT then
			return false, `The one free slot went out as {slot}, not {SLOT}`
		elseif generation ~= expected then
			return false, `A retake after generation {previous} carries {generation}, not {expected}`
		elseif Slots.get(SLOT) ~= generation then
			return false, "Slots.get reads another generation than the take gave"
		end

		previous = expected
		Slots.release(SLOT)
	end

	if previous ~= FIRST then
		return false, `After {LIVES} laps the slot is at generation {previous}, not back at {FIRST}`
	end

	return true, nil
end
