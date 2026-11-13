--[[
    The step's casts in Lune over fixture parts: exact on an axis-aligned part
    and on a tilted part's top face, all it sees of one, with a sphere swept as
    its cube against a box, and each skipping a part it starts in
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Geometry = require(script.Parent.Geometry)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local SKINS: number = 2 * Constants.SKIN -- How far under a box's bottom rest still looks, as the engine's does
local MATERIAL: Enum.Material = Enum.Material.Plastic -- Every fixture part's, as a new Part's

type Collision = State.Collision
type Hit = State.Hit
type Part = Geometry.Part

-- A part as the casts read it: an axis-aligned box, or a tilted part's top face
type Solid = {
	tilted: boolean,
	center: vector, -- The box's center, or the face's
	half: vector, -- The box's half size
	normal: vector, -- The face's normal
	along: vector, -- The face's axis up the tilt
	halfLength: number, -- Half the face up the tilt
	halfWidth: number, -- Half the face along Z
}

-- The nearest hit of the cast running: its share of the move, its normal and its contact
local nearest: number = math.huge
local nearestNormal: vector = vector.zero
local nearestPoint: vector = vector.zero

local function dot(a: vector, b: vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function solid(part: Part): Solid
	local radians: number = math.rad(part.tilt)
	local along: vector = vector.create(math.cos(radians), math.sin(radians), 0)
	local normal: vector = vector.create(-math.sin(radians), math.cos(radians), 0)

	return {
		tilted = part.tilt ~= 0,
		center = part.tilt ~= 0 and part.center + normal * (part.size.y / 2) or part.center,
		half = part.size / 2,
		normal = normal,
		along = along,
		halfLength = part.size.x / 2,
		halfWidth = part.size.z / 2,
	}
end

-- The shares of a move at which it enters and leaves a slab of half width extent whose center lies gap away
local function slab(gap: number, extent: number, move: number): (number, number)
	if move == 0 then
		if math.abs(gap) < extent then
			return -math.huge, math.huge
		end

		return math.huge, -math.huge
	end

	local near: number = (gap - extent) / move
	local far: number = (gap + extent) / move
	if near > far then
		return far, near
	end

	return near, far
end

-- A box of half size half swept from center along direction against an axis-aligned part
local function sweepBox(target: Solid, center: vector, half: vector, direction: vector)
	local gap: vector = target.center - center
	local extent: vector = target.half + half
	local enterX: number, exitX: number = slab(gap.x, extent.x, direction.x)
	local enterY: number, exitY: number = slab(gap.y, extent.y, direction.y)
	local enterZ: number, exitZ: number = slab(gap.z, extent.z, direction.z)
	local enter: number = math.max(enterX, enterY, enterZ)
	local exit: number = math.min(exitX, exitY, exitZ)

	if enter < 0 or enter >= exit or enter > 1 or enter >= nearest then
		return
	end

	local normal: vector
	if enter == enterX then
		normal = vector.create(-math.sign(direction.x), 0, 0)
	elseif enter == enterY then
		normal = vector.create(0, -math.sign(direction.y), 0)
	else
		normal = vector.create(0, 0, -math.sign(direction.z))
	end

	nearest = enter
	nearestNormal = normal
	nearestPoint = center + direction * enter - normal * half
end

-- A box, or a sphere of radius half.x, swept against a tilted part's top face
local function sweepFace(target: Solid, center: vector, half: vector, direction: vector, round: boolean)
	local normal: vector = target.normal

	-- The point of the shape that leads into the face: a sphere's nearest, a box's lowest corner or edge
	local support: vector
	if round then
		support = center - normal * half.x
	else
		local lead: vector = vector.create(math.sign(normal.x), math.sign(normal.y), math.sign(normal.z))
		support = center - half * lead
	end

	local above: number = dot(normal, support - target.center)
	local closing: number = dot(normal, direction)
	if above <= 0 or closing >= 0 then
		return
	end

	local share: number = above / -closing
	if share > 1 or share >= nearest then
		return
	end

	local point: vector = support + direction * share
	local offset: vector = point - target.center
	if math.abs(dot(offset, target.along)) > target.halfLength or math.abs(offset.z) > target.halfWidth then
		return
	end

	nearest = share
	nearestNormal = normal
	nearestPoint = point
end

--[[
    Builds the casts over a list of fixture parts, each hit filled into one
    table the collision reuses, as the engine's collision does
--]]

return function (parts: { Part }): Collision
	local solids: { Solid } = {}
	for _, part: Part in parts do
		table.insert(solids, solid(part))
	end

	local hit: Hit = {
		distance = 0,
		position = vector.zero,
		normal = vector.zero,
		material = MATERIAL,
		instance = nil,
	}

	local function cast(center: vector, half: vector, direction: vector, round: boolean): Hit?
		nearest = math.huge

		for _, target: Solid in solids do
			if target.tilted then
				sweepFace(target, center, half, direction, round)
			else
				sweepBox(target, center, half, direction)
			end
		end

		if nearest > 1 then
			return nil
		end

		hit.distance = nearest * math.sqrt(dot(direction, direction))
		hit.position = nearestPoint
		hit.normal = nearestNormal

		return hit
	end

	return {
		ray = function (origin: vector, direction: vector): Hit?
			return cast(origin, vector.zero, direction, false)
		end,

		sweep = function (center: vector, size: vector, direction: vector): Hit?
			return cast(center, size / 2, direction, false)
		end,

		rest = function (center: vector, size: vector): number?
			local top: number = center.y + size.y / 2
			local plate: vector = vector.create(size.x / 2, 0, size.z / 2)
			local found: Hit? =
				cast(vector.create(center.x, top, center.z), plate, vector.create(0, -(size.y + SKINS), 0), false)
			if not found then
				return nil
			end

			return top - found.distance
		end,

		sphere = function (center: vector, radius: number, direction: vector): Hit?
			return cast(center, vector.one * radius, direction, true)
		end,

		overlap = function (center: vector, size: vector): boolean
			local half: vector = size / 2

			for _, target: Solid in solids do
				if target.tilted then
					-- Inside when the box's lowest corner under the face sits under the face itself
					local normal: vector = target.normal
					local lead: vector = vector.create(math.sign(normal.x), math.sign(normal.y), math.sign(normal.z))
					local offset: vector = center - half * lead - target.center
					local under: boolean = dot(normal, offset) < 0
						and math.abs(dot(offset, target.along)) < target.halfLength
						and math.abs(offset.z) < target.halfWidth

					if under then
						return true
					end
				else
					local gap: vector = target.center - center
					local extent: vector = target.half + half
					if math.abs(gap.x) < extent.x and math.abs(gap.y) < extent.y and math.abs(gap.z) < extent.z then
						return true
					end
				end
			end

			return false
		end,

		destroy = function () end,
	}
end
