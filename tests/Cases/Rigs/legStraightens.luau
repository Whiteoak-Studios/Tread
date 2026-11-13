--[[
    A planted leg whose target is out of reach lies straight toward it at its
    bones' lengths, its foot the way it rests: over ground a stud too low,
    and toward a target far ahead and down
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local Vector3: any = roblox.Vector3

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local LEGS: string = "tests/Fixtures/Rigs/Legs.luau"

local TOLERANCE: number = 1e-4 -- Studs a pivot may sit from where the straight leg puts it
local FLAT: number = 0.01 -- Degrees a foot may turn from the way it rests
local DROP: number = 1 -- Studs the low floor's top sits below the soles
local FAR: vector = vector.create(0, -1.5, -1) -- A target's move from the ankle's rest, out of reach down and ahead

-- A floor a stud below the soles, which the straight legs can't reach
local LOW: { [string]: any } = {
	name = "Low",
	center = vector.create(0, -DROP - 0.5, 0),
	size = vector.create(20, 1, 20),
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

	-- Why a posed leg missed the straight line from its hip toward a point, at its bones' rest lengths
	local function miss(leg: any, rest: any, toward: any, when: string): string?
		local thigh: number = (rest.knee - rest.hip).Magnitude
		local shin: number = (rest.ankle - rest.knee).Magnitude

		local posed: any = Legs.posed(rig, joints, leg.place)
		local along: any = (toward - posed.hip).Unit
		local knee: number = (posed.knee - (posed.hip + along * thigh)).Magnitude
		local ankle: number = (posed.ankle - (posed.hip + along * (thigh + shin))).Magnitude
		local turned: number = Legs.degrees(posed.foot, rest.foot)

		if knee > TOLERANCE or ankle > TOLERANCE then
			return `{when}, {leg.place.hip}'s leg sat off its straight line, the knee {knee} and the ankle {ankle} studs`
		elseif turned > FLAT then
			return `{when}, {leg.place.ankle}'s foot turned {turned} degrees from its rest`
		end

		return nil
	end

	-- 1) Ground a stud too low leaves both legs straight down toward it
	Animate.plant(animated, root, 0, reach, Collision({ LOW }), true, true)
	Animate.layer(animated)

	local below: any = Vector3.new(0, DROP, 0)
	local low: string? = miss(left, restLeft, restLeft.ankle - below, "Over ground too low")
		or miss(right, restRight, restRight.ankle - below, "Over ground too low")
	if low then
		return false, low
	end

	-- 2) A target far ahead and down straightens the left leg toward it
	left.target = left.place.rest + FAR
	Animate.layer(animated)

	local far: string? = miss(left, restLeft, restLeft.ankle + Vector3.new(FAR.x, FAR.y, FAR.z), "Toward a far target")
	if far then
		return false, far
	end

	return true, nil
end
