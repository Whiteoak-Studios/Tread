--[[
    Players and NPCs at the same place stay apart: near names the players
    only and npcsNear gives the NPC slots only, and a slot set with or
    without a name moves between the two
--]]

--!strict
local Environment = require("../../Environment")

local RANGE: string = "src/Server/Range.luau"
local STUDS: number = 5
local PLAYER: number = 0
local NPC: number = 1
local SWITCHED: number = 2

return function (): (boolean, string | nil)
	local Range = Environment.load(RANGE)
	local place: vector = vector.create(10, 0, 10)

	Range.set(PLAYER, place, "Player")
	Range.set(NPC, place)
	Range.set(SWITCHED, place)

	local names: { string } = Range.near(place, STUDS)
	local slots: { number } = Range.npcsNear(place, STUDS)
	table.sort(slots)

	if #names ~= 1 or names[1] ~= "Player" then
		return false, "near named another set than the one player"
	elseif #slots ~= 2 or slots[1] ~= NPC or slots[2] ~= SWITCHED then
		return false, "npcsNear gave another set than the two NPC slots"
	end

	-- An NPC's slot set with a name joins the players and leaves the NPCs
	Range.set(SWITCHED, place, "Woken")

	local joined: { string } = Range.near(place, STUDS)
	table.sort(joined)
	local npcs: { number } = Range.npcsNear(place, STUDS)

	if #joined ~= 2 or joined[1] ~= "Player" or joined[2] ~= "Woken" then
		return false, "A slot set with a name did not join the players"
	elseif #npcs ~= 1 or npcs[1] ~= NPC then
		return false, "A slot set with a name stayed among the NPCs"
	end

	-- Set without a name it goes back
	Range.set(SWITCHED, place)

	if #Range.near(place, STUDS) ~= 1 or #Range.npcsNear(place, STUDS) ~= 2 then
		return false, "A player's slot set without a name did not move back to the NPCs"
	end

	return true, nil
end
