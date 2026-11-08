--[[
    The boundary between the public Vector3 and the step's vector: the step's
    casts on the engine, a game's own collision functions crossed into them,
    and the copies that carry a value or a box across
--]]

--!strict
--!native
local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent.Parent.Constants)
local State = require(script.Parent.State)

local SKINS: number = 2 * Constants.SKIN -- How far under a box's bottom rest looks, past a resting body's skin
local COLLISION_INCLUDE: string = "collision.include" -- How a refusal names each include list's key
local OCCLUSION_INCLUDE: string = "antiEsp.include"

type Box = State.Box
type Collision = State.Collision
type GameCollision = State.GameCollision
type GameHit = State.GameHit
type Hit = State.Hit

-- The overlap query's probe part, the Camera that holds it and the filter it tests with
type Probe = {
	holder: Camera,
	part: Part,
	params: OverlapParams,
}

local Engine = {}

--[[
    A Vector3 copied into the step's vector. The two never share a value in
    Lune, and both type checkers refuse either where the other is typed, so
    every value that crosses is copied by its components
--]]

function Engine.toVector(value: Vector3): vector
	return vector.create(value.X, value.Y, value.Z)
end

--[[
    A vector of the step's copied out into the public Vector3
--]]

function Engine.toVector3(value: vector): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

--[[
    An oriented box in the step's numbers, from a CFrame and a size, for a
    ladder's registration or the hull-overlap query
--]]

function Engine.box(cframe: CFrame, size: Vector3): Box
	return {
		center = Engine.toVector(cframe.Position),
		right = Engine.toVector(cframe.RightVector),
		up = Engine.toVector(cframe.UpVector),
		look = Engine.toVector(cframe.LookVector),
		size = Engine.toVector(size),
	}
end

-- One hit each collision fills and hands back for every cast
local function newHit(): Hit
	return {
		distance = 0,
		position = vector.zero,
		normal = vector.zero,
		material = Enum.Material.Air,
		instance = nil,
	}
end

--[[
    Errors naming the first entry of an include list that is no Instance,
    under the key the game gave it as

    @ key | the list's path in the game's tables, such as collision.include
--]]

local function checkInclude(include: { Instance }, key: string)
	if type(include) ~= "table" then
		error(`{key} must be a list of Instances, and got a {typeof(include)}`)
	end

	for index: number, instance: Instance in include do
		if typeof(instance) ~= "Instance" then
			error(`{key}[{index}] must be an Instance, and got a {typeof(instance)}`)
		end
	end
end

--[[
    The probe part the overlap query tests with, under a Camera of its own
    so a server's probe never replicates, and its filter: only the include
    list's parts when there is one, and every part with CanCollide on but
    the probe's own when there is none
--]]

local function newProbe(include: { Instance }?): Probe
	local holder: Camera = Instance.new("Camera")
	holder.Name = "TreadProbe"

	local part: Part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = holder

	local params: OverlapParams = OverlapParams.new()
	params.RespectCanCollide = true

	if include then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { holder }
	end

	holder.Parent = Workspace

	return { holder = holder, part = part, params = params }
end

--[[
    The exact overlap query, GetPartsInPart on one probe box, and the
    closure that removes the probe. The probe is made at the first query,
    so building the casts makes no engine object
--]]

local function overlapper(include: { Instance }?): ((center: vector, size: vector) -> boolean, () -> ())
	local made: Probe? = nil

	local function overlap(center: vector, size: vector): boolean
		local probe: Probe = made or newProbe(include)
		made = probe

		probe.part.Size = Engine.toVector3(size)
		probe.part.CFrame = CFrame.new(center.x, center.y, center.z)

		return #Workspace:GetPartsInPart(probe.part, probe.params) > 0
	end

	local function release()
		local probe: Probe? = made
		if probe then
			probe.holder:Destroy()
			made = nil
		end
	end

	return overlap, release
end

--[[
    The step's casts on the engine for a game that passes no collision
    functions: a Raycast, a Blockcast with no margin for the box hull, a
    Spherecast and the overlap query, each seeing only the include list's
    parts with CanCollide on and never terrain water
--]]

