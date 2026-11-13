--[[
    Each load builds a fresh environment, so a module's state from one load,
    Promise's and Volt's mock among them, never reaches the next
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"

return function (): (boolean, string | nil)
	local first: any = Environment.load(GLOBALS)
	local counter: any = first.require(first.script.Parent.Counter)
	counter.count += 1

	local second: any = Environment.load(GLOBALS)
	local again: any = second.require(second.script.Parent.Counter)

	if again == counter or again.count ~= 0 then
		return false, `The second load's Counter is the first's, its count {again.count}`
	end

	if first.game == second.game then
		return false, "Two loads share one fake game"
	end

	local firstPackages: any = first.game:GetService("ReplicatedStorage").Packages
	local secondPackages: any = second.game:GetService("ReplicatedStorage").Packages

	if first.require(firstPackages.Promise) == second.require(secondPackages.Promise) then
		return false, "Two loads share one Promise library"
	end

	if first.require(firstPackages.Volt).mock == second.require(secondPackages.Volt).mock then
		return false, "Two loads share one Volt mock"
	end

	return true, nil
end
