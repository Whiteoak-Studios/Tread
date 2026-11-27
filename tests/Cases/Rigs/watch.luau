--[[
    The spectated target's world rig takes the local player's own "rig"
    setting on this screen, hidden until the game shows it, its attire
    from a new look included, as the local player's own world rig does; it
    shows again when watched no more or released, and a slot with no rig
    can't be watched
--]]

--!strict
local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

local TARGET: number = 5
local OWN: number = 9
local EMPTY: number = 12
local HIDDEN: number = 1
local SHOWN: number = 0

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	-- A dress hook that welds a hat to the head when the look names one, as a game's hook welds attire
	local settings: any = Rig.settings({})
	settings.dress = function (rig: Model, outfit: { [string]: any }, _: boolean)
		if outfit.hat then
			Owner.wear(rig, "Hat", Owner.find(rig, "Head"), "WeldConstraint")
		end
	end

	local rigs = Rigs.new(settings, Rig.drawDistance, Rig.collision())
	local target: any = rigs:checkout(TARGET, {})
	local own: any = rigs:checkout(OWN, {}, true)

	-- 1) Watched, the target's world rig hides with the local player's own, and both show together
	rigs:watch(TARGET)
	local shown: string? = Owner.all(target, HIDDEN)
	if shown then
		return false, `The watched target's rig showed on this screen: {shown}`
	end

	rigs:show("rig", true)
	if Owner.all(target, SHOWN) or Owner.all(own, SHOWN) then
		return false, "Showing the rig left the watched target's or the own world rig hidden"
	end

	rigs:show("rig", false)
	if Owner.all(target, HIDDEN) then
		return false, "Hiding the rig again left the watched target's rig showing"
	end

	-- 2) A new look's attire on the watched rig hides with it
	rigs:dress(TARGET, { hat = true })
	if Owner.level(target, "Hat") ~= HIDDEN then
		return false, "The watched target's new hat showed on this screen"
	end

	-- 3) Watched no more, it shows again; released while watched, it shows and the pool lets it go
	rigs:watch(nil)
	if Owner.all(target, SHOWN) then
		return false, "The target's rig stayed hidden once it was watched no more"
	end

	rigs:watch(TARGET)
	rigs:release(TARGET)
	local left: string? = Owner.all(target, SHOWN)
	if left then
		return false, `The released target's rig went back to the pool hidden: {left}`
	end

	-- The pool no longer counts the released slot as watched, so a new look on another slot changes nothing hidden
	local reused: any = rigs:checkout(TARGET + 1, {})
	rigs:dress(TARGET + 1, { hat = true })
	if reused ~= target or Owner.all(reused, SHOWN) then
		return false, "A rig released while watched came back from the pool hidden"
	end

	if pcall(rigs.watch, rigs, EMPTY) then
		return false, `Slot {EMPTY}, which has no rig, was watched`
	end

	rigs:destroy()

	return true, nil
end
