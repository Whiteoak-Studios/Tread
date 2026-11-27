--[[
    A stock R15 rig as Roblox's Rig Builder makes it, over the rig fixture's
    template: MeshParts on the same joints, none anchored, with a Humanoid
    holding the Animator, the Animate script, sockets and no-collision pairs
--]]

--!strict
local Rig = require(script.Parent.Rig)

local ROOT_JOINT: string = "Root" -- The one joint a stock rig gives no ball socket
local SOCKET: string = "BallSocket" -- A joint's ball socket is named for it and this, as a stock rig's are
local HIP_HEIGHT: number = 2 -- The stock Humanoid's

-- The parts a stock rig collides with; the rest collide with nothing
local COLLIDING: { [string]: boolean } = {
	HumanoidRootPart = true,
	LowerTorso = true,
	UpperTorso = true,
	Head = true,
}

-- The pairs kept apart beyond each socketed joint's own two parts, which make a stock rig's 19 in all
local APART: { { string } } = {
	{ "LeftUpperLeg", "RightUpperLeg" },
	{ "LeftUpperArm", "LowerTorso" },
	{ "RightUpperArm", "LowerTorso" },
	{ "LeftUpperArm", "Head" },
	{ "RightUpperArm", "Head" },
}

-- The six scale values a stock Humanoid holds
local SCALES: { string } = {
	"BodyDepthScale",
	"BodyHeightScale",
	"BodyProportionScale",
	"BodyTypeScale",
	"BodyWidthScale",
	"HeadScale",
}

-- Some of the Animate script's StringValues, each holding its Animation
local CLIPS: { string } = { "idle", "walk", "run", "jump", "fall", "climb", "swim" }

local Stock = {}

-- A new instance of a class under a name and a parent
local function add(className: string, name: string, parent: Instance): any
	local item: any = Instance.new(className :: any)
	item.Name = name
	item.Parent = parent

	return item
end

-- A no-collision pair between two of a model's parts
local function apart(part0: Instance, part1: Instance)
	local pair: NoCollisionConstraint = Instance.new("NoCollisionConstraint")
	pair.Name = `{part0.Name}{part1.Name}NoCollision`
	pair.Part0 = part0 :: BasePart
	pair.Part1 = part1 :: BasePart
	pair.Parent = part1
end

--[[
    The stock rig: its root a Part and every other part a MeshPart, none
    anchored, the root, torso and head colliding and every part queried and
    touched, beside what Roblox's rig carries apart from its joints
--]]

function Stock.template(): Model
	local model: Model = Rig.template()
	model.Name = "StockRig"
	local root: BasePart = model.PrimaryPart :: BasePart

	-- 1) The Animator sits under a Humanoid, and there is no AnimationController
	local controller: Instance = model:FindFirstChildOfClass("AnimationController") :: Instance
	controller:Destroy()

	local humanoid: Humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = HIP_HEIGHT
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.Parent = model

	add("Animator", "Animator", humanoid)
	add("HumanoidDescription", "HumanoidDescription", humanoid)
	add("Status", "Status", humanoid)
	for _, scale: string in SCALES do
		add("NumberValue", scale, humanoid)
	end

	local animate: Instance = add("LocalScript", "Animate", model)
	for _, clip: string in CLIPS do
		add("Animation", clip, add("StringValue", clip, animate))
	end
	add("BindableFunction", "PlayEmote", animate)
	add("BodyColors", "Body Colors", model)

	-- 2) Every part but the root becomes a MeshPart holding what the part held
	for _, part: Instance in model:GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			local mesh: MeshPart = Instance.new("MeshPart")
			mesh.Name = part.Name
			mesh.Size = part.Size
			mesh.CFrame = part.CFrame

			for _, child: Instance in part:GetChildren() do
				child.Parent = mesh
			end

			add("WrapTarget", `{part.Name}WrapTarget`, mesh)
			add("Vector3Value", "OriginalSize", mesh)
			mesh.Parent = model
			part:Destroy()
		end
	end
	add("FaceControls", "FaceControls", model:FindFirstChild("Head") :: Instance)

	-- 3) Nothing anchored, the root, torso and head colliding, and every part queried and touched
	for _, part: Instance in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = COLLIDING[part.Name] == true
			part.CanQuery = true
			part.CanTouch = true
		end
	end

	-- 4) Each joint's attachments keep their first place, and every joint but Root has a ball socket on them
	for name: string in Rig.joints do
		local joint: AnimationConstraint = model:FindFirstChild(name, true) :: AnimationConstraint
		local attachment0: Attachment = joint.Attachment0 :: Attachment
		local attachment1: Attachment = joint.Attachment1 :: Attachment
		add("Vector3Value", "OriginalPosition", attachment0)
		add("Vector3Value", "OriginalPosition", attachment1)

		if name ~= ROOT_JOINT then
			local socket: BallSocketConstraint = Instance.new("BallSocketConstraint")
			socket.Name = `{name}{SOCKET}`
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.Parent = attachment1.Parent

			apart(attachment0.Parent :: Instance, attachment1.Parent :: Instance)
		end
	end

	for _, pair: { string } in APART do
		apart(model:FindFirstChild(pair[1]) :: Instance, model:FindFirstChild(pair[2]) :: Instance)
	end

	return model
end

return Stock
