--[[
    Every zone of the dev table's Stand and Crouch shapes stays inside its
    body capsule at each whole degree of pitch to a quarter turn and lean to
    step.lean either way, and a body a tenth of a stud thinner lets one out
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/DevShared/Harness")

local SHAPES: string = "src/Step/Shapes.luau"
local POSTURES: { string } = { "Stand", "Crouch" } -- Those that stand, whose zones the pitch and lean tilt
local QUARTER_TURN: number = 90 -- Degrees of pitch either way
local DEGREE: number = 1 -- The sweep's step through pitch and lean
local TENTH: number = 0.1 -- Studs, the step a body's radius is chosen in
local FEET: vector = vector.zero
local AHEAD: number = 0 -- A yaw that faces -Z, since turning moves every capsule alike

-- How far a point sits from the nearest point of a segment
local function distance(point: vector, from: vector, to: vector): number
	local axis: vector = to - from
	local length: number = vector.dot(axis, axis)
	local share: number = 0
	if length > 0 then
		share = math.clamp(vector.dot(point - from, axis) / length, 0, 1)
	end

	return vector.magnitude(point - (from + axis * share))
end

--[[
    The radius a placed body capsule needs to hold every placed zone: the
    furthest any zone's end sits from the body's axis plus that zone's
    radius, since along a zone's own axis that distance peaks at an end
--]]

local function needed(placed: any): number
	local body: any = placed.body
	local need: number = 0

	for _, zone: any in placed.zones do
		need = math.max(
			need,
			distance(zone.from, body.from, body.to) + zone.radius,
			distance(zone.to, body.from, body.to) + zone.radius
		)
	end

	return need
end

return function (): (boolean, string | nil)
	local Shapes: any = Environment.load(SHAPES)
	local shared: any = Harness.load().shared
	local limit: number = shared.step.lean

	for _, posture: string in POSTURES do
		local from: any = Shapes.cross(shared.hitShapes[posture])
		local into: any = Shapes.cross(shared.hitShapes[posture])
		local radius: number = from.body.radius
		local widest: number = 0
		local at: string = ""

		for pitch: number = -QUARTER_TURN, QUARTER_TURN, DEGREE do
			for lean: number = -limit, limit, DEGREE do
				Shapes.place(from, into, FEET, AHEAD, lean, math.rad(pitch))

				local need: number = needed(into)
				if need > widest then
					widest = need
					at = `{pitch} degrees of pitch and {lean} of lean`
				end
			end
		end

		if widest > radius then
			return false, `A {posture} zone reaches {widest} studs from the body's axis at {at}, past its {radius}`
		elseif widest <= radius - TENTH then
			return false, `The {posture} body's {radius} studs hold every zone with {widest}, so a tenth less would too`
		end
	end

	return true, nil
end
