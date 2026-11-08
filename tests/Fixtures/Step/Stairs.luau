--[[
    The mantle's stair fixtures above 1,000 studs: flights of 0.5-stud risers
    up to a landing or a ledge, the places a body stands on them, and the
    worlds, bodies and presses the stair cases build from them
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Collision)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Course = require(script.Parent.Course)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local SKIN: number = Constants.SKIN
local RADIUS: number = Course.settings.radius
local FLOOR: number = Course.floor
local RISER: number = 0.5 -- Each step's rise, the city block's stairs'
local RISERS: number = 12 -- Steps from the floor to the landing
local MIDDLE: number = 6 -- The tread a body partway up stands on
local FACE: number = 10 -- X of the first riser, the flight climbing along +X
local LANDING_DEPTH: number = 20 -- Along X, past the last riser
local LEDGE_LANDING: number = 3 -- The landing's depth before a ledge, room for the hull with a skin either side
local LEDGE_HEIGHT: number = 3 -- Over the landing
local LEDGE_DEPTH: number = 6
local WIDTH: number = 16 -- Along Z, wider than any probe a body met at 45° makes
local FLOOR_FROM: number = FACE - 20 -- X where the floor starts, behind the flight's foot
local FLOOR_TO: number = FACE + 60 -- And ends, past the longest landing
local FLOOR_THICKNESS: number = 2

type Command = State.Command
type Part = Geometry.Part
type State = State.State
type World = State.World

-- A flight in its own world, and where a body stands on it
export type Flight = {
	world: World,
	foot: vector, -- On the floor, its hull a skin from the first riser
	middle: vector, -- On a tread partway up, its hull a skin from the next riser
	top: vector, -- On the landing, its hull's back a skin past the last riser, or a skin from the ledge's face
}

local Stairs = {}

Stairs.east = Course.east -- A yaw that looks up the flight, along +X
Stairs.depths = { 0.5, 1, 1.5 } :: { number } -- Each flight's tread depth
Stairs.places = { "foot", "middle", "top" } :: { string } -- The places a Flight gives, by key
Stairs.angles = { math.rad(30), math.rad(-30), math.rad(45), math.rad(-45) } :: { number } -- Off the flight's line
Stairs.advance = Course.advance

--[[
    A part across the stairs' width, from the floor up to top, between two
    X along the flight
--]]

function Stairs.box(name: string, from: number, to: number, top: number): Part
	return {
		name = name,
		center = vector.create((from + to) / 2, (FLOOR + top) / 2, 0),
		size = vector.create(to - from, top - FLOOR, WIDTH),
		tilt = 0,
	}
end

local FLOOR_PART: Part = {
	name = "StairsFloor",
	center = vector.create((FLOOR_FROM + FLOOR_TO) / 2, FLOOR - FLOOR_THICKNESS / 2, 0),
	size = vector.create(FLOOR_TO - FLOOR_FROM, FLOOR_THICKNESS, WIDTH),
	tilt = 0,
}

--[[
    A server's world over the stairs' floor and the parts given, on Lune's
    fixture casts
--]]

function Stairs.world(parts: { Part }): World
	local all: { Part } = { FLOOR_PART }
	table.move(parts, 1, #parts, 2, all)

	return Course.world(Casts(all))
end

--[[
    A flight up from the floor at the first riser, its treads depth deep,
    to a landing, or with ledge set to a short landing that ends at a
    ledge's face, and the places a body stands on it
--]]

function Stairs.flight(depth: number, ledge: boolean): Flight
	local parts: { Part } = {}

	for step: number = 1, RISERS - 1 do
		local from: number = FACE + (step - 1) * depth
		table.insert(parts, Stairs.box(`Tread{step}`, from, from + depth, FLOOR + step * RISER))
	end

	local landingFrom: number = FACE + (RISERS - 1) * depth
	local landingTop: number = FLOOR + RISERS * RISER
	local landingTo: number = landingFrom + (ledge and LEDGE_LANDING or LANDING_DEPTH)
	table.insert(parts, Stairs.box("Landing", landingFrom, landingTo, landingTop))

	local topX: number = landingFrom + RADIUS + SKIN
	if ledge then
		table.insert(parts, Stairs.box("Ledge", landingTo, landingTo + LEDGE_DEPTH, landingTop + LEDGE_HEIGHT))
		topX = landingTo - RADIUS - SKIN
	end

	local middleRiser: number = FACE + MIDDLE * depth

	return {
		world = Stairs.world(parts),
		foot = vector.create(Math.quantize(FACE - RADIUS - SKIN), Course.resting, 0),
		middle = vector.create(
			Math.quantize(middleRiser - RADIUS - SKIN),
			Math.quantize(FLOOR + MIDDLE * RISER + SKIN),
			0
		),
		top = vector.create(Math.quantize(topX), Math.quantize(landingTop + SKIN), 0),
	}
end

--[[
    A standing body at rest on the ground with its feet at feet, its last
    ground under them, facing along yaw
--]]

function Stairs.body(feet: vector, yaw: number): State
	local state: State = Course.state(feet, true)
	state.facing = yaw

	return state
end

-- A jump press with no move, looking along yaw
function Stairs.press(yaw: number): Command
	local order: Command = Course.command()
	order.yaw = yaw
	order.jump, order.pressed.jump = true, true

	return order
end

return Stairs
