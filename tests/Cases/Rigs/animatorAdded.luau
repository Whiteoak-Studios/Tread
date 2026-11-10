--[[
    A template whose AnimationController holds no Animator still makes rigs
    that have one, under that one controller, while the game's controller is
    left without
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

local SLOT: number = 4

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local settings: any = Rig.settings({})
	local given: any = settings.rig:FindFirstChildOfClass("AnimationController")
	given:FindFirstChildOfClass("Animator"):Destroy()

	local made: boolean, rigs: any = pcall(Rigs.new, settings, Rig.drawDistance, Rig.collision())
	if not made then
		return false, `Rigs.new refused a template whose AnimationController has no Animator: {rigs}`
	end

	local rig: any = rigs:checkout(SLOT, {})
	local controllers: number = 0
	for _, child: any in rig:GetChildren() do
		if child:IsA("AnimationController") then
			controllers += 1
		end
	end

	local controller: any = rig:FindFirstChildOfClass("AnimationController")
	if controllers ~= 1 or not controller:FindFirstChildOfClass("Animator") then
		return false, `The rig holds {controllers} AnimationControllers, not the one with an Animator`
	elseif given:FindFirstChildOfClass("Animator") then
		return false, "The game's own AnimationController was given an Animator"
	end

	rigs:destroy()

	return true, nil
end
