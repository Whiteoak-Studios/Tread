--[[
    A hook that throws for the first-person copy is warned and stops none of
    the world rig's work: its checkout still hands back the world rig hidden
    on this screen, and its looks, held items and release still reach it
--]]

--!strict
local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local OWN: number = 9
local HIDDEN: number = 1
local SHOWN: number = 0

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	-- A dress hook that throws for the copy alone
	local calls: { any } = {}
	local settings: any = Rig.settings(calls)
	local dress: (Model, any, boolean) -> () = settings.dress
	settings.dress = function (rig: Model, outfit: any, copy: boolean)
		dress(rig, outfit, copy)
		if copy then
			error("This dress hook throws for the copy on purpose, to show the world rig carries on")
		end
	end

	local rigs = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	local checked: boolean, world: any = pcall(rigs.checkout, rigs, OWN, {}, true)
	if not checked then
		return false, `The own checkout threw when its copy's dress did: {world}`
	end

	local hidden: string? = Owner.all(world, HIDDEN)
	if hidden then
		return false, `With no copy the own world rig wasn't hidden: {hidden}`
	end

	-- Its look, held item and pose still reach the world rig, with no copy to reach
	table.clear(calls)
	local dressed: boolean, dressProblem: any = pcall(rigs.dress, rigs, OWN, { shirt = 1 })
	local held: boolean, holdProblem: any = pcall(rigs.hold, rigs, OWN, { item = 2 })
	if not dressed or not held then
		return false, `The own slot's look or held item threw with no copy: {dressProblem or holdProblem}`
	elseif #calls ~= 3 then
		return false, `The own slot's look and held item made {#calls} hook calls, not the world rig's three`
	end

	for _, call: any in calls do
		if call.rig ~= world then
			return false, `The own slot's {call.hook} reached a rig that is no world rig of its`
		end
	end

	-- Past the draw distance, so the pose loads no animation, which Lune can't
	local far: number = Rig.drawDistance + 1
	local state: any = Environment.load("src/Step/State.luau").new()
	local posed: boolean, poseProblem: any = pcall(rigs.pose, rigs, OWN, state, far, 0)
	if not posed then
		return false, `The own slot's pose threw with no copy: {poseProblem}`
	end

	rigs:release(OWN)
	local shown: string? = Owner.all(world, SHOWN)
	if shown then
		return false, `The released world rig stayed hidden: {shown}`
	end

	rigs:destroy()

	return true, nil
end
