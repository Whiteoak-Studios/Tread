--[[
    The dev game's rig: a lean R15 template of plain parts sized to Frontier
    Zero's hull, its joints, one of Roblox's own R15 animations per state,
    and the hooks that tint a slot's look and put its held item in its hand
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local ROOT: string = "HumanoidRootPart"
local HAND: string = "RightHand" -- The part a held item is welded to
local HELD: string = "Held" -- The held item's part, which hold replaces
local ATTACHMENT: string = "RigAttachment" -- A joint's attachments are named for it and this, as an R15 rig's are
local SKIN: Color3 = Color3.fromRGB(234, 184, 146) -- The bare body's color, which undress puts back
local GOLDEN: number = 0.618033988749895 -- The golden ratio's fraction, which spreads each item's hue round the wheel
local SATURATION: number = 0.65 -- Each item's tint
local BRIGHTNESS: number = 0.85
local HELD_SIZE: Vector3 = Vector3.new(0.4, 0.5, 1.8) -- The held item's block, studs, its length along the hand's facing
local GRIP: CFrame = CFrame.new(0, -0.15, -0.6) -- The held item's place in the hand's space, reaching ahead of it

-- Each part's size and center, studs, standing on the origin and facing -Z: inside Frontier Zero's standing hull, 4.9
-- studs tall and 2.78 wide across the arms, with its 4.17-stud eye inside the head
local PARTS: { [string]: Piece } = {
	HumanoidRootPart = { size = Vector3.new(1.6, 1.6, 0.8), center = Vector3.new(0, 2.4, 0) },
	LowerTorso = { size = Vector3.new(1.6, 0.4, 0.8), center = Vector3.new(0, 2.4, 0) },
	UpperTorso = { size = Vector3.new(1.6, 1.3, 0.8), center = Vector3.new(0, 3.25, 0) },
	Head = { size = Vector3.new(1, 1, 1), center = Vector3.new(0, 4.4, 0) },
	LeftUpperArm = { size = Vector3.new(0.6, 0.9, 0.6), center = Vector3.new(-1.09, 3.45, 0) },
	LeftLowerArm = { size = Vector3.new(0.6, 0.8, 0.6), center = Vector3.new(-1.09, 2.6, 0) },
	LeftHand = { size = Vector3.new(0.6, 0.3, 0.6), center = Vector3.new(-1.09, 2.05, 0) },
	RightUpperArm = { size = Vector3.new(0.6, 0.9, 0.6), center = Vector3.new(1.09, 3.45, 0) },
	RightLowerArm = { size = Vector3.new(0.6, 0.8, 0.6), center = Vector3.new(1.09, 2.6, 0) },
	RightHand = { size = Vector3.new(0.6, 0.3, 0.6), center = Vector3.new(1.09, 2.05, 0) },
	LeftUpperLeg = { size = Vector3.new(0.7, 1, 0.7), center = Vector3.new(-0.4, 1.7, 0) },
	LeftLowerLeg = { size = Vector3.new(0.7, 0.95, 0.7), center = Vector3.new(-0.4, 0.725, 0) },
	LeftFoot = { size = Vector3.new(0.7, 0.25, 1), center = Vector3.new(-0.4, 0.125, -0.15) },
	RightUpperLeg = { size = Vector3.new(0.7, 1, 0.7), center = Vector3.new(0.4, 1.7, 0) },
	RightLowerLeg = { size = Vector3.new(0.7, 0.95, 0.7), center = Vector3.new(0.4, 0.725, 0) },
	RightFoot = { size = Vector3.new(0.7, 0.25, 1), center = Vector3.new(0.4, 0.125, -0.15) },
}

-- Each R15 joint's two parts and the pivot both its attachments sit at
local JOINTS: { [string]: Joint } = {
	Root = { part0 = "HumanoidRootPart", part1 = "LowerTorso", pivot = Vector3.new(0, 2.4, 0) },
	Waist = { part0 = "LowerTorso", part1 = "UpperTorso", pivot = Vector3.new(0, 2.6, 0) },
	Neck = { part0 = "UpperTorso", part1 = "Head", pivot = Vector3.new(0, 3.9, 0) },
	LeftShoulder = { part0 = "UpperTorso", part1 = "LeftUpperArm", pivot = Vector3.new(-1.09, 3.75, 0) },
	LeftElbow = { part0 = "LeftUpperArm", part1 = "LeftLowerArm", pivot = Vector3.new(-1.09, 3, 0) },
	LeftWrist = { part0 = "LeftLowerArm", part1 = "LeftHand", pivot = Vector3.new(-1.09, 2.2, 0) },
	RightShoulder = { part0 = "UpperTorso", part1 = "RightUpperArm", pivot = Vector3.new(1.09, 3.75, 0) },
	RightElbow = { part0 = "RightUpperArm", part1 = "RightLowerArm", pivot = Vector3.new(1.09, 3, 0) },
	RightWrist = { part0 = "RightLowerArm", part1 = "RightHand", pivot = Vector3.new(1.09, 2.2, 0) },
	LeftHip = { part0 = "LowerTorso", part1 = "LeftUpperLeg", pivot = Vector3.new(-0.4, 2.2, 0) },
	LeftKnee = { part0 = "LeftUpperLeg", part1 = "LeftLowerLeg", pivot = Vector3.new(-0.4, 1.2, 0) },
	LeftAnkle = { part0 = "LeftLowerLeg", part1 = "LeftFoot", pivot = Vector3.new(-0.4, 0.25, 0) },
	RightHip = { part0 = "LowerTorso", part1 = "RightUpperLeg", pivot = Vector3.new(0.4, 2.2, 0) },
	RightKnee = { part0 = "RightUpperLeg", part1 = "RightLowerLeg", pivot = Vector3.new(0.4, 1.2, 0) },
	RightAnkle = { part0 = "RightLowerLeg", part1 = "RightFoot", pivot = Vector3.new(0.4, 0.25, 0) },
}

-- Roblox's own R15 animations, which any experience may load, by the state Tread plays each for. The dev game has no
-- clips of its own, so a state Roblox has none for plays the nearest: crouching and the downed body stand, the
-- crawl walks, a landing plays the idle and the mantle climbs
local ANIMATIONS: { [string]: string } = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	sprint = "rbxassetid://507767714",
	crouchIdle = "rbxassetid://507766388",
	crouchWalk = "rbxassetid://507777826",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
	land = "rbxassetid://507766388",
	swimIdle = "rbxassetid://507785072",
	swim = "rbxassetid://507784897",
	climb = "rbxassetid://507765644",
	mantle = "rbxassetid://507765644",
	downed = "rbxassetid://507766388",
	crawl = "rbxassetid://507777826",
}

-- The parts each worn slot tints, by the slot-table field's name
local COVERS: { [string]: { string } } = {
	face = { "Head" },
	head = { "Head" },
	shirt = { "UpperTorso", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" },
	torso = { "UpperTorso" },
	pants = { "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" },
	leg = { "LeftLowerLeg", "LeftFoot", "RightLowerLeg", "RightFoot" },
}

-- The order the slots go on in, so a piece worn over another shows where both cover a part
local ORDER: { string } = { "face", "head", "shirt", "torso", "pants", "leg" }

-- The slots the first-person copy leaves off, since it never shows the head
local OFF_COPY: { [string]: boolean } = { face = true, head = true }

type Piece = { size: Vector3, center: Vector3 }
type Joint = { part0: string, part1: string, pivot: Vector3 }

local Rig = {
	joints = {} :: { [string]: string }, -- Each logical joint's name in the template, which names every joint for it
}

for name: string in JOINTS do
	Rig.joints[name] = name
end

-- An item id's tint, the same on every client for the same id
local function tint(id: number): Color3
	return Color3.fromHSV(id * GOLDEN % 1, SATURATION, BRIGHTNESS)
end

--[[
    The template the pool clones: the 16 parts under their R15 names, none
    colliding, queried or touched, only the root anchored and the root its
    PrimaryPart, each joint a kinematic AnimationConstraint under its Part1
    on attachments at its pivot, and an AnimationController with an Animator
--]]

function Rig.template(): Model
	local model: Model = Instance.new("Model")
	model.Name = "DevRig"

	local parts: { [string]: Part } = {}
	for name: string, piece: Piece in PARTS do
		local part: Part = Instance.new("Part")
		part.Name = name
		part.Size = piece.size
		part.CFrame = CFrame.new(piece.center)
		part.Color = SKIN
		part.Anchored = name == ROOT
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = false
		part.CastShadow = true
		part.Parent = model
		parts[name] = part
	end

	parts[ROOT].Transparency = 1
	model.PrimaryPart = parts[ROOT]

	for name: string, joint: Joint in JOINTS do
		local part0: Part = parts[joint.part0]
		local part1: Part = parts[joint.part1]

		local attachment0: Attachment = Instance.new("Attachment")
		attachment0.Name = `{name}{ATTACHMENT}`
		attachment0.CFrame = CFrame.new(joint.pivot - part0.CFrame.Position)
		attachment0.Parent = part0

		local attachment1: Attachment = Instance.new("Attachment")
		attachment1.Name = `{name}{ATTACHMENT}`
		attachment1.CFrame = CFrame.new(joint.pivot - part1.CFrame.Position)
		attachment1.Parent = part1

		local constraint: AnimationConstraint = Instance.new("AnimationConstraint")
		constraint.Name = name
		constraint.Attachment0 = attachment0
		constraint.Attachment1 = attachment1
		constraint.IsKinematic = true
		constraint.Parent = part1
	end

	local controller: AnimationController = Instance.new("AnimationController")
	controller.Name = "AnimationController"
	Instance.new("Animator").Parent = controller
	controller.Parent = model

	return model
end

--[[
    An Animation for every state Tread plays, named for its state
--]]

function Rig.animations(): { [string]: Animation }
	local animations: { [string]: Animation } = {}
	for state: string, id: string in ANIMATIONS do
		local animation: Animation = Instance.new("Animation")
		animation.Name = state
		animation.AnimationId = id
		animations[state] = animation
	end

	return animations
end

--[[
    Puts a slot's look on a rig: each worn piece tints the parts it covers
    with its item's color, a piece worn over another showing where both
    cover a part, and the first-person copy leaves the head's pieces off

    @ outfit | the slot-table fields, each an item id or nil for nothing worn
--]]

function Rig.dress(rig: Model, outfit: Tread.Outfit, copy: boolean)
	for _, slot: string in ORDER do
		local item: number? = outfit[slot]
		local hidden: boolean = copy and OFF_COPY[slot] == true
		if item == nil or hidden then
			continue
		end

		local color: Color3 = tint(item)
		for _, name: string in COVERS[slot] do
			local part = rig:FindFirstChild(name) :: BasePart
			part.Color = color
		end
	end
end

--[[
    Takes a look off a rig before it goes back to the pool, every body part
    back to the bare body's color
--]]

function Rig.undress(rig: Model)
	for name: string in PARTS do
		if name ~= ROOT then
			local part = rig:FindFirstChild(name) :: BasePart
			part.Color = SKIN
		end
	end
end

--[[
    Puts the held item a slot's held-item fields name in the rig's right
    hand, a block welded to it and tinted by its skin, or by the item when
    it has none, in place of what the hand held. Nil, or fields naming no
    item, clear the hand

    @ held | the held-item fields, the item and its skin each an id or nil
--]]

function Rig.hold(rig: Model, held: Tread.Held?)
	local carried: Instance? = rig:FindFirstChild(HELD)
	if carried then
		carried:Destroy()
	end

	if held == nil then
		return
	end

	local item: number? = held.item
	if item == nil then
		return
	end

	local skin: number? = held.skin
	local hand = rig:FindFirstChild(HAND) :: BasePart

	local piece: Part = Instance.new("Part")
	piece.Name = HELD
	piece.Size = HELD_SIZE
	piece.Color = tint(skin or item)
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.CastShadow = true
	piece.CFrame = hand.CFrame * GRIP

	local weld: Weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = piece
	weld.C0 = GRIP
	weld.Parent = piece

	piece.Parent = rig
end

return Rig
