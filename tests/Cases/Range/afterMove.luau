--[[
    A slot set again moves to its new place, so the query finds a player or
    NPC that moved into range and drops one that moved out
--]]

--!strict
local Environment = require("../../Environment")

local RANGE: string = "src/Server/Range.luau"
local STUDS: number = 950 -- Frontier Zero's relevancy enter radius
local PLAYER: number = 12
local NPC: number = 40

return function (): (boolean, string | nil)
	local Range = Environment.load(RANGE)
	local origin: vector = vector.create(0, 0, 0)
	local outside: vector = vector.create(0, 0, 2000)
	local inside: vector = vector.create(0, 0, 900)

	Range.set(PLAYER, outside, "Walker")
	Range.set(NPC, outside)

	if #Range.near(origin, STUDS) ~= 0 or #Range.npcsNear(origin, STUDS) ~= 0 then
		return false, "The query found a player or NPC that stood outside its range"
	end

	Range.set(PLAYER, inside, "Walker")
	Range.set(NPC, inside)

	local names: { string } = Range.near(origin, STUDS)
	local slots: { number } = Range.npcsNear(origin, STUDS)
	if #names ~= 1 or names[1] ~= "Walker" then
		return false, "The query missed a player that moved into range"
	elseif #slots ~= 1 or slots[1] ~= NPC then
		return false, "The NPC query missed an NPC that moved into range"
	end

	Range.set(PLAYER, outside, "Walker")
	Range.set(NPC, outside)

	if #Range.near(origin, STUDS) ~= 0 or #Range.npcsNear(origin, STUDS) ~= 0 then
		return false, "The query still found a player or NPC that moved out of range"
	end

	if #Range.near(outside, 0) ~= 1 or #Range.npcsNear(outside, 0) ~= 1 then
		return false, "A slot set many times is not found once, and only once, at the place it was last set"
	end

	return true, nil
end
