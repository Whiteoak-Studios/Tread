--[[
    The hit shapes on the step's vector: a posture's shapes crossed from the
    shared table, placed at the feet, the facing and the lean, and the
    posture a body is hit through, which the history and the client share
--]]

--!strict
--!native
local Engine = require(script.Parent.Engine)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)

local DEGREES: number = math.pi / 180 -- Radians a degree of lean

type Mode = State.Mode
type Posture = State.Posture

-- One capsule of a hit shape, on the step's vector: in the character's own space, or placed in the world
export type Shape = {
	from: vector,
	to: vector,
	radius: number,
}

-- One posture's hit shapes crossed onto vector, and the height a lean tilts every point above about
export type Shapes = {
	body: Shape,
	zones: { [string]: Shape },
	waist: number,
}

-- One posture's shapes placed, which Shapes.place rewrites in place
export type Placed = {
	body: Shape,
	zones: { [string]: Shape },
}

-- One posture's hit shapes as the shared table's hitShapes give them
type GameShapes = {
	body: Types.Shape,
	zones: { [string]: Types.Shape },
	waist: number,
}

local Shapes = {}

local function crossShape(shape: Types.Shape): Shape
	return { from = Engine.toVector(shape.from), to = Engine.toVector(shape.to), radius = shape.radius }
end

--[[
    A posture's hit shapes from the shared table crossed onto vector, every
    capsule a new table, so the result can also be placed into
--]]

function Shapes.cross(shapes: GameShapes): Shapes
	local zones: { [string]: Shape } = {}

	for name: string, shape: Types.Shape in shapes.zones do
		zones[name] = crossShape(shape)
	end

	return { body = crossShape(shapes.body), zones = zones, waist = shapes.waist }
end

--[[
    A point of a shape in the character's own space, placed: tilted by the
    lean about the waist when it sits above it, a positive lean to the
    right, then turned by the yaw and moved to the feet. Own space has +X
    right and +Z back, as the step reads it
--]]

local function point(
	at: vector,
	feet: vector,
	sine: number,
	cosine: number,
	waist: number,
	leanSine: number,
	leanCosine: number
): vector
	local x: number, y: number, z: number = at.x, at.y, at.z

	if y > waist then
		local up: number = y - waist
		x, y = x * leanCosine + up * leanSine, waist - x * leanSine + up * leanCosine
	end

	return vector.create(feet.x + cosine * x + sine * z, feet.y + y, feet.z - sine * x + cosine * z)
end

local function capsule(
	from: Shape,
	into: Shape,
	feet: vector,
	sine: number,
	cosine: number,
	waist: number,
	leanSine: number,
	leanCosine: number
)
	into.from = point(from.from, feet, sine, cosine, waist, leanSine, leanCosine)
	into.to = point(from.to, feet, sine, cosine, waist, leanSine, leanCosine)
	into.radius = from.radius
end

--[[
    Places a posture's shapes into a set holding the same capsules: the
    body capsule and every zone, each point above the waist tilted by the
    lean, then turned by the yaw and moved to the feet, with the step's own
    sine and cosine

    @ yaw | radians, along -Z at 0 and -X at a quarter turn
    @ lean | degrees, to the right when positive
--]]

function Shapes.place(from: Shapes, into: Placed, feet: vector, yaw: number, lean: number)
	local sine: number = Math.sin(yaw)
	local cosine: number = Math.cos(yaw)
	local leanSine: number = Math.sin(lean * DEGREES)
	local leanCosine: number = Math.cos(lean * DEGREES)
	local waist: number = from.waist

	capsule(from.body, into.body, feet, sine, cosine, waist, leanSine, leanCosine)

	for name: string, shape: Shape in from.zones do
		capsule(shape, into.zones[name], feet, sine, cosine, waist, leanSine, leanCosine)
	end
end

--[[
    The posture a body is hit through: Downed for a lying one, Crouch while
    it swims, downed or not, and otherwise its own
--]]

function Shapes.posture(posture: Posture, mode: Mode, lying: boolean): Posture
	if lying then
		return "Downed"
	elseif mode == "Swim" then
		return "Crouch"
	end

	return posture
end

return Shapes
