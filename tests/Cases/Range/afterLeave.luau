--[[
    A slot removed from the range query is never found again while the
    others still are, a second removal or one of a slot never set does
    nothing, and a removed slot can be set again
--]]

--!strict
local Environment = require("../../Environment")

local RANGE: string = "src/Server/Range.luau"
local STUDS: number = 100

return function (): (boolean, string | nil)
	local Range = Environment.load(RANGE)
	local origin: vector = vector.create(0, 0, 0)
	local names: { string } = { "First", "Second", "Third", "Fourth" }

	for slot: number, name: string in names do
		Range.set(slot, vector.create(slot, 0, 0), name)
	end

	for slot: number = 10, 12 do
		Range.set(slot, vector.create(0, slot, 0))
	end

	-- A leave from the middle of each list, then from its end
	Range.remove(2)
	Range.remove(3)
	Range.remove(11)
	Range.remove(12)

	local players: { string } = Range.near(origin, STUDS)
	table.sort(players)
	local left: string = table.concat(players, " ")
	local npcs: { number } = Range.npcsNear(origin, STUDS)
	if left ~= "First Fourth" then
		return false, `After two players left the query named {left}, not First Fourth`
	elseif #npcs ~= 1 or npcs[1] ~= 10 then
		return false, "After two NPCs left the NPC query gave another set than the one left"
	end

	local again: boolean, problem: any = pcall(Range.remove, 2)
	local never: boolean, neverProblem: any = pcall(Range.remove, 300)
	if not again or not never then
		return false, `Removing a slot already gone or never set threw: {problem or neverProblem}`
	end

	Range.set(2, vector.create(2, 0, 0), "Returned")

	local returned: { string } = Range.near(origin, STUDS)
	table.sort(returned)
	local back: string = table.concat(returned, " ")
	if back ~= "First Fourth Returned" then
		return false, `A slot set again after its removal left the query naming {back}`
	end

	return true, nil
end
