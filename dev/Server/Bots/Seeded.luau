--[[
    A seeded number generator, Park and Miller's minimal standard, which
    draws the same numbers for a seed in Lune and in a Roblox server
--]]

--!strict
local Seeded = {}
Seeded.__index = Seeded

local MODULUS: number = 2 ^ 31 - 1 -- The generator's prime, inside which every product stays exact in a double
local MULTIPLIER: number = 48271

type Fields = {
	_state: number, -- From 1 to MODULUS - 1, never 0
}

--[[
    A generator from a whole seed. Any whole number seeds one, a seed that
    lands on 0 inside the modulus taking 1 instead
--]]

function Seeded.new(seed: number): Self
	if type(seed) ~= "number" or seed % 1 ~= 0 then
		error(`Seeded.new takes a whole number, not {seed}`, 2)
	end

	local state: number = seed % MODULUS
	if state == 0 then
		state = 1
	end

	return setmetatable({ _state = state }, Seeded)
end

-- The next number from 0 up to but never 1
function Seeded.next(self: Self): number
	self._state = self._state * MULTIPLIER % MODULUS

	return (self._state - 1) / (MODULUS - 1)
end

-- A number from min up to but never max
function Seeded.number(self: Self, min: number, max: number): number
	return min + (max - min) * self:next()
end

-- A whole number from min to max, both included
function Seeded.integer(self: Self, min: number, max: number): number
	return min + math.floor((max - min + 1) * self:next())
end

export type Seeded = Self
type Self = typeof(setmetatable({} :: Fields, Seeded))

return Seeded
