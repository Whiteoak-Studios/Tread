--[[
    The first-person cases' rigs: a world rig and its copy cloned from the
    rig pool's template, attire welded on as a game's hooks weld it, and the
    LocalTransparencyModifier each part reads on this screen
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Environment = require("../../Environment")

local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local SHOWN: number = 0 -- What a part never hidden reads in the engine, which Lune holds no default for

export type Copy = {
	rig: Model,
	joints: { [string]: AnimationConstraint },
}

local Owner = {
	-- The template's parts in each region of the copy, by name
	head = { "Head" },
	chest = { "UpperTorso" },
	arms = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" },
	body = {
		"HumanoidRootPart",
		"LowerTorso",
		"LeftUpperLeg",
		"LeftLowerLeg",
		"LeftFoot",
		"RightUpperLeg",
		"RightLowerLeg",
		"RightFoot",
	},
}

-- An item's LocalTransparencyModifier, 0 for one Tread never set
local function read(item: any): number
	local got: boolean, value: any = pcall(function (): number
		return item.LocalTransparencyModifier
	end)

	if got then
		return value
	end

	return SHOWN
end

--[[
    A world rig and a copy, each a clone of a fresh template, the copy with
    its own joints by logical name, as the pool holds them
--]]

function Owner.rigs(): (Model, Copy)
	local Rig: any = Environment.load(RIG)
	local template: Model = Rig.template()

	local world: Model = template:Clone()
	local copy: Model = template:Clone()

	local joints: { [string]: AnimationConstraint } = {}
	for logical: string, name: string in Rig.joints do
		joints[logical] = copy:FindFirstChild(name, true) :: AnimationConstraint
	end

	return world, { rig = copy, joints = joints }
end

--[[
    A piece of attire parented to the rig itself and held to a part by the
    weld named: a Weld or Motor6D, a WeldConstraint, or a RigidConstraint on
    an attachment in each part
--]]

function Owner.wear(rig: Model, name: string, onto: BasePart, weld: string): BasePart
	local piece: any = roblox.Instance.new("Part")
	piece.Name = name
	piece.Parent = rig

	local joint: any = roblox.Instance.new(weld)
	if weld == "RigidConstraint" then
		local attachment0: any = roblox.Instance.new("Attachment")
		attachment0.Parent = onto
		local attachment1: any = roblox.Instance.new("Attachment")
		attachment1.Parent = piece

		joint.Attachment0 = attachment0
		joint.Attachment1 = attachment1
	else
		joint.Part0 = onto
		joint.Part1 = piece
	end
	joint.Parent = piece

	return piece
end

-- The first descendant of a rig with the name given, erroring naming it when there is none
function Owner.find(rig: Model, name: string): any
	local found: Instance? = rig:FindFirstChild(name, true)
	if not found then
		error(`{rig.Name} holds nothing named {name}`, 2)
	end

	return found
end

-- The LocalTransparencyModifier of a rig's first descendant by the name given
function Owner.level(rig: Model, name: string): number
	return read(Owner.find(rig, name))
end

--[[
    The first of the names whose part reads another level than the one
    given, with what it reads, or nil when they all read it
--]]

function Owner.differs(rig: Model, names: { string }, expected: number): string?
	for _, name: string in names do
		local value: number = Owner.level(rig, name)
		if value ~= expected then
			return `{name} reads {value}`
		end
	end

	return nil
end

--[[
    The first part or decal anywhere in a rig that reads another level than
    the one given, with what it reads, or nil when they all read it
--]]

function Owner.all(rig: Model, expected: number): string?
	for _, item: any in rig:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			local value: number = read(item)
			if value ~= expected then
				return `{item:GetFullName()} reads {value}`
			end
		end
	end

	return nil
end

return Owner
