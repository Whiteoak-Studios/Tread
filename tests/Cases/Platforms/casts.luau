--[[
    The first platform wraps the world's casts and the last one out puts
    them back: every sweep, rest, ray, sphere and overlap meets the boxes
    where the path puts them on the tick the world runs, a box hit is
    Plastic with no instance, the nearer hit answers and the casts' own
    on a tie, and the wrapper's destroy reaches the casts under it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local PLATFORMS: string = "src/Step/Platforms.luau"
local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"

local HIGH: number = 1120 -- The rising box's center on tick 0, clear of every fixture part
local X: number = -20 -- Where the boxes stand, over the fixture floor and clear of its other parts
local Z: number = 20
local TICK: number = 100
local TOLERANCE: number = 1e-9

local function near(a: number, b: number): boolean
	return math.abs(a - b) <= TOLERANCE
end

-- A box 4 studs across and 1 high, centered where the path puts it, rising a stud a tick
local function rising(id: number): { [string]: any }
	return {
		id = id,
		boxes = { { center = roblox.Vector3.zero, size = roblox.Vector3.new(4, 1, 4) } },
		path = function (tick: number, _: number?): any
			return roblox.Vector3.new(X, HIGH + tick, Z)
		end,
	}
end

-- A still box of the size given, its center at y
local function still(id: number, y: number, size: any): { [string]: any }
	return {
		id = id,
		boxes = { { center = roblox.Vector3.zero, size = size } },
		path = function (_: number, _: number?): any
			return roblox.Vector3.new(X, y, Z)
		end,
	}
end

return function (): (boolean, string | nil)
	local Platforms: any = Environment.load(PLATFORMS)
	local Riders: any = Environment.load(RIDERS)
	local Geometry: any = Environment.load(GEOMETRY)
	local world: any = Riders.world()
	local casts: any = world.collision

	world.clock = TICK
	world.tick = TICK

	local remove: () -> () = Platforms.add(world, rising(1))
	local wrapped: any = world.collision
	if wrapped == casts then
		return false, "the first platform left the world's casts unwrapped"
	end

	-- 1) A sweep down onto the box's top where it stands on the world's tick, then on the next
	local top: number = HIGH + TICK + 0.5
	local from: number = top + 9 -- The swept box's center, a stud over its bottom
	local down: any = wrapped.sweep(vector.create(X, from, Z), vector.create(2, 2, 2), vector.create(0, -20, 0))
	if not down or not near(down.distance, 8) then
		return false, `a sweep down met the rising box at {down and down.distance}, not 8 studs down`
	elseif down.normal ~= vector.create(0, 1, 0) or down.material ~= roblox.Enum.Material.Plastic or down.instance then
		return false, `the box's hit had the normal {down.normal}, the material {down.material} and {down.instance}`
	end

	world.tick = TICK + 1
	local later: any = wrapped.sweep(vector.create(X, from, Z), vector.create(2, 2, 2), vector.create(0, -20, 0))
	if not later or not near(later.distance, 7) then
		return false, `on the next tick the sweep met the box at {later and later.distance}, not 7 studs down`
	end

	-- 2) A ray up into its bottom, and a sphere into its side, which meets it as the cube around it
	local ray: any = wrapped.ray(vector.create(X, top + 1 - 11, Z), vector.create(0, 20, 0))
	if not ray or not near(ray.distance, 10) or ray.normal ~= vector.create(0, -1, 0) then
		return false, `a ray up met the box at {ray and ray.distance}, not 10 studs up`
	end

	local side: any = wrapped.sphere(vector.create(X - 3, top + 0.5, Z), 0.5, vector.create(5, 0, 0))
	if not side or not near(side.distance, 0.5) or side.normal ~= vector.create(-1, 0, 0) then
		return false, `a sphere met the box's side at {side and side.distance}, not half a stud on`
	end

	-- 3) Rest finds its top under a box whose bottom is just over it, and passes by one whose top starts inside it
	local rest: number? = wrapped.rest(vector.create(X, top + 2 + 0.01, Z), vector.create(2, 2, 2))
	if rest ~= top + 1 then
		return false, `rest over the box gave {rest}, where its top at {top + 1} was expected`
	end

	local straddling: number? = wrapped.rest(vector.create(X, top - 0.5, Z), vector.create(2, 2, 2))
	if straddling ~= nil then
		return false, `rest from inside the box gave {straddling}, where an engine cast would pass it by`
	end

	-- 4) Overlap is true inside it, false touching it, and the casts' own answer away from it
	local inside: boolean = wrapped.overlap(vector.create(X, top + 0.5, Z), vector.create(2, 2, 2))
	local touching: boolean = wrapped.overlap(vector.create(X, top + 2, Z), vector.create(2, 2, 2))
	local floor: boolean = wrapped.overlap(vector.create(X, Geometry.floor - 1, Z), vector.create(2, 2, 2))
	if not inside or touching or not floor then
		return false, `overlap gave {inside} inside the box, {touching} touching it and {floor} in the floor`
	end

	-- 5) The nearer answers, and the casts' own hit on a tie
	local floorTop: number = Geometry.floor
	local floorWorld: any = Riders.world()
	local floorCasts: any = floorWorld.collision
	Platforms.add(floorWorld, still(2, floorTop - 2, roblox.Vector3.new(4, 1, 4)))

	local start: vector = vector.create(X, floorTop + 3, Z)
	local onFloor: any = floorWorld.collision.sweep(start, vector.create(2, 2, 2), vector.create(0, -10, 0))
	local own: any = floorCasts.sweep(start, vector.create(2, 2, 2), vector.create(0, -10, 0))
	if onFloor ~= own then
		return false, "a sweep down met the box under the floor before the floor itself"
	end

	local tieWorld: any = Riders.world()
	local tieCasts: any = tieWorld.collision
	Platforms.add(tieWorld, still(3, floorTop - 0.5, roblox.Vector3.new(4, 1, 4)))

	local tie: any = tieWorld.collision.sweep(start, vector.create(2, 2, 2), vector.create(0, -10, 0))
	local tieOwn: any = tieCasts.sweep(start, vector.create(2, 2, 2), vector.create(0, -10, 0))
	if tie ~= tieOwn then
		return false, "a box flush with the floor answered a sweep in place of the floor's own hit"
	end

	local raised: number? = tieWorld.collision.rest(start, vector.create(2, 6, 2))
	if raised ~= floorTop then
		return false, `rest over a box flush with the floor gave {raised}, not the floor's top`
	end

	-- A plate on the floor 1/128 stud thick, its center on the 1/512 quantum a path's place is rounded to
	local thinWorld: any = Riders.world()
	Platforms.add(thinWorld, still(4, floorTop + 1 / 256, roblox.Vector3.new(4, 1 / 128, 4)))
	local higher: number? = thinWorld.collision.rest(start, vector.create(2, 6, 2))
	if not higher or not near(higher, floorTop + 1 / 128) then
		return false, `rest over a plate on the floor gave {higher}, not the plate's top over the floor's`
	end

	-- 6) The last platform out puts the casts back, and nothing meets its box after
	remove()
	remove()
	if world.collision ~= casts or next(world.platforms) ~= nil then
		return false, "taking the only platform out, twice, left the world's casts wrapped or it registered"
	end

	-- 7) The wrapper's destroy reaches the casts under it
	local destroyed: boolean = false
	local stand: any = Riders.world()
	local under: any = stand.collision
	stand.collision = table.clone(under)
	stand.collision.destroy = function ()
		destroyed = true
	end

	Platforms.add(stand, rising(5))
	stand.collision.destroy()
	if not destroyed then
		return false, "the wrapper's destroy never reached the casts under it"
	end

	return true, nil
end
