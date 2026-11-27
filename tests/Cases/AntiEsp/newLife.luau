--[[
    A new life in a slot starts its pair afresh, hidden and due at once,
    whatever the last life's pair held, and a player falling asleep keeps
    its pair's verdict while it moves to the sleepers' schedule
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	local Slots: any = Harness.Slots

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))

	AntiEsp.isHidden(viewer, target)
	harness:slice(0)
	if AntiEsp.isHidden(viewer, target) then
		return false, "The pair with every ray open was hidden"
	end

	harness:reborn(target)
	if not AntiEsp.isHidden(viewer, target) then
		return false, "The slot's new life kept the last life's visible verdict"
	end

	harness:slice(0.01)
	if #harness.rays == 0 then
		return false, "The new life's pair was not due at once"
	elseif AntiEsp.isHidden(viewer, target) then
		return false, "The new life with every ray open stayed hidden"
	end

	-- Asleep in the same life: still visible, tested at once on the sleepers' rays
	Slots.setEntry(target, { kind = "Sleeper", rig = "A" })
	harness.wall = Harness.solid

	if AntiEsp.isHidden(viewer, target) then
		return false, "The player falling asleep in sight lost its visible verdict"
	end

	harness:slice(0.02)
	if #harness.rays ~= 3 then
		return false, `The new sleeper's pair cast {#harness.rays} rays, not the sleepers' 3`
	end

	return true, nil
end
