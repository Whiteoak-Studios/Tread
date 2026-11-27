--[[
    The dev game's rig: the place's own R15 model at ReplicatedStorage.DevRig,
    its joints, one of Roblox's own R15 animations per state, and the hooks
    that tint a slot's look and put its held item in its hand
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local TEMPLATE: string = "DevRig" -- The model's name in ReplicatedStorage, where the place holds it from the start
local HAND: string = "RightHand" -- The part a held item is welded to
local HELD: string = "Held" -- The held item's part, which hold replaces
local GOLDEN: number = 0.618033988749895 -- The golden ratio's fraction, which spreads each item's hue round the wheel
local SATURATION: number = 0.65 -- Each item's tint
local BRIGHTNESS: number = 0.85
local HELD_SIZE: Vector3 = Vector3.new(0.4, 0.5, 1.8) -- The held item's block, studs, its length along the hand's facing
local GRIP: CFrame = CFrame.new(0, -0.15, -0.6) -- The held item's place in the hand's space, reaching ahead of it

-- The 15 R15 joints, each an AnimationConstraint in the template named for its joint
local JOINTS: { string } = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

-- Roblox's own R15 animations, which any experience may load, by the state Tread plays each for. The dev game has no
-- clips of its own, so a state Roblox has none for plays the nearest: crouching, the crouch slide and the downed body
-- stand, the crawl walks, a landing plays the idle and the mantle climbs
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
	slide = "rbxassetid://507766388",
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

local Rig = {
	joints = {} :: { [string]: string }, -- Each logical joint's name in the template, which names every joint for it
}

for _, name: string in JOINTS do
	Rig.joints[name] = name
end

-- An item id's tint, the same on every client for the same id
local function tint(id: number): Color3
	return Color3.fromHSV(id * GOLDEN % 1, SATURATION, BRIGHTNESS)
end

--[[
    The template the pool clones: the place's own R15 model, handed over as
    it stands, since Tread prepares a clone of it and never changes it.
    Errors naming it when the place holds none, or holds something else
--]]

function Rig.template(): Model
	local template = ReplicatedStorage:FindFirstChild(TEMPLATE) :: Model?
	if not template or not template:IsA("Model") then
		error(`The dev client draws every rig from ReplicatedStorage.{TEMPLATE}, which is missing or no Model`)
	end

	return template
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
    back to the color of the template's part of the same name
--]]

function Rig.undress(rig: Model)
	for _, item: Instance in Rig.template():GetChildren() do
		if item:IsA("BasePart") then
			local part = rig:FindFirstChild(item.Name) :: BasePart
			part.Color = item.Color
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
