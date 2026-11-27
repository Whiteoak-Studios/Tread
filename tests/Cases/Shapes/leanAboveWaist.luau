--[[
    A lean tilts only the points above the posture's waist, about the waist
    and to the right for a positive lean, and leaves every point at or below
    it where it stands upright, so a capsule that spans the waist stretches
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local SHAPES: string = "src/Step/Shapes.luau"
local WAIST: number = 2
local LEAN: number = 30 -- Degrees, to the right
local FEET: vector = vector.create(10, 5, -20)
local NEAR: number = 1e-5 -- A vector holds float32, so a placed point sits within its rounding of the oracle's
local LEVEL: number = 0 -- The aim pitch, radians, so only the lean tilts

local SIDE: number = 0.3 -- Studs right of the body's line, where a point on the waist would show a tilt

-- A capsule in own space on Vector3, as the shared table gives one, upright between two heights at a side
local function capsule(fromY: number, toY: number, side: number?): any
	local x: number = side or 0

	return { from = roblox.Vector3.new(x, fromY, 0), to = roblox.Vector3.new(x, toY, 0), radius = 0.5 }
end

return function (): (boolean, string | nil)
	local Shapes: any = Environment.load(SHAPES)

	-- A body spanning the waist, a zone wholly above it, one wholly below it and one off to the side whose top sits
	-- on it, which any tilt would move
	local given: any = {
		body = capsule(0.5, 4),
		zones = { head = capsule(3.5, 4), legs = capsule(0.2, 1), hips = capsule(1, WAIST, SIDE) },
		waist = WAIST,
	}

	local shapes: any = Shapes.cross(given)
	local upright: any = Shapes.cross(given)
	local leaning: any = Shapes.cross(given)

	-- Facing -Z with no turn, so own space's +X, the body's right, is the world's +X
	Shapes.place(shapes, upright, FEET, 0, 0, LEVEL)
	Shapes.place(shapes, leaning, FEET, 0, LEAN, LEVEL)

	-- 1) Upright, every point is its own-space point moved to the feet
	if
		upright.zones.head.to ~= FEET + vector.create(0, 4, 0)
		or upright.body.from ~= FEET + vector.create(0, 0.5, 0)
	then
		return false,
			`Upright, the head's top sat at {upright.zones.head.to} and the body's foot at {upright.body.from}`
	end

	-- 2) Every point at or below the waist stays where it stands upright
	local still: { { name: string, got: vector, want: vector } } = {
		{ name = "body's bottom", got = leaning.body.from, want = upright.body.from },
		{ name = "legs' bottom", got = leaning.zones.legs.from, want = upright.zones.legs.from },
		{ name = "legs' top", got = leaning.zones.legs.to, want = upright.zones.legs.to },
		{ name = "hips' top, on the waist", got = leaning.zones.hips.to, want = upright.zones.hips.to },
	}

	for _, point in still do
		if point.got ~= point.want then
			return false, `The lean moved the {point.name}, at or below the waist, to {point.got} from {point.want}`
		end
	end

	-- 3) Every point above it tips right about the waist, keeping its distance from it
	local tilt: number = math.rad(LEAN)
	local tipped: { { name: string, got: vector, height: number } } = {
		{ name = "body's top", got = leaning.body.to, height = 4 },
		{ name = "head's bottom", got = leaning.zones.head.from, height = 3.5 },
		{ name = "head's top", got = leaning.zones.head.to, height = 4 },
	}

	for _, point in tipped do
		local up: number = point.height - WAIST
		local want: vector = FEET + vector.create(up * math.sin(tilt), WAIST + up * math.cos(tilt), 0)

		if vector.magnitude(point.got - want) > NEAR then
			return false, `The lean put the {point.name} at {point.got}, not tipped right to {want}`
		end
	end

	-- 4) The radii come through the lean as they are, and the shapes placed from are left as they were
	if leaning.zones.head.radius ~= given.zones.head.radius or leaning.body.radius ~= given.body.radius then
		return false, "Placing the leaning shapes lost their radii"
	elseif shapes.zones.head.to ~= vector.create(0, 4, 0) then
		return false, `Placing moved the shapes it placed from, the head's top to {shapes.zones.head.to}`
	end

	return true, nil
end
