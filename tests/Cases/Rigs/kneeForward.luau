--[[
    A leg planted on a step bends its knee forward along the rig's facing,
    with none of it to the side, and its ankle on the step, whichever way
    the rig faces
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local CFrame: any = roblox.CFrame
local Vector3: any = roblox.Vector3

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local LEGS: string = "tests/Fixtures/Rigs/Legs.luau"

local TOLERANCE: number = 1e-4 -- Studs an ankle may sit from its target
local SIDEWAYS: number = 1e-3 -- Studs a knee may sit to the side of its leg's line
local FORWARD: number = 0.5 -- Studs the knee must sit ahead, where a stud's rise bends the fixture's leg about 0.97
local RISE: number = 1 -- Studs the step stands above the floor
local STEP_WIDTH: number = 0.6 -- The step's width and depth, under the left foot alone
local SPOT: { number } = { 5, 0, -2 } -- Where the rig's soles stand
local FACINGS: { number } = { 0, math.pi / 2, math.pi, -math.pi / 2, 2.5 }

-- A floor whose top is the soles
local FLOOR: { [string]: any } = {
	name = "Floor",
	center = vector.create(0, -0.5, 0),
	size = vector.create(40, 1, 40),
	tilt = 0,
}

return function (): (boolean, string | nil)
	local Animate = Environment.load(ANIMATE)
	local Collision = Environment.load(COLLISION)
	local Legs = Environment.load(LEGS)

	for _, facing: number in FACINGS do
		local rig: any, joints: any = Legs.rig()
		local root: any = rig.PrimaryPart
		local reach: number = root.CFrame.Position.Y -- The root's height above the soles
		root.CFrame = CFrame.new(SPOT[1], SPOT[2] + reach, SPOT[3]) * CFrame.Angles(0, facing, 0)

		local animated: any = Legs.animated(rig, joints)
		local left: any = animated.legs[1]
		local rest: any = Legs.posed(rig, joints, left.place)

		-- The step goes wherever the facing puts the left foot
		local foot: any = root.CFrame:PointToWorldSpace(left.place.foot)
		local step: { [string]: any } = {
			name = "Step",
			center = vector.create(foot.X, RISE / 2, foot.Z),
			size = vector.create(STEP_WIDTH, RISE, STEP_WIDTH),
			tilt = 0,
		}

		Animate.plant(animated, root, SPOT[2], reach, Collision({ FLOOR, step }), true, true)
		Animate.layer(animated)

		local posed: any = Legs.posed(rig, joints, left.place)
		local off: number = (posed.ankle - (rest.ankle + Vector3.new(0, RISE, 0))).Magnitude
		local ahead: number, aside: number = Legs.knee(posed, root.CFrame)

		if off > TOLERANCE then
			return false, `Facing {facing}, the left ankle sat {off} studs from the step`
		elseif not (ahead > FORWARD) then
			return false, `Facing {facing}, the left knee sat {ahead} studs ahead along the facing, not past {FORWARD}`
		elseif math.abs(aside) > SIDEWAYS then
			return false, `Facing {facing}, the left knee sat {aside} studs to the side of its leg's line`
		end
	end

	return true, nil
end
