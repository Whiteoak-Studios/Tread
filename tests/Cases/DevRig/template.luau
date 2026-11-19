--[[
    The dev rig is the place's own ReplicatedStorage.DevRig, refused by name
    while the place holds none or holds no Model there, its joints are the 15
    R15 joints by their own names, and each state Tread plays has an animation
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevClient/Harness")
local Template = require("../../Fixtures/DevRig/Template")

local RIG: string = "dev/Client/Rig.luau"
local NAMED: string = "ReplicatedStorage.DevRig" -- What a refusal names
local NAME: string = "DevRig"
local ASSET: string = "^rbxassetid://%d+$" -- An asset id, as each animation's must be

-- The R15 joints, each of which the joints map names for itself
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

-- The states Tread plays an animation for
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

-- Whether a failure names the model the place must hold
local function names(failure: any): boolean
	return tostring(failure):find(NAMED, 1, true) ~= nil
end

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local Rig: any = place.load(RIG)

	-- Refused by name while the place holds no DevRig
	local found: boolean, missing: any = pcall(Rig.template)
	if found or not names(missing) then
		return false, `With no DevRig in the place, the template gave {missing} where it should refuse by name`
	end

	-- And while what it holds under that name is no Model
	local folder: any = roblox.Instance.new("Folder")
	folder.Name = NAME
	folder.Parent = place.game:GetService("ReplicatedStorage")

	local taken: boolean, wrong: any = pcall(Rig.template)
	if taken or not names(wrong) then
		return false, `With a Folder for the DevRig, the template gave {wrong} where it should refuse by name`
	end

	folder:Destroy()

	-- The place's own model, handed over as it stands
	local model: any = Template(place.game)
	if Rig.template() ~= model then
		return false, "The template is not the place's own DevRig"
	end

	local count: number = 0
	for name: string, joint: string in Rig.joints do
		count += 1
		if joint ~= name then
			return false, `The joints map names {joint} for {name}, not itself`
		end
	end

	for _, name: string in JOINTS do
		if Rig.joints[name] ~= name then
			return false, `The joints map leaves out {name}`
		end
	end

	if count ~= #JOINTS then
		return false, `The joints map names {count} joints, not the {#JOINTS} R15 joints`
	end

	local animations: any = Rig.animations()
	for _, state: string in STATES do
		local animation: any = animations[state]
		if not animation or not animation:IsA("Animation") or not animation.AnimationId:match(ASSET) then
			return false, `The animations give {state} no Animation with an asset id`
		end
	end

	return true, nil
end
