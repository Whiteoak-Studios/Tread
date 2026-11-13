--[[
    A planted leg whose target is in reach puts its ankle on the target and
    its foot the way it rests, its knee ahead along the facing: over a
    step, under hips their pose lowers, and toward a target set aside
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
local FLAT: number = 0.01 -- Degrees a foot may turn from the way it rests
local RISE: number = 1 -- Studs the step stands above the floor
local LOWERED: number = 0.6 -- Studs the hips' pose drops them
local ASIDE: vector = vector.create(0.3, 0.6, -0.4) -- A target's move from the ankle's rest: right, up and ahead

-- A floor whose top is the soles, and a step under the left foot alone
local FLOOR: { [string]: any } = {
	name = "Floor",
	center = vector.create(0, -0.5, 0),
	size = vector.create(20, 1, 20),
	tilt = 0,
}
local STEP: { [string]: any } = {
	name = "Step",
	center = vector.create(-0.75, RISE / 2, 0),
	size = vector.create(1.5, RISE, 2),
	tilt = 0,
}

return function (): (boolean, string | nil)
	local Animate = Environment.load(ANIMATE)
	local Collision = Environment.load(COLLISION)
	local Legs = Environment.load(LEGS)

	local rig: any, joints: any = Legs.rig()
	local root: any = rig.PrimaryPart
	local reach: number = root.CFrame.Position.Y -- The root's height above the soles, which stand at 0
	local animated: any = Legs.animated(rig, joints)
	local left: any, right: any = animated.legs[1], animated.legs[2]

	local restLeft: any = Legs.posed(rig, joints, left.place)
	local restRight: any = Legs.posed(rig, joints, right.place)

	-- Why a leg missed: its ankle off the point, its foot turned from its rest, or its knee not ahead
	local function miss(leg: any, rest: any, expected: any, bent: boolean, when: string): string?
		local posed: any = Legs.posed(rig, joints, leg.place)
		local off: number = (posed.ankle - expected).Magnitude
		local turned: number = Legs.degrees(posed.foot, rest.foot)
		local ahead: number = Legs.knee(posed, root.CFrame)

		if off > TOLERANCE then
			return `{when}, {leg.place.ankle} sat {off} studs from {expected}`
		elseif turned > FLAT then
			return `{when}, {leg.place.ankle}'s foot turned {turned} degrees from its rest`
		elseif bent and not (ahead > 0) then
			return `{when}, {leg.place.knee} sat {ahead} studs ahead of its leg's line, not ahead of it`
		end

		return nil
	end

	-- 1) Over the step, the left ankle rises by the step and the right one rests
	Animate.plant(animated, root, 0, reach, Collision({ FLOOR, STEP }), true, true)
	Animate.layer(animated)

	local raised: any = restLeft.ankle + Vector3.new(0, RISE, 0)
	local stepped: string? = miss(left, restLeft, raised, true, "Over the step")
		or miss(right, restRight, restRight.ankle, false, "Beside the step")
	if stepped then
		return false, stepped
	end

	-- 2) Hips the pose lowers bend both knees, and the ankles stay on their targets
	joints.Root.Transform = CFrame.new(0, -LOWERED, 0)
	Animate.layer(animated)

	local lowered: string? = miss(left, restLeft, raised, true, "Under lowered hips over the step")
		or miss(right, restRight, restRight.ankle, true, "Under lowered hips beside the step")
	if lowered then
		return false, lowered
	end

	-- 3) A target aside, ahead and up
	joints.Root.Transform = CFrame.identity
	right.target = right.place.rest + ASIDE
	Animate.layer(animated)

	local aside: any = restRight.ankle + Vector3.new(ASIDE.x, ASIDE.y, ASIDE.z)
	local moved: string? = miss(right, restRight, aside, true, "Toward a target aside")
	if moved then
		return false, moved
	end

	return true, nil
end
