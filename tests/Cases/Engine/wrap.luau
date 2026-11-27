--[[
    Engine.wrap hands a game's four functions Vector3s copied from the step's
    vectors and copies each hit back, and asks the engine for the overlap
    whether or not the game gives an include list
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local ENGINE: string = "src/Step/Engine.luau"
local REST: number = 1100.5

return function (): (boolean, string | nil)
	local Engine: any = Environment.load(ENGINE)
	local Vector3: any = roblox.Vector3
	local grass: any = roblox.Enum.Material.Grass

	-- What each of the game's functions was handed, and one hit each gives back
	local calls: { [string]: { any } } = {}
	local gameHit: { [string]: any } = {
		distance = 2.5,
		position = Vector3.new(1, 1100.5, -3),
		normal = Vector3.new(0, 1, 0),
		material = grass,
		instance = nil,
	}

	local collision: any = Engine.wrap({
		ray = function (origin: any, direction: any): any
			calls.ray = { origin, direction }
			return gameHit
		end,
		sweep = function (center: any, size: any, direction: any): any
			calls.sweep = { center, size, direction }
			return gameHit
		end,
		rest = function (center: any, size: any): number?
			calls.rest = { center, size }
			return REST
		end,
		sphere = function (center: any, radius: number, direction: any): any
			calls.sphere = { center, radius, direction }
			return nil
		end,
	})

	local origin: vector = vector.create(1, 1104, -3)
	local down: vector = vector.create(0, -10, 0)
	local size: vector = vector.create(2.78, 5, 2.78)

	local hit: any = collision.ray(origin, down)
	if not calls.ray or calls.ray[1] ~= Vector3.new(1, 1104, -3) or calls.ray[2] ~= Vector3.new(0, -10, 0) then
		return false, "Engine.wrap's ray handed the game something other than its vectors as Vector3s"
	elseif typeof(calls.ray[1]) ~= "Vector3" then
		return false, `Engine.wrap's ray handed the game a {typeof(calls.ray[1])}, not a Vector3`
	elseif not hit or typeof(hit.position) ~= "vector" or typeof(hit.normal) ~= "vector" then
		return false, "Engine.wrap's ray gave back a hit not on vector"
	elseif hit.position ~= vector.create(1, 1100.5, -3) or hit.normal ~= vector.create(0, 1, 0) then
		return false, `Engine.wrap's ray crossed the hit to {hit.position} and {hit.normal}`
	elseif hit.distance ~= 2.5 or hit.material ~= grass or hit.instance ~= nil then
		return false, "Engine.wrap's ray dropped the hit's distance, material or instance"
	end

	-- Every cast fills the same hit, so nothing is made per cast
	local swept: any = collision.sweep(origin, size, down)
	if swept ~= hit then
		return false, "Engine.wrap's sweep gave back a new hit table, where the one the collision reuses was expected"
	elseif calls.sweep[2] ~= Vector3.new(2.78, 5, 2.78) then
		return false, "Engine.wrap's sweep handed the game a size other than the hull's"
	end

	if collision.rest(origin, size) ~= REST or calls.rest[1] ~= Vector3.new(1, 1104, -3) then
		return false, "Engine.wrap's rest did not pass the game's rest height through"
	end

	if collision.sphere(origin, 1.37, down) ~= nil or calls.sphere[2] ~= 1.37 then
		return false, "Engine.wrap's sphere did not pass a miss or the radius through"
	end

	-- With no include list the overlap still asks the engine, over every part with CanCollide on but its own probe.
	-- Lune's query, stood in by the environment, finds nothing, and the live scenario checks what the engine answers
	local query: any = Environment.partsInPart
	local asked: number = query.calls
	if collision.overlap(origin, size) then
		return false, "Engine.wrap's overlap found a part, where the environment's query finds none"
	elseif query.calls ~= asked + 1 then
		return false,
			`Engine.wrap's overlap asked the engine's query {query.calls - asked} times, where once was expected`
	end

	local params: any = query.params
	if params.FilterType ~= roblox.Enum.RaycastFilterType.Exclude or params.RespectCanCollide ~= true then
		return false, "Engine.wrap's overlap with no include list asked for less than every part with CanCollide on"
	elseif params.FilterDescendantsInstances[1] ~= query.part.Parent then
		return false, "Engine.wrap's overlap with no include list left its own probe in what it asks for"
	end

	collision.destroy()

	-- An include list beside the functions is taken, and a probe never made needs no removing
	local narrowed: any = Engine.wrap({
		ray = function (): any
			return nil
		end,
		sweep = function (): any
			return nil
		end,
		rest = function (): number?
			return nil
		end,
		sphere = function (): any
			return nil
		end,
		include = { roblox.Instance.new("Folder") },
	})
	narrowed.destroy()

	return true, nil
end
