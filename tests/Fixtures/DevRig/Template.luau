--[[
    A stand-in for the dev place's ReplicatedStorage.DevRig: a Model with the
    R15 rig's 16 parts under their names, each in a color of its own
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local NAME: string = "DevRig" -- Where the dev client reads it, in ReplicatedStorage
local ROOT: string = "HumanoidRootPart"
local SATURATION: number = 0.3 -- Each part's own color, apart from every tint a look gives
local VALUE: number = 0.5

-- The R15 rig's parts, the root first, each given its own hue in this order
local PARTS: { string } = {
	"HumanoidRootPart",
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

--[[
    Puts the stand-in in a fake game's ReplicatedStorage, where the place
    holds its rig from the start, and gives it back
--]]

return function (dataModel: any): any
	local model: any = roblox.Instance.new("Model")
	model.Name = NAME

	for index: number, name: string in PARTS do
		local part: any = roblox.Instance.new("Part")
		part.Name = name
		part.Color = roblox.Color3.fromHSV(index / #PARTS, SATURATION, VALUE)
		part.Parent = model
	end

	local root: any = model:FindFirstChild(ROOT)
	root.Transparency = 1
	model.PrimaryPart = root
	model.Parent = dataModel:GetService("ReplicatedStorage")

	return model
end
