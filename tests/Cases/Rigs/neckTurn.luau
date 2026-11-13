--[[
    The layer turns the neck by the head offset on top of its pose, the way
    the published eye adds the offset to the base look, and the waist by the
    aim's yaw and pitch the same way, each on its own joint alone
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local CFrame: any = roblox.CFrame

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local LEGS: string = "tests/Fixtures/Rigs/Legs.luau"
local PUBLIC: string = "src/Step/Public.luau"

local HEAD_YAW: number = 0.6 -- Radians
local HEAD_PITCH: number = -0.3
local PITCH: number = 0.4
local YAW: number = -0.2
local CONE: number = 90 -- Degrees, wider than the head offset, so the look holds it whole
local CLOSE: number = 1e-5 -- A CFrame holds 32-bit floats

-- Whether a joint's Transform looks along a direction, and why not
local function along(name: string, joint: any, look: vector): string?
	local got: any = joint.Transform.LookVector
	if math.abs(got.X - look.x) > CLOSE or math.abs(got.Y - look.y) > CLOSE or math.abs(got.Z - look.z) > CLOSE then
		return `The {name} looked along {got}, not {look}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Animate = Environment.load(ANIMATE)
	local Legs = Environment.load(LEGS)
	local Public = Environment.load(PUBLIC)

	-- The stand-in holds the waist's layer, so the neck's joins it at rest
	local rig: any, joints: any = Legs.rig()
	local animated: any = Legs.animated(rig, joints)
	animated.neck = joints.Neck
	animated.pitch = 0
	animated.yaw = 0
	animated.lean = 0
	animated.headYaw = 0
	animated.headPitch = 0
	animated.turn = CFrame.identity
	animated.turned = false

	-- 1) A head offset alone turns the neck, and the waist keeps its pose
	Animate.aim(animated, 0, 0, 0, HEAD_YAW, HEAD_PITCH)
	Animate.layer(animated)

	local head: vector = Public.look(0, 0, math.deg(HEAD_YAW), math.deg(HEAD_PITCH), CONE)
	local problem: string? = along("neck", joints.Neck, head)
	if problem then
		return false, `With a head offset: {problem}`
	elseif joints.Waist.Transform ~= CFrame.identity then
		return false, `A head offset turned the waist to {joints.Waist.Transform}`
	end

	-- 2) An aim with a yaw turns the waist, and the neck, its offset gone, keeps its pose
	joints.Neck.Transform = CFrame.identity
	Animate.aim(animated, PITCH, 0, YAW, 0, 0)
	Animate.layer(animated)

	problem = along("waist", joints.Waist, Public.look(YAW, PITCH, 0, 0, CONE))
	if problem then
		return false, `With an aim's yaw and pitch: {problem}`
	elseif joints.Neck.Transform ~= CFrame.identity then
		return false, `With no head offset the neck turned to {joints.Neck.Transform}`
	end

	return true, nil
end
