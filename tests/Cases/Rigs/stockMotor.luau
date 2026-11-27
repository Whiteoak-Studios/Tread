--[[
    A pool refuses a stock R15 rig with one joint a Motor6D, as an older
    rig's are, naming the joint
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STOCK: string = "tests/Fixtures/Rigs/Stock.luau"

local JOINT: string = "LeftKnee"

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)
	local Stock = Environment.load(STOCK)

	local settings: any = Rig.settings({})
	settings.rig = Stock.template()

	-- The joint becomes a Motor6D between the same two parts at the same pivot
	local joint: any = settings.rig:FindFirstChild(JOINT, true)
	local motor: any = roblox.Instance.new("Motor6D")
	motor.Name = JOINT
	motor.Part0 = joint.Attachment0.Parent
	motor.Part1 = joint.Attachment1.Parent
	motor.C0 = joint.Attachment0.CFrame
	motor.C1 = joint.Attachment1.CFrame
	motor.Parent = joint.Parent
	joint:Destroy()

	local made: boolean, problem: any = pcall(Rigs.new, settings, Rig.drawDistance, Rig.collision())
	if made then
		return false, `Rigs.new took a stock rig whose {JOINT} is a Motor6D`
	elseif not tostring(problem):find(JOINT, 1, true) then
		return false, `Rigs.new refused a stock rig whose {JOINT} is a Motor6D without naming it: {problem}`
	end

	return true, nil
end
