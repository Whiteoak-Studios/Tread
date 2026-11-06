--[[
    A pool refuses a template whose leg can't bend, naming why: joints that
    don't chain down the leg, a bone of no length, and a leg that points
    along the rig's facing at rest
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local CFrame: any = roblox.CFrame
local Vector3: any = roblox.Vector3

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

local AHEAD: any = Vector3.new(0, 0, -2) -- Where the bad ankle sits from the hip, straight along the facing

type Trial = { name: string, says: { string }, spoil: (settings: any) -> () }

-- A joint's pivot in the template's world, where its attachment in the part it moves sits
local function pivotOf(settings: any, joint: string): any
	local attachment: any = settings.rig:FindFirstChild(joint, true).Attachment1

	return (attachment.Parent.CFrame * attachment.CFrame).Position
end

-- Moves a joint's pivot to a point in the template's world, both its attachments with it
local function move(settings: any, joint: string, at: any)
	local constraint: any = settings.rig:FindFirstChild(joint, true)
	constraint.Attachment0.CFrame = constraint.Attachment0.Parent.CFrame:ToObjectSpace(CFrame.new(at))
	constraint.Attachment1.CFrame = constraint.Attachment1.Parent.CFrame:ToObjectSpace(CFrame.new(at))
end

local TRIALS: { Trial } = {
	{
		name = "a joints map whose LeftKnee names the right knee",
		says = { "LeftKnee", "hang" },
		spoil = function (settings: any)
			settings.joints = table.clone(settings.joints)
			settings.joints.LeftKnee = "RightKnee"
		end,
	},
	{
		name = "a left knee whose pivot sits on the hip's",
		says = { "LeftHip", "no length" },
		spoil = function (settings: any)
			move(settings, "LeftKnee", pivotOf(settings, "LeftHip"))
		end,
	},
	{
		name = "a left ankle level with the hip and straight ahead of it",
		says = { "LeftAnkle", "facing" },
		spoil = function (settings: any)
			move(settings, "LeftAnkle", pivotOf(settings, "LeftHip") + AHEAD)
		end,
	},
}

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	for _, trial: Trial in TRIALS do
		local settings: any = Rig.settings({})
		trial.spoil(settings)

		local made: boolean, problem: any = pcall(Rigs.new, settings, Rig.drawDistance, Rig.collision())
		if made then
			return false, `Rigs.new took {trial.name}`
		end

		for _, word: string in trial.says do
			if not tostring(problem):find(word, 1, true) then
				return false, `Rigs.new refused {trial.name} without naming {word}: {problem}`
			end
		end
	end

	return true, nil
end
