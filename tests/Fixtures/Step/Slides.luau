--[[
    The crouch slide's fixture: Frontier Zero's step settings with the dev
    place's slide, a floor inside the wire bounds with a wall, a ledge, a
    shelf and ramps tilted about Z, and the worlds, states and commands
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Collision)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local Scene = require(script.Parent.Scene)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Step = require(ReplicatedStorage.Packages.Tread.Step)
local World = require(ReplicatedStorage.Packages.Tread.Step.World)

local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation, in Hz
local SKIN: number = Constants.SKIN
local FLOOR: number = 500 -- The floor's top, inside the record's height window
local FLOOR_SIZE: vector = vector.create(240, 2, 240)
local RAMP_THICKNESS: number = 2
local RAMP_WIDTH: number = 10 -- Along Z
local RAMP_LENGTH: number = 90 -- Up its tilt
local RAMP_FOOT_X: number = -110 -- Where each ramp's low edge meets the floor, so a ramp falls toward -X
local LEDGE_DROP: number = 1 -- The ledge's top over the floor, past the walk's snap

type Allow = State.Allow
type Collision = State.Collision
type Command = State.Command
type Part = Geometry.Part
type RuleStep = State.RuleStep
type Rules = State.Rules
type Settings = State.Settings
type SlideSettings = State.Slide
type State = State.State
type World = State.World

local Slides = {}

-- The dev place's slide, from the research's values
local SLIDE: SlideSettings = {
	start = 15,
	boost = 0,
	friction = 6,
	slope = 0.5,
	max = 27,
	stop = 6,
	steer = 60,
	cooldown = 2,
}

--[[
    Frontier Zero's step settings with a slide, its values the dev place's
    and any of them changed as given, a fresh table each call
--]]

function Slides.settings(changes: { [string]: number }?): Settings
	local settings: Settings = table.clone(Scene.settings)
	local slide: SlideSettings = table.clone(SLIDE)

	for key: string, value: number in changes or {} do
		(slide :: any)[key] = value
	end

	settings.slide = slide

	return settings
end

-- An axis-aligned part by its center and size
local function block(name: string, center: vector, size: vector): Part
	return { name = name, center = center, size = size, tilt = 0 }
end

-- A ramp along Z at z, its low edge on the floor at the foot and its top face rising toward +X at a tilt in degrees
local function ramp(name: string, z: number, tilt: number): Part
	local radians: number = math.rad(tilt)
	local along: vector = vector.create(math.cos(radians), math.sin(radians), 0)
	local normal: vector = vector.create(-math.sin(radians), math.cos(radians), 0)
	local foot: vector = vector.create(RAMP_FOOT_X, FLOOR, z)

	return {
		name = name,
		center = foot + along * (RAMP_LENGTH / 2) - normal * (RAMP_THICKNESS / 2),
		size = vector.create(RAMP_LENGTH, RAMP_THICKNESS, RAMP_WIDTH),
		tilt = tilt,
	}
end

Slides.floor = FLOOR
Slides.resting = Math.quantize(FLOOR + SKIN) -- Feet at rest on the floor, on the quanta
Slides.rampFoot = RAMP_FOOT_X
Slides.ledgeDrop = LEDGE_DROP
Slides.east = -math.pi / 2 -- A yaw that looks along +X
Slides.west = math.pi / 2 -- A yaw that looks along -X, down every ramp

-- The wall a slide along -Z meets in the x = 40 lane, its face toward +Z at z = 40.5
Slides.wall = block("Wall", vector.create(40, FLOOR + 4, 40), vector.create(10, 8, 1))

-- The ledge in the x = 70 lane, its top a stud over the floor and its edge toward -Z at z = 40
Slides.ledge = block("Ledge", vector.create(70, FLOOR + LEDGE_DROP / 2, 60), vector.create(10, LEDGE_DROP, 40))

-- A shelf to mantle in the x = 100 lane, 3 studs tall, its face toward +Z at z = 20
Slides.shelf = block("Shelf", vector.create(100, FLOOR + 1.5, 15), vector.create(10, 3, 10))

Slides.ramps = {
	gentle = ramp("Gentle", -60, 10),
	steep = ramp("Steep", -30, 25),
	steeper = ramp("Steeper", 0, 30),
}

Slides.parts = {
	block("Floor", vector.create(0, FLOOR - FLOOR_SIZE.y / 2, 0), FLOOR_SIZE),
	Slides.wall,
	Slides.ledge,
	Slides.shelf,
	Slides.ramps.gentle,
	Slides.ramps.steep,
	Slides.ramps.steeper,
} :: { Part }

-- A rules function that refuses nothing and caps no speed
local function free(_: RuleStep, _: Allow): number
	return math.huge
end

--[[
    A server's world over the fixture's parts at Frontier Zero's simulation
    rate, with the settings given or the slide's, and the rules given or
    ones that refuse nothing
--]]

function Slides.world(settings: Settings?, rules: Rules?): World
	return World.new(settings or Slides.settings(), SIMULATION_RATE, Casts(Slides.parts), nil, rules or free, true)
end

-- Registers an axis-aligned ladder box on a world by its center and size
function Slides.ladder(world: World, center: vector, size: vector): () -> ()
	return World.addLadder(world, CFrame.new(center.x, center.y, center.z), Vector3.new(size.x, size.y, size.z))
end

--[[
    A standing body with its feet at feet, on the ground or in the air,
    on level ground when grounded, its last ground under its feet and its
    eye at the standing height
--]]

function Slides.state(feet: vector, grounded: boolean): State
	local state: State = Scene.state(feet, grounded)
	state.groundHeight = feet.y
	state.eyeHeight = Math.quantizeEye(Scene.settings.eyeStanding)

	if grounded then
		state.groundNormal = vector.create(0, 1, 0)
	end

	return state
end

-- A command with no input, numbered 1, its presses all off
function Slides.command(): Command
	return {
		number = 1,
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

--[[
    Steps a body for ticks on one command, numbered on from its own, its
    presses off after the first tick as a handler derives them
--]]

function Slides.advance(state: State, world: World, order: Command, ticks: number)
	for _ = 1, ticks do
		world.tick += 1
		Step.advance(state, order, world)

		order.number += 1
		order.pressed.jump = false
		order.pressed.crouch = false
		order.pressed.sprint = false
		order.pressed.aim = false
	end
end

-- The horizontal speed a body carries
function Slides.speed(state: State): number
	local velocity: vector = state.velocity

	return math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
end

--[[
    A body sprinting along a yaw on the floor at feet, stepped until its
    sprint holds, with sprint and forward held on the command it gives back
--]]

function Slides.sprinting(world: World, feet: vector, yaw: number): (State, Command)
	local state: State = Slides.state(feet, true)
	local order: Command = Slides.command()
	order.forward = 1
	order.sprint = true
	order.yaw = yaw
	Slides.advance(state, world, order, 2)

	return state, order
end

--[[
    Presses crouch on a command and steps one tick, the crouch held after
--]]

function Slides.crouch(state: State, world: World, order: Command)
	order.crouch = true
	order.pressed.crouch = true
	Slides.advance(state, world, order, 1)
end

-- Why a value is not exactly what it should be, or nil
function Slides.is(label: string, got: any, want: any): string?
	if got == want then
		return nil
	end

	return `{label} was {got}, where {want} was expected`
end

-- A case's verdict from why it failed, nil for a pass
function Slides.verdict(problem: string?): (boolean, string | nil)
	if problem then
		return false, problem
	end

	return true, nil
end

return Slides
