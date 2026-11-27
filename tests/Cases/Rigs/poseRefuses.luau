--[[
    A pose refuses a slot with no rig checked out, and a rig posed past the
    draw distance stays out of Workspace with nothing loaded
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	local rigs = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())
	local state = State.new()

	local posed: boolean, problem: any = pcall(rigs.pose, rigs, 2, state, 0, 0)
	if posed then
		return false, "A pose of slot 2, with no rig checked out, was taken"
	elseif not tostring(problem):find("with a rig checked out", 1, true) then
		return false, `A pose of an unknown slot failed with the wrong reason: {problem}`
	end

	local rig: any = rigs:checkout(2, {})
	local far: number = Rig.drawDistance + 1
	local farPosed: boolean, farProblem: any = pcall(rigs.pose, rigs, 2, state, far, 0)
	if not farPosed then
		return false, `A pose past the draw distance failed: {farProblem}`
	elseif rig.Parent ~= nil then
		return false, `A rig posed past the draw distance sits in {rig.Parent:GetFullName()}`
	end

	rigs:release(2)
	local released: boolean = pcall(rigs.pose, rigs, 2, state, far, 0)
	if released then
		return false, "A pose of a released slot was taken"
	end

	rigs:destroy()

	return true, nil
end
