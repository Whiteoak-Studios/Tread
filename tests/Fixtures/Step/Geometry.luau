--[[
    The step's fixture geometry above the 1,000 studs no test content reaches:
    a floor, a wall, a 0.5-stud step, a 1-stud riser, a ledge, a vault and a
    slope too steep to walk, which Lune's casts and the live scenario both build
--]]

--!strict
local FLOOR: number = 1100 -- The floor's top
local LEDGE_HEIGHT: number = 0.705 -- A quarter skin under a resting hull's bottom lifted by a step up
local SLOPE_TILT: number = 55 -- Degrees about Z, steeper than Frontier Zero's 50° walkable limit
local SLOPE_LENGTH: number = 10 -- Its top face up the tilt
local SLOPE_THICKNESS: number = 2
local SLOPE_WIDTH: number = 8 -- Its top face along Z
local SLOPE_FOOT: vector = vector.create(10, FLOOR, 20) -- The middle of its top face's low edge, on the floor

-- A part by its center and full size, turned tilt degrees about Z, 0 for one that is axis-aligned
export type Part = {
	name: string,
	center: vector,
	size: vector,
	tilt: number,
}

-- The slope's axes, from its tilt: X turned up toward Y, and Y turned back toward -X
local radians: number = math.rad(SLOPE_TILT)
local slopeAlong: vector = vector.create(math.cos(radians), math.sin(radians), 0)
local slopeNormal: vector = vector.create(-math.sin(radians), math.cos(radians), 0)
local slopeCenter: vector = SLOPE_FOOT + slopeAlong * (SLOPE_LENGTH / 2) - slopeNormal * (SLOPE_THICKNESS / 2)

local FLOOR_PART: Part = {
	name = "Floor",
	center = vector.create(0, FLOOR - 1, 0),
	size = vector.create(80, 2, 60),
	tilt = 0,
}

local WALL: Part = {
	name = "Wall",
	center = vector.create(20.5, FLOOR + 4, -22),
	size = vector.create(1, 8, 12),
	tilt = 0,
}

local STEP: Part = {
	name = "Step",
	center = vector.create(13, FLOOR + 0.25, -8),
	size = vector.create(6, 0.5, 8),
	tilt = 0,
}

local RISER: Part = {
	name = "Riser",
	center = vector.create(13, FLOOR + 0.5, 6),
	size = vector.create(6, 1, 8),
	tilt = 0,
}

local LEDGE: Part = {
	name = "Ledge",
	center = vector.create(13, FLOOR + LEDGE_HEIGHT / 2, 12),
	size = vector.create(6, LEDGE_HEIGHT, 4),
	tilt = 0,
}

local VAULT: Part = {
	name = "Vault",
	center = vector.create(-32, FLOOR + 6, -22),
	size = vector.create(6, 12, 6),
	tilt = 0,
}

local SLOPE: Part = {
	name = "Slope",
	center = slopeCenter,
	size = vector.create(SLOPE_LENGTH, SLOPE_THICKNESS, SLOPE_WIDTH),
	tilt = SLOPE_TILT,
}

return {
	floor = FLOOR,
	wall = WALL,
	step = STEP,
	riser = RISER,
	ledge = LEDGE,
	vault = VAULT,
	slope = SLOPE,
	slopeFoot = SLOPE_FOOT,
	slopeNormal = slopeNormal,
	parts = { FLOOR_PART, WALL, STEP, RISER, LEDGE, VAULT, SLOPE },
}
