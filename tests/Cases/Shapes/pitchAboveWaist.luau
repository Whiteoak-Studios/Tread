--[[
    An aim pitch tilts only the points above the waist, after the lean and
    back along +Z when positive, as Roblox's CFrame.Angles(pitch, 0, -lean)
    does, and a level pitch leaves the lean's placement exactly as it was
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local SHAPES: string = "src/Step/Shapes.luau"
local MATH: string = "src/Step/Math.luau"
local WAIST: number = 2
local FEET: vector = vector.create(10, 5, -20)
local LEAN: number = 30 -- Degrees, to the right
local TIPPED: number = math.pi / 6 -- Radians of aim pitch, up
local STEEP: number = math.pi / 3 -- Radians, the pitch the composition is checked at beside the lean
local TURNED: number = 0.9 -- Radians of yaw the composition is checked at
local QUARTER: number = math.pi / 2 -- A yaw that faces -X
local LEVEL: number = 0 -- Radians of aim pitch, none
local UNLEANED: number = 0 -- Degrees of lean, none
local NEAR: number = 1e-5 -- A vector holds float32, so a placed point sits within its rounding of the oracle's
local STUDIO_NEAR: number = 1e-4 -- The four places Studio's figures were read to

-- Studio 0.746's CFrame.Angles(0.5, 0, -0.3) * Vector3.yAxis, which Lune's own CFrame must give
local STUDIO_PITCH: number = 0.5
local STUDIO_LEAN: number = 0.3 -- Radians
local STUDIO_TURNED: vector = vector.create(0.2955, 0.8384, 0.458)

-- An own-space capsule on Vector3, as the shared table gives one
local function capsule(from: vector, to: vector): any
	return {
		from = roblox.Vector3.new(from.x, from.y, from.z),
		to = roblox.Vector3.new(to.x, to.y, to.z),
		radius = 0.5,
	}
end

-- Where a point sits after the lean alone, in the order and with the step trig Shapes.place uses
local function leanOnly(Math: any, at: vector, yaw: number, lean: number): vector
	local sine: number, cosine: number = Math.sin(yaw), Math.cos(yaw)
	local leanSine: number, leanCosine: number = Math.sin(math.rad(lean)), Math.cos(math.rad(lean))
	local x: number, y: number, z: number = at.x, at.y, at.z

	if y > WAIST then
		local up: number = y - WAIST
		x, y = x * leanCosine + up * leanSine, WAIST - x * leanSine + up * leanCosine
	end

	return vector.create(FEET.x + cosine * x + sine * z, FEET.y + y, FEET.z - sine * x + cosine * z)
end

-- Where Roblox's own CFrames put an own-space point above the waist: turned at the feet, then tilted at the waist
local function composed(at: vector, yaw: number, lean: number, pitch: number): vector
	local frame: any = roblox.CFrame.new(FEET.x, FEET.y, FEET.z)
		* roblox.CFrame.Angles(0, yaw, 0)
		* roblox.CFrame.new(0, WAIST, 0)
		* roblox.CFrame.Angles(pitch, 0, -math.rad(lean))
	local world: any = frame * roblox.Vector3.new(at.x, at.y - WAIST, at.z)

	return vector.create(world.X, world.Y, world.Z)
end

local function apart(a: vector, b: vector): number
	return vector.magnitude(a - b)
end

return function (): (boolean, string | nil)
	local Shapes: any = Environment.load(SHAPES)
	local Math: any = Environment.load(MATH)

	-- Off the body's line both ways: a body spanning the waist, a head above it and hips below it, the hips' top on it
	local given: any = {
		body = capsule(vector.create(0.2, 0.5, -0.1), vector.create(-0.3, 4.5, 0.25)),
		zones = {
			head = capsule(vector.create(0.3, 3.5, -0.2), vector.create(-0.4, 4.2, 0.35)),
			hips = capsule(vector.create(0.3, 1, 0.2), vector.create(-0.25, WAIST, -0.15)),
		},
		waist = WAIST,
	}

	local shapes: any = Shapes.cross(given)
	local into: any = Shapes.cross(given)

	-- 0) Lune's CFrame turns a point as Studio's does, so it can stand as the oracle
	local turned: any = roblox.CFrame.Angles(STUDIO_PITCH, 0, -STUDIO_LEAN) * roblox.Vector3.new(0, 1, 0)
	local studio: vector = vector.create(turned.X, turned.Y, turned.Z)
	if apart(studio, STUDIO_TURNED) > STUDIO_NEAR then
		return false, `Lune's CFrame.Angles turned the up axis to {studio}, where Studio's gave {STUDIO_TURNED}`
	end

	-- 1) A level pitch with a lean places every point exactly where the lean alone does
	Shapes.place(shapes, into, FEET, TURNED, LEAN, LEVEL)
	local points: { [string]: vector } = {
		["body's bottom"] = shapes.body.from,
		["body's top"] = shapes.body.to,
		["head's bottom"] = shapes.zones.head.from,
		["head's top"] = shapes.zones.head.to,
		["hips' top"] = shapes.zones.hips.to,
	}

	local placed: { [string]: vector } = {
		["body's bottom"] = into.body.from,
		["body's top"] = into.body.to,
		["head's bottom"] = into.zones.head.from,
		["head's top"] = into.zones.head.to,
		["hips' top"] = into.zones.hips.to,
	}

	for name: string, at: vector in points do
		local want: vector = leanOnly(Math, at, TURNED, LEAN)
		if placed[name] ~= want then
			return false, `At a level pitch the {name} sat at {placed[name]}, not the lean's own {want}`
		end
	end

	-- 2) Facing -Z, a point 2 studs above the waist on the axis tips back along +Z, and down along -Z for a low pitch
	local axis: any = { body = capsule(vector.create(0, 0.5, 0), vector.create(0, 4, 0)), zones = {}, waist = WAIST }
	local upright: any = Shapes.cross(axis)
	local tipped: any = Shapes.cross(axis)

	local expected: { { name: string, yaw: number, pitch: number, want: vector } } = {
		{ name = "facing -Z, up", yaw = 0, pitch = TIPPED, want = FEET + vector.create(0, 3.7320508, 1) },
		{ name = "facing -Z, down", yaw = 0, pitch = -TIPPED, want = FEET + vector.create(0, 3.7320508, -1) },
		{ name = "facing -X, up", yaw = QUARTER, pitch = TIPPED, want = FEET + vector.create(1, 3.7320508, 0) },
	}

	for _, case in expected do
		Shapes.place(upright, tipped, FEET, case.yaw, UNLEANED, case.pitch)
		if apart(tipped.body.to, case.want) > NEAR then
			return false, `{case.name}, the axis' top at 4 studs sat at {tipped.body.to}, not {case.want}`
		elseif tipped.body.from ~= FEET + vector.create(0, 0.5, 0) then
			return false, `{case.name}, the axis' foot below the waist moved to {tipped.body.from}`
		end
	end

	-- 3) Points at or below the waist sit exactly where a level pitch puts them
	local level: any = Shapes.cross(given)
	Shapes.place(shapes, level, FEET, TURNED, LEAN, LEVEL)
	Shapes.place(shapes, into, FEET, TURNED, LEAN, STEEP)

	local below: { { name: string, got: vector, want: vector } } = {
		{ name = "body's bottom", got = into.body.from, want = level.body.from },
		{ name = "hips' bottom", got = into.zones.hips.from, want = level.zones.hips.from },
		{ name = "hips' top, on the waist", got = into.zones.hips.to, want = level.zones.hips.to },
	}

	for _, point in below do
		if point.got ~= point.want then
			return false, `The pitch moved the {point.name}, at or below the waist, to {point.got} from {point.want}`
		end
	end

	-- 4) Above it, with the lean and the pitch together, every point sits where Roblox's CFrames put it
	local above: { { name: string, got: vector, at: vector } } = {
		{ name = "body's top", got = into.body.to, at = shapes.body.to },
		{ name = "head's bottom", got = into.zones.head.from, at = shapes.zones.head.from },
		{ name = "head's top", got = into.zones.head.to, at = shapes.zones.head.to },
	}

	for _, point in above do
		local want: vector = composed(point.at, TURNED, LEAN, STEEP)
		if apart(point.got, want) > NEAR then
			return false, `Leaning and pitched, the {point.name} sat at {point.got}, not the CFrames' {want}`
		end
	end

	-- 5) The radii come through as they are, and the shapes placed from are left as they were
	if into.zones.head.radius ~= given.zones.head.radius or into.body.radius ~= given.body.radius then
		return false, "Placing the pitched shapes lost their radii"
	elseif
		shapes.zones.head.to ~= vector.create(-0.4, 4.2, 0.35) or shapes.body.to ~= vector.create(-0.3, 4.5, 0.25)
	then
		return false, `Placing moved the shapes it placed from, the head's top to {shapes.zones.head.to}`
	end

	return true, nil
end
