--[[
    Wrap-safe compares of Tread's u16 wire numbers: command numbers, relay
    sequences, wire ticks and the yaw steps of a turn
--]]

--!strict
--!native

local WRAP: number = 2 ^ 16 -- The numbers a u16 holds
local HALF: number = WRAP / 2

local Sequence = {}

--[[
    The signed difference a - b of two u16 wire numbers, from -32,768 to
    32,767, the shorter way round the wrap, so a is newer than b when it is
    above 0. Two yaws' difference is the shortest arc from b to a
--]]

function Sequence.difference(a: number, b: number): number
	return (a - b + HALF) % WRAP - HALF
end

return Sequence
