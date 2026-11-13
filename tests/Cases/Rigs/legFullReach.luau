--[[
    A planted leg whose target sits exactly at its full reach puts its
    ankle there with the leg straight and every Transform a real number:
    the fixture's straight legs on flat ground, and a target down and ahead
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
local LINE: number = 1e-3 -- Studs a knee may sit off its leg's line, which a float32 hair short of full reach bends it by
local REST: number = 0.1 -- Degrees a joint may turn on flat ground, where the fixture's legs rest straight
local DOWN_AHEAD: any = Vector3.new(0, -1, -0.5) -- The way a full-reach target lies from the hip

-- A floor whose top is the soles
local FLOOR: { [string]: any } = {
	name = "Floor",
	center = vector.create(0, -0.5, 0),
	size = vector.create(20, 1, 20),
	tilt = 0,
}

-- Whether every component of a joint's Transform is a real number, not NaN
local function real(joint: any): boolean
	local components: { number } = { joint.Transform:GetComponents() }
	for _, component: number in components do
		if component ~= component then
			return false
		end
	end

	return true
end

return function (): (boolean, string | nil)
	local Animate = Environment.load(ANIMATE)
	local Collision = Environment.load(COLLISION)
	local Legs = Environment.load(LEGS)

	local rig: any, joints: any = Legs.rig()
	local root: any = rig.PrimaryPart
	local reach: number = root.CFrame.Position.Y -- The root's height above the soles, which stand at 0
	local animated: any = Legs.animated(rig, joints)
	local left: any = animated.legs[1]
	local rest: any = Legs.posed(rig, joints, left.place)

	-- 1) Flat ground: each target is the ankle's rest, at the straight leg's full reach
	Animate.plant(animated, root, 0, reach, Collision({ FLOOR }), true, true)
	Animate.layer(animated)

	for _, leg: any in animated.legs do
		local before: any = Legs.posed(rig, joints, leg.place)
		local names: { string } = { leg.place.hip, leg.place.knee, leg.place.ankle }
		for _, name: string in names do
			local turned: number = Legs.degrees(CFrame.identity, joints[name].Transform)
			if not real(joints[name]) then
				return false, `On flat ground, {name}'s Transform holds a NaN`
			elseif turned > REST then
				return false, `On flat ground, {name} turned {turned} degrees, where its leg rests straight`
			end
		end

		local ahead: number, aside: number = Legs.knee(before, root.CFrame)
		if math.abs(ahead) > LINE or math.abs(aside) > LINE then
			return false, `On flat ground, {leg.place.knee} sat {ahead} ahead and {aside} aside of its straight leg`
		end
	end

	-- 2) A target down and ahead at exactly the bones' lengths from the hip
	local length: number = (rest.knee - rest.hip).Magnitude + (rest.ankle - rest.knee).Magnitude
	local target: any = rest.hip + DOWN_AHEAD.Unit * length
	left.target = Legs.inRoot(rig, target)
	Animate.layer(animated)

	local posed: any = Legs.posed(rig, joints, left.place)
	local off: number = (posed.ankle - target).Magnitude
	local ahead: number, aside: number = Legs.knee(posed, root.CFrame)

	if off > TOLERANCE then
		return false, `At full reach down and ahead, the left ankle sat {off} studs from its target`
	elseif math.abs(ahead) > LINE or math.abs(aside) > LINE then
		return false, `At full reach down and ahead, the left knee sat {ahead} ahead and {aside} aside of its line`
	elseif not real(joints.LeftHip) or not real(joints.LeftKnee) or not real(joints.LeftAnkle) then
		return false, "At full reach down and ahead, a left leg Transform holds a NaN"
	end

	return true, nil
end
