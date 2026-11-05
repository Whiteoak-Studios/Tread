--[[
    Slots go out lowest first while any was never used, and a released slot
    waits behind every slot freed before it, so it comes back last
--]]

--!strict
local Environment = require("../../Environment")

local SLOTS: string = "src/Server/Slots.luau"
local CONSTANTS: string = "src/Constants.luau"

return function (): (boolean, string | nil)
	local Slots = Environment.load(SLOTS)
	local count: number = Environment.load(CONSTANTS).SLOTS

	Slots.start(0)

	for expected: number = 0, 2 do
		local slot: number? = Slots.take("Player")
		if slot ~= expected then
			return false, `A fresh table gave out slot {slot}, not {expected}`
		end
	end

	Slots.release(1)

	local next: number? = Slots.take("Npc")
	if next ~= 3 then
		return false, `After slot 1 was released the next take gave {next}, not the never-used slot 3`
	end

	for expected: number = 4, count - 1 do
		local slot: number? = Slots.take("Body")
		if slot ~= expected then
			return false, `Filling the table gave out slot {slot}, not {expected}`
		end
	end

	local back: number? = Slots.take("Player")
	if back ~= 1 then
		return false, `Once every never-used slot was taken the next take gave {back}, not the released slot 1`
	end

	local released: { number } = { 9, 4, count - 1, 0 }
	for _, slot: number in released do
		Slots.release(slot)
	end

	for _, expected: number in released do
		local slot: number? = Slots.take("Sleeper")
		if slot ~= expected then
			return false, `Released slots came back with {slot} where {expected}, the next released, was due`
		end
	end

	return true, nil
end