function Engine.collision(include: { Instance }): Collision
	checkInclude(include, COLLISION_INCLUDE)

	local params: RaycastParams = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.RespectCanCollide = true
	params.IgnoreWater = true

	local overlap: (center: vector, size: vector) -> boolean, release: () -> () = overlapper(include)
	local hit: Hit = newHit()

	local function cross(found: RaycastResult?): Hit?
		if not found then
			return nil
		end

		hit.distance = found.Distance
		hit.position = Engine.toVector(found.Position)
		hit.normal = Engine.toVector(found.Normal)
		hit.material = found.Material
		hit.instance = found.Instance

		return hit
	end

	return {
		ray = function (origin: vector, direction: vector): Hit?
			return cross(Workspace:Raycast(Engine.toVector3(origin), Engine.toVector3(direction), params))
		end,

		sweep = function (center: vector, size: vector, direction: vector): Hit?
			local at: CFrame = CFrame.new(center.x, center.y, center.z)

			return cross(Workspace:Blockcast(at, Engine.toVector3(size), Engine.toVector3(direction), params))
		end,

		-- A flat box the size of the footprint, cast down from the box's top to a little under its bottom
		rest = function (center: vector, size: vector): number?
			local top: number = center.y + size.y / 2
			local at: CFrame = CFrame.new(center.x, top, center.z)
			local footprint: Vector3 = Vector3.new(size.x, 0, size.z)
			local down: Vector3 = Vector3.new(0, -(size.y + SKINS), 0)

			local found: RaycastResult? = Workspace:Blockcast(at, footprint, down, params)
			if not found then
				return nil
			end

			return top - found.Distance
		end,

		sphere = function (center: vector, radius: number, direction: vector): Hit?
			return cross(Workspace:Spherecast(Engine.toVector3(center), radius, Engine.toVector3(direction), params))
		end,

		overlap = overlap,
		destroy = release,
	}
end

--[[
    A game's own four collision functions crossed into the step's casts,
    each vector copied out to a Vector3 and each hit copied back. The
    overlap query runs on the engine, over the game's include list when it
    gives one and over every part with CanCollide on when it gives none
--]]

function Engine.wrap(functions: GameCollision): Collision
	if type(functions) ~= "table" then
		error(`collision must be a table of the four functions, and got a {typeof(functions)}`)
	end

	local gameRay = functions.ray
	local gameSweep = functions.sweep
	local gameRest = functions.rest
	local gameSphere = functions.sphere

	if type(gameRay) ~= "function" then
		error(`collision.ray must be a function, and got a {typeof(gameRay)}`)
	elseif type(gameSweep) ~= "function" then
		error(`collision.sweep must be a function, and got a {typeof(gameSweep)}`)
	elseif type(gameRest) ~= "function" then
		error(`collision.rest must be a function, and got a {typeof(gameRest)}`)
	elseif type(gameSphere) ~= "function" then
		error(`collision.sphere must be a function, and got a {typeof(gameSphere)}`)
	end

	local include: { Instance }? = functions.include
	if include then
		checkInclude(include, COLLISION_INCLUDE)
	end

	local overlap: (center: vector, size: vector) -> boolean, release: () -> () = overlapper(include)
	local hit: Hit = newHit()

	local function cross(found: GameHit?): Hit?
		if not found then
			return nil
		end

		hit.distance = found.distance
		hit.position = Engine.toVector(found.position)
		hit.normal = Engine.toVector(found.normal)
		hit.material = found.material
		hit.instance = found.instance

		return hit
	end

	return {
		ray = function (origin: vector, direction: vector): Hit?
			return cross(gameRay(Engine.toVector3(origin), Engine.toVector3(direction)))
		end,

		sweep = function (center: vector, size: vector, direction: vector): Hit?
			return cross(gameSweep(Engine.toVector3(center), Engine.toVector3(size), Engine.toVector3(direction)))
		end,

		rest = function (center: vector, size: vector): number?
			return gameRest(Engine.toVector3(center), Engine.toVector3(size))
		end,

		sphere = function (center: vector, radius: number, direction: vector): Hit?
			return cross(gameSphere(Engine.toVector3(center), radius, Engine.toVector3(direction)))
		end,

		overlap = overlap,
		destroy = release,
	}
end

--[[
    The step's casts from the shared table's collision key: the game's own
    functions crossed over through wrap, which names the first one missing
    from a partial set, or engine casts over its include list when it gives
    none of them
--]]

function Engine.casts(collision: GameCollision): Collision
	if type(collision) ~= "table" then
		error(`collision must be a table of the four functions or an include list, and got a {typeof(collision)}`)
	end

	if collision.ray ~= nil or collision.sweep ~= nil or collision.rest ~= nil or collision.sphere ~= nil then
		return Engine.wrap(collision)
	end

	local include: { Instance }? = collision.include
	if include == nil then
		error("collision gives none of the four functions and no include list for engine casts")
	end

	return Engine.collision(include)
end

--[[
    Anti-ESP's line-of-sight test on the engine: true when a ray meets any
    part of the include list, CanCollide off or on, or solid terrain in it,
    never terrain water, so occluder-only parts the step's casts pass
    through still block it
--]]

function Engine.occlusion(include: { Instance }): (origin: vector, direction: vector) -> boolean
	checkInclude(include, OCCLUSION_INCLUDE)

	local params: RaycastParams = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.RespectCanCollide = false
	params.IgnoreWater = true

	return function (origin: vector, direction: vector): boolean
		return Workspace:Raycast(Engine.toVector3(origin), Engine.toVector3(direction), params) ~= nil
	end
end

return Engine
