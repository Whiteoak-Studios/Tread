--[[
    The range query names the players within a range of a point in three
    dimensions, the edge included, and leaves out every one past it
--]]

--!strict
local Environment = require("../../Environment")

local RANGE: string = "src/Server/Range.luau"
local STUDS: number = 10

type Place = { slot: number, position: vector, name: string }

-- Each name says where its player stands from the origin
local PLACES: { Place } = {
	{ slot = 0, position = vector.create(3, 0, 0), name = "Inside" },
	{ slot = 1, position = vector.create(6, 8, 0), name = "OnTheEdge" },
	{ slot = 2, position = vector.create(6, 8, 0.01), name = "JustPast" },
	{ slot = 3, position = vector.create(0, 10.01, 0), name = "JustAbove" },
	{ slot = 4, position = vector.create(-4, -4, -4), name = "BelowBehind" },
	{ slot = 5, position = vector.create(500, 0, 0), name = "FarOff" },
}

return function (): (boolean, string | nil)
	local Range = Environment.load(RANGE)
	local origin: vector = vector.create(0, 0, 0)

	for _, place: Place in PLACES do
		Range.set(place.slot, place.position, place.name)
	end

	local near: { string } = Range.near(origin, STUDS)
	table.sort(near)
	local found: string = table.concat(near, " ")
	if found ~= "BelowBehind Inside OnTheEdge" then
		return false, `Within {STUDS} studs of the origin the query named {found}`
	end

	local far: { string } = Range.near(vector.create(500, 0, 5), STUDS)
	if #far ~= 1 or far[1] ~= "FarOff" then
		return false, `Around the far player the query named {table.concat(far, " ")}, not FarOff alone`
	end

	local exact: { string } = Range.near(vector.create(3, 0, 0), 0)
	if #exact ~= 1 or exact[1] ~= "Inside" then
		return false, `A range of 0 named {table.concat(exact, " ")}, not the one player standing on the point`
	end

	local every: { string } = Range.near(origin, math.huge)
	if #every ~= #PLACES then
		return false, `An unbounded range named {#every} players, not all {#PLACES}`
	end

	if #Range.npcsNear(origin, math.huge) ~= 0 then
		return false, "The NPC query returned a player's slot"
	end

	return true, nil
end
