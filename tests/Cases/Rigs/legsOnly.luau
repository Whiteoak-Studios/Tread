--[[
    The layer's bend writes only a planted leg's hip, knee and ankle: every
    other joint keeps the Transform it had, the Root's pose it reads among
    them, as does a leg whose ray found nothing and a rig let go
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local CFrame: any = roblox.CFrame

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local LEGS: string = "tests/Fixtures/Rigs/Legs.luau"

local MARK: number = 0.01 -- Radians each joint's own mark turns it by, one more step per joint
local RISE: number = 1 -- Studs the step stands above the soles

-- A step under the left foot and no other ground, so the right foot's ray finds nothing
local STEP: { [string]: any } = {
	name = "Step",
	center = vector.create(-0.75, RISE / 2, 0),
	size = vector.create(1.5, RISE, 2),
	tilt = 0,
}

-- The joints the left leg's bend writes
local BENT: { [string]: boolean } = { LeftHip = true, LeftKnee = true, LeftAnkle = true }

return function (): (boolean, string | nil)
	local Animate = Environment.load(ANIMATE)
	local Collision = Environment.load(COLLISION)
	local Legs = Environment.load(LEGS)

	local rig: any, joints: any = Legs.rig()
	local root: any = rig.PrimaryPart
	local reach: number = root.CFrame.Position.Y -- The root's height above the soles, which stand at 0
	local animated: any = Legs.animated(rig, joints)

	-- Every joint gets a mark of its own, so a write to any of them shows
	local names: { string } = {}
	for name: string in joints do
		table.insert(names, name)
	end
	table.sort(names)

	-- Each mark is kept as read back, since Lune stores a Transform's turn a little rounded
	local marks: { [string]: any } = {}
	local function mark()
		for index: number, name: string in names do
			joints[name].Transform = CFrame.Angles(MARK * index, 0, 0)
			marks[name] = joints[name].Transform
		end
	end
	mark()

	-- 1) Planted over the step, only the left leg's three joints change
	Animate.plant(animated, root, 0, reach, Collision({ STEP }), true, true)
	if animated.legs[2].planted then
		return false, "The right foot, over nothing, was planted"
	end

	Animate.layer(animated)

	for _, name: string in names do
		local kept: boolean = joints[name].Transform == marks[name]
		if BENT[name] and kept then
			return false, `The planted left leg's {name} kept its mark, so the bend wrote nothing to it`
		elseif not BENT[name] and not kept then
			return false, `The bend wrote {name}, which is not a planted leg's joint`
		end
	end

	-- 2) A rig let go writes no joint at all
	mark()

	Animate.plant(animated, root, 0, reach, Collision({ STEP }), false, false)
	Animate.layer(animated)

	for _, name: string in names do
		if joints[name].Transform ~= marks[name] then
			return false, `A rig whose feet were let go had its {name} written`
		end
	end

	return true, nil
end
