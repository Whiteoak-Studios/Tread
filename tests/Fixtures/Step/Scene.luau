--[[
    The step's fixture scene: Frontier Zero's step settings, and the worlds
    and states the step's cases and the live scenario build from them
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation, in Hz

type Allow = State.Allow
type Collision = State.Collision
type RuleStep = State.RuleStep
type Settings = State.Settings
type State = State.State
type World = State.World

-- Frontier Zero's step block, as its shared table gives it
local SETTINGS: Settings = {
	gravity = 68.1,
	terminal = 138.9,
	walk = 10,
	sprint = 18,
	crouch = 6,
	swim = 3.04,
	swimSprint = 6.09,
	ladder = 3.04,
	ladderSprint = 6.09,
	jump = 25,
	stepHeight = 0.69,
	walkable = 0.643,
	standable = 0.5,
	landing = 0.3,
	airEase = 3,
	ladderEase = 20,
	waterEase = 5,
	waterEntry = 0.1,
	radius = 1.39,
	standing = 5,
	crouched = 3.06,
	eyeStanding = 4.17,
	eyeCrouched = 2.5,
	eyeDowned = 0.97,
	eyeEase = 10,
	clearance = 1.45,
	clearanceStart = 1.5,
	lean = 20,
	leanShift = Vector3.new(0.57, -0.1, 0),
	leanRate = 200, -- Frontier Zero's own is unset, and no step case reads it
	headCone = 75,
	ladderDrop = 30,
	swimEnter = 3.25,
	swimLeave = 2.71,
	floatDepth = 1.83,
	crouchDepth = 2.22,
	mantleHeight = 4,
	mantleReach = 1.39, -- The hull's radius
	mantleTime = 0.5,
	mantleArc = 0.5,
	ladderJump = 25,
	headSlide = 4, -- Frontier Zero's own is unset, and no step case reads it
	lyingBox = { length = 5, width = 2, height = 2, lift = 1 },
}

local Scene = {
	settings = SETTINGS,
}

-- A rules function that refuses nothing and caps no speed
local function rules(_: RuleStep, _: Allow): number
	return math.huge
end

--[[
    A server's world over a collision, with the live bodies given, none by
    default, at Frontier Zero's simulation rate
--]]

function Scene.world(collision: Collision, bodies: { State }?): World
	return {
		settings = SETTINGS,
		collision = collision,
		water = nil,
		rules = rules,
		isServer = true,
		delta = 1 / SIMULATION_RATE,
		tick = 0,
		leanShift = Engine.toVector(SETTINGS.leanShift),
		ladders = {},
		bodies = bodies or {},
		platforms = {},
		clock = 0,
	}
end

--[[
    A standing body with its feet at feet, on the ground or in the air
--]]

function Scene.state(feet: vector, grounded: boolean): State
	local state: State = State.new()
	state.position = feet
	state.grounded = grounded

	if grounded then
		state.mode = "Ground"
	end

	return state
end

return Scene
