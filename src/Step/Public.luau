--[[
    The State both handles hand a game, on Vector3 and CFrame: the step's
    state crossed over with its hull center and its standing and lying
    boxes, and the look direction a command's base look and head offset give
--]]

--!strict
local Constants = require(script.Parent.Parent.Constants)
local Engine = require(script.Parent.Engine)
local Hulls = require(script.Parent.Hulls)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)

local TURN: number = 2 * math.pi -- Radians a turn, which a u16 angle counts in ANGLE_STEPS
local PITCH_LIMIT: number = Constants.PITCH_LIMIT / Constants.ANGLE_STEPS * TURN -- A quarter turn either way

type LyingBox = State.LyingBox
type Mode = State.Mode
type MoveMode = State.MoveMode
type Posture = State.Posture
type Settings = State.Settings
type StepState = State.State
type World = State.World

-- A box a game's checks read: its CFrame, turned with the body, and its full size along that CFrame's own axes
export type Box = {
	cframe: CFrame,
	size: Vector3,
}

-- The state a handle gives a game, every position, direction and size on Vector3
export type State = {
	root: Vector3, -- The feet, the hull's bottom center
	facing: number, -- Radians, along -Z at 0 and -X at a quarter turn
	velocity: Vector3,
	grounded: boolean,
	groundNormal: Vector3, -- Zero off the ground
	groundMaterial: Enum.Material,
	mode: Mode,
	posture: Posture,
	moveMode: MoveMode,
	eye: Vector3, -- The cleared eye
	look: Vector3, -- The look direction, a unit vector
	hullCenter: Vector3,
	standingBox: Box, -- The hull as it stands, crouched for a crouched, downed or swimming body
	lyingBox: Box, -- The body lying along its facing, which a downed body's checks read
	apex: number, -- The fall apex's height since the last ground, ladder or water contact
	platform: number, -- The ridden platform's id, 0 for none
	epoch: number,
}

local Public = {}

--[[
    A public state with every field set: at rest at the origin, airborne,
    standing and walking, with both boxes at the origin and empty, for a
    handle to fill
--]]

function Public.new(): State
	return {
		root = Vector3.zero,
		facing = 0,
		velocity = Vector3.zero,
		grounded = false,
		groundNormal = Vector3.zero,
		groundMaterial = Enum.Material.Air,
		mode = "Air",
		posture = "Stand",
		moveMode = "Walk",
		eye = Vector3.zero,
		look = Vector3.zero,
		hullCenter = Vector3.zero,
		standingBox = { cframe = CFrame.identity, size = Vector3.zero },
		lyingBox = { cframe = CFrame.identity, size = Vector3.zero },
		apex = 0,
		platform = 0,
		epoch = 0,
	}
end

-- A CFrame at x, y and z turned about Y by a facing's sine and cosine, its look along -Z at 0 and -X at a quarter turn
local function turned(x: number, y: number, z: number, sine: number, cosine: number): CFrame
	-- The rotation matrix's rows, a turn about the world's up
	return CFrame.new(x, y, z, cosine, 0, sine, 0, 1, 0, -sine, 0, cosine)
end

--[[
    Fills every field of a public state in place from the step's state and
    the world's settings, keeping its box tables: the hull's center at its
    height for the posture, the standing box that hull turned by the
    facing, and the lying box from the settings at the feet, its center
    lifted off the ground and its length along the facing

    @ eye | the cleared eye the handle hands in
    @ look | the look direction it hands in, a unit vector
--]]

function Public.fill(into: State, state: StepState, world: World, eye: vector, look: vector)
	local settings: Settings = world.settings
	local feet: vector = state.position
	local height: number = Hulls.height(state, settings)
	local width: number = settings.radius + settings.radius
	local center: number = feet.y + height / 2
	local sine: number = Math.sin(state.facing)
	local cosine: number = Math.cos(state.facing)

	into.root = Engine.toVector3(feet)
	into.facing = state.facing
	into.velocity = Engine.toVector3(state.velocity)
	into.grounded = state.grounded
	into.groundNormal = Engine.toVector3(state.groundNormal)
	into.groundMaterial = state.groundMaterial
	into.mode = state.mode
	into.posture = state.posture
	into.moveMode = state.moveMode
	into.eye = Engine.toVector3(eye)
	into.look = Engine.toVector3(look)
	into.hullCenter = Vector3.new(feet.x, center, feet.z)
	into.apex = state.apex
	into.platform = state.platform
	into.epoch = state.epoch

	local standing: Box = into.standingBox
	standing.cframe = turned(feet.x, center, feet.z, sine, cosine)
	standing.size = Vector3.new(width, height, width)

	-- The width across the facing, the height up and the length along it
	local shape: LyingBox = settings.lyingBox
	local lying: Box = into.lyingBox
	lying.cframe = turned(feet.x, feet.y + shape.lift, feet.z, sine, cosine)
	lying.size = Vector3.new(shape.width, shape.height, shape.length)
end

--[[
    A command's look direction, along -Z at a yaw and pitch of 0: the base
    look in radians turned by the head offset in degrees, the offset held
    to the game's cone as the step holds a command's, and the pitch to a
    quarter turn either way

    @ cone | the shared table's step.headCone, degrees
--]]

function Public.look(yaw: number, pitch: number, headYaw: number, headPitch: number, cone: number): vector
	local lookYaw: number = yaw + math.rad(math.clamp(headYaw, -cone, cone))
	local raised: number = pitch + math.rad(math.clamp(headPitch, -cone, cone))
	local lookPitch: number = math.clamp(raised, -PITCH_LIMIT, PITCH_LIMIT)
	local level: number = Math.cos(lookPitch)

	return vector.create(-Math.sin(lookYaw) * level, Math.sin(lookPitch), -Math.cos(lookYaw) * level)
end

return Public
