--[[
    The probe's cast record through a stand-in Collision that reuses one hit
    table: a hit's fields in place with its material's Value, zeros for a
    miss, -1 for a part outside the index or none, and a rest's height
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local PLAN_WIDTH: number = 8
local RESULT_WIDTH: number = 9
local F64_BYTES: number = 8
local HULL: { number } = { 3, 5, 3 }
local RAY: number = 1
local SWEEP: number = 2
local SPHERE: number = 3
local REST: number = 4
local RAY_DISTANCE: number = 2.5 -- What the stand-in ray reports, a quarter of the way along
local RAY_SHARE: number = 0.25
local SPHERE_REACH: number = 3 -- The stand-in sphere's distance, in radii
local SLATE: number = 800 -- Enum.Material's Values
local GRASS: number = 1280
local WOOD: number = 512

-- Each query: its kind, origin, direction and radius
local PLAN: { { number } } = {
	{ RAY, 1, 2, 3, 0, -8, 0, 0 }, -- Hits the first indexed part
	{ SPHERE, 4, 5, 6, 0, 0, -2, 0.5 }, -- Hits the second, before the ray's hit can be read late
	{ SWEEP, -1, 2, 3, 8, 0, 0, 0 }, -- Hits a part outside the index
	{ RAY, -1, 2, 3, 0, -8, 0, 0 }, -- Misses
	{ REST, 0, 7, 0, 0, 0, 0, 0 }, -- Finds a height
	{ REST, 0, -7, 0, 0, 0, 0, 0 }, -- Finds none
	{ SWEEP, -1, 2, 3, 0, 4, 0, 0 }, -- Hits with no instance
}

-- What each query records, worked from the stand-in's rules below
local EXPECTED: { { number } } = {
	{ 1, 1, 0, 3, 0, 1, 0, RAY_DISTANCE, SLATE },
	{ 2, 4, 5, 5.5, 0, 0, 1, 0.5 * SPHERE_REACH, GRASS },
	{ -1, 2, 2, 3, -1, 0, 0, HULL[1], WOOD },
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 1, 0, 0, 0, 0, 0, 0, 7 - HULL[2], 0 },
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ -1, 2, 2, 3, -1, 0, 0, HULL[1], WOOD },
}

local FIELDS: { string } =
	{ "index", "position.x", "position.y", "position.z", "normal.x", "normal.y", "normal.z", "distance", "material" }

--[[
    The stand-in casts, each deterministic from its inputs and filling the
    one hit table every cast hands back, as the engine's casts do: a ray
    with a positive x hits the first part a quarter along, a sphere hits the
    second three radii along, a sweep hits a box's width along x, on the
    outsider when it moves along x and on nothing otherwise, and a rest
    finds the box's height under its center when it starts above 0
--]]

local function standIn(first: any, second: any, outsider: any): any
	local hit: any = { distance = 0, position = vector.zero, normal = vector.zero, material = nil, instance = nil }

	local function fill(distance: number, position: vector, normal: vector, material: any, instance: any): any
		hit.distance = distance
		hit.position = position
		hit.normal = normal
		hit.material = material
		hit.instance = instance

		return hit
	end

	return {
		ray = function (origin: vector, direction: vector): any
			if origin.x <= 0 then
				return nil
			end

			local position: vector = origin + direction * RAY_SHARE
			return fill(RAY_DISTANCE, position, vector.create(0, 1, 0), roblox.Enum.Material.Slate, first)
		end,

		sphere = function (origin: vector, radius: number, _direction: vector): any
			local position: vector = origin - vector.create(0, 0, radius)
			local distance: number = radius * SPHERE_REACH
			return fill(distance, position, vector.create(0, 0, 1), roblox.Enum.Material.Grass, second)
		end,

		sweep = function (origin: vector, size: vector, direction: vector): any
			local instance: any = direction.x > 0 and outsider or nil
			local position: vector = origin + vector.create(size.x, 0, 0)
			return fill(size.x, position, vector.create(-1, 0, 0), roblox.Enum.Material.Wood, instance)
		end,

		rest = function (origin: vector, size: vector): number?
			if origin.y <= 0 then
				return nil
			end

			return origin.y - size.y
		end,

		overlap = function (): boolean
			return false
		end,

		destroy = function () end,
	}
end

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Queries: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Queries)

	local first: any = roblox.Instance.new("Part")
	local second: any = roblox.Instance.new("Part")
	local outsider: any = roblox.Instance.new("Part")
	local index: { [any]: number } = Queries.indexOf({ first, second })
	if index[first] ~= 1 or index[second] ~= 2 or index[outsider] ~= nil then
		return false,
			`The index put the parts at {index[first]} and {index[second]}, and the outsider at {index[outsider]}`
	end

	local plan: buffer = buffer.create(#PLAN * PLAN_WIDTH * F64_BYTES)
	for query: number, values: { number } in PLAN do
		for field: number, value: number in values do
			buffer.writef64(plan, ((query - 1) * PLAN_WIDTH + field - 1) * F64_BYTES, value)
		end
	end

	local hull: any = roblox.Vector3.new(HULL[1], HULL[2], HULL[3])
	local results: buffer = Queries.cast(plan, hull, standIn(first, second, outsider), index)
	if buffer.len(results) ~= #PLAN * RESULT_WIDTH * F64_BYTES then
		return false, `{#PLAN} queries gave {buffer.len(results)} B of results`
	end

	for query: number, expected: { number } in EXPECTED do
		for field: number, value: number in expected do
			local got: number = buffer.readf64(results, ((query - 1) * RESULT_WIDTH + field - 1) * F64_BYTES)
			if got ~= value then
				return false, `Query {query}'s {FIELDS[field]} recorded {got}, not {value}`
			end
		end
	end

	return true, nil
end
