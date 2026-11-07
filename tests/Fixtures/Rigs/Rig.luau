--[[
    The rig pool's fixture: a lean R15 template of plain parts with kinematic
    joints, Frontier Zero's detail, draw and body values, and settings whose
    hooks write down every call they get
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Collision = require(script.Parent.Parent.Step.Collision)
local Rigs = require(ReplicatedStorage.Packages.Tread.Client.Rigs)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local ROOT: string = "HumanoidRootPart"
local ATTACHMENT: string = "RigAttachment" -- A joint's attachments are named for it and this, as an R15 rig's are

type Animations = Rigs.Animations
type Casts = State.Collision
type Bodies = Rigs.Bodies
type Held = Rigs.Held
type Joints = Rigs.Joints
type Lod = Rigs.Lod
type Outfit = Rigs.Outfit
type Settings = Rigs.Settings

-- One hook call the settings wrote down
export type Call = {
	hook: string, -- dress, undress or hold
	rig: Model,
	outfit: Outfit?,
	copy: boolean?,
	held: Held?,
}

type Piece = { size: Vector3, center: Vector3 }
type Joint = { part0: string, part1: string, pivot: Vector3 }

-- Each part's size and center, studs, standing with its feet on the origin
local PARTS: { [string]: Piece } = {
	HumanoidRootPart = { size = Vector3.new(2, 2, 1), center = Vector3.new(0, 3, 0) },
	LowerTorso = { size = Vector3.new(2, 0.4, 1), center = Vector3.new(0, 2.9, 0) },
	UpperTorso = { size = Vector3.new(2, 1.6, 1), center = Vector3.new(0, 3.9, 0) },
	Head = { size = Vector3.new(1.2, 1.2, 1.2), center = Vector3.new(0, 5.3, 0) },
	LeftUpperArm = { size = Vector3.new(1, 1.2, 1), center = Vector3.new(-1.5, 4.1, 0) },
	LeftLowerArm = { size = Vector3.new(1, 1, 1), center = Vector3.new(-1.5, 3, 0) },
	LeftHand = { size = Vector3.new(1, 0.3, 1), center = Vector3.new(-1.5, 2.35, 0) },
	RightUpperArm = { size = Vector3.new(1, 1.2, 1), center = Vector3.new(1.5, 4.1, 0) },
	RightLowerArm = { size = Vector3.new(1, 1, 1), center = Vector3.new(1.5, 3, 0) },
	RightHand = { size = Vector3.new(1, 0.3, 1), center = Vector3.new(1.5, 2.35, 0) },
	LeftUpperLeg = { size = Vector3.new(1, 1.2, 1), center = Vector3.new(-0.5, 2.1, 0) },
	LeftLowerLeg = { size = Vector3.new(1, 1.2, 1), center = Vector3.new(-0.5, 0.9, 0) },
	LeftFoot = { size = Vector3.new(1, 0.3, 1), center = Vector3.new(-0.5, 0.15, 0) },
	RightUpperLeg = { size = Vector3.new(1, 1.2, 1), center = Vector3.new(0.5, 2.1, 0) },
	RightLowerLeg = { size = Vector3.new(1, 1.2, 1), center = Vector3.new(0.5, 0.9, 0) },
	RightFoot = { size = Vector3.new(1, 0.3, 1), center = Vector3.new(0.5, 0.15, 0) },
}

-- Each R15 joint's two parts and the pivot both its attachments sit at
local JOINTS: { [string]: Joint } = {
	Root = { part0 = "HumanoidRootPart", part1 = "LowerTorso", pivot = Vector3.new(0, 2.9, 0) },
	Waist = { part0 = "LowerTorso", part1 = "UpperTorso", pivot = Vector3.new(0, 3.1, 0) },
	Neck = { part0 = "UpperTorso", part1 = "Head", pivot = Vector3.new(0, 4.7, 0) },
	LeftShoulder = { part0 = "UpperTorso", part1 = "LeftUpperArm", pivot = Vector3.new(-1.5, 4.5, 0) },
	LeftElbow = { part0 = "LeftUpperArm", part1 = "LeftLowerArm", pivot = Vector3.new(-1.5, 3.5, 0) },
	LeftWrist = { part0 = "LeftLowerArm", part1 = "LeftHand", pivot = Vector3.new(-1.5, 2.5, 0) },
	RightShoulder = { part0 = "UpperTorso", part1 = "RightUpperArm", pivot = Vector3.new(1.5, 4.5, 0) },
	RightElbow = { part0 = "RightUpperArm", part1 = "RightLowerArm", pivot = Vector3.new(1.5, 3.5, 0) },
	RightWrist = { part0 = "RightLowerArm", part1 = "RightHand", pivot = Vector3.new(1.5, 2.5, 0) },
	LeftHip = { part0 = "LowerTorso", part1 = "LeftUpperLeg", pivot = Vector3.new(-0.5, 2.7, 0) },
	LeftKnee = { part0 = "LeftUpperLeg", part1 = "LeftLowerLeg", pivot = Vector3.new(-0.5, 1.5, 0) },
	LeftAnkle = { part0 = "LeftLowerLeg", part1 = "LeftFoot", pivot = Vector3.new(-0.5, 0.3, 0) },
	RightHip = { part0 = "LowerTorso", part1 = "RightUpperLeg", pivot = Vector3.new(0.5, 2.7, 0) },
	RightKnee = { part0 = "RightUpperLeg", part1 = "RightLowerLeg", pivot = Vector3.new(0.5, 1.5, 0) },
	RightAnkle = { part0 = "RightLowerLeg", part1 = "RightFoot", pivot = Vector3.new(0.5, 0.3, 0) },
}

-- The states the game's animations map gives one Animation each
local STATES: { string } = {
	"idle",
	"walk",
	"sprint",
	"crouchIdle",
	"crouchWalk",
	"jump",
	"fall",
	"land",
	"swimIdle",
	"swim",
	"climb",
	"mantle",
	"downed",
	"crawl",
}

local Rig = {
	-- Its own joint names under their logical names, as mode A's map gives them
	joints = {} :: Joints,

	-- Frontier Zero's lod and desktop draw distance
	lod = { full = 128, footIk = 128, aim = 600 } :: Lod,
	drawDistance = 1000,

	-- Frontier Zero's bodies values; its joint limits are tuned in its Studio test, so these are the fixture's own
	bodies = {
		radius = 250,
		late = 6,
		minSeconds = 1,
		maxSeconds = 6,
		check = 0.5,
		settleSpeed = 0.33,
		pushSpeed = 6,
		pushUpBias = 0.5,
		jointLimits = {
			Waist = { tilt = 30, twistLower = -30, twistUpper = 30 },
			Neck = { tilt = 45, twistLower = -45, twistUpper = 45 },
			LeftShoulder = { tilt = 110, twistLower = -85, twistUpper = 85 },
			LeftElbow = { tilt = 5, twistLower = -120, twistUpper = -5 },
			LeftWrist = { tilt = 45, twistLower = -45, twistUpper = 45 },
			RightShoulder = { tilt = 110, twistLower = -85, twistUpper = 85 },
			RightElbow = { tilt = 5, twistLower = -120, twistUpper = -5 },
			RightWrist = { tilt = 45, twistLower = -45, twistUpper = 45 },
			LeftHip = { tilt = 60, twistLower = -30, twistUpper = 30 },
			LeftKnee = { tilt = 5, twistLower = -120, twistUpper = -5 },
			LeftAnkle = { tilt = 30, twistLower = -15, twistUpper = 15 },
			RightHip = { tilt = 60, twistLower = -30, twistUpper = 30 },
			RightKnee = { tilt = 5, twistLower = -120, twistUpper = -5 },
			RightAnkle = { tilt = 30, twistLower = -15, twistUpper = 15 },
		},
	} :: Bodies,
}

for name: string in JOINTS do
	Rig.joints[name] = name
end

--[[
    The template: the 16 parts under their R15 names, only the root
    anchored and the root its PrimaryPart, each joint a kinematic
    AnimationConstraint under its Part1, and an AnimationController with an
    Animator
--]]

function Rig.template(): Model
	local model: Model = Instance.new("Model")
	model.Name = "RigTemplate"

	local parts: { [string]: Part } = {}
	for name: string, piece: Piece in PARTS do
		local part: Part = Instance.new("Part")
		part.Name = name
		part.Size = piece.size
		part.CFrame = CFrame.new(piece.center)
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
    An Animation for every state, named for it, with no AnimationId: the
    Lune cases never load one
--]]

function Rig.animations(): Animations
	local animations: Animations = {}
	for _, state: string in STATES do
		local animation: Animation = Instance.new("Animation")
		animation.Name = state
		animations[state] = animation
	end

	return animations
end

--[[
    The pool's settings over a fresh template, with hooks that write each
    call into calls, and the animations given or the fixture's own
--]]

function Rig.settings(calls: { Call }, animations: Animations?): Settings
	return {
		rig = Rig.template(),
		joints = Rig.joints,
		animations = animations or Rig.animations(),
		lod = Rig.lod,
		bodies = Rig.bodies,

		dress = function (rig: Model, outfit: Outfit, copy: boolean)
			table.insert(calls, { hook = "dress", rig = rig, outfit = outfit, copy = copy })
		end,

		undress = function (rig: Model)
			table.insert(calls, { hook = "undress", rig = rig })
		end,

		hold = function (rig: Model, held: Held?)
			table.insert(calls, { hook = "hold", rig = rig, held = held })
		end,
	}
end

--[[
    The step's casts over no geometry, so a planted foot finds nothing
--]]

function Rig.collision(): Casts
	return Collision({})
end

return Rig
