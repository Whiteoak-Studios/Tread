--[[
    AntiEsp.moved makes every pair of a slot due at once: as each viewer's
    target, a hidden or visible player and a sleeper with no walk of the
    viewer's or wait for its rate, and as the viewer, every pair it holds
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	harness.wall = Harness.solid

	local ownSlot: number, viewer: any = harness:player("Viewer", vector.zero)
	local otherSlot: number, other: any = harness:player("Other", vector.create(60, 0, 0))
	local hidden: number = harness:body("Player", vector.create(0, 0, -50))
	local sleeper: number = harness:body("Sleeper", vector.create(0, 0, 50))

	local function ask()
		for _, target: number in { hidden, sleeper, otherSlot } do
			AntiEsp.isHidden(viewer, target)
		end

		AntiEsp.isHidden(other, hidden)
		AntiEsp.isHidden(other, ownSlot)
	end

	ask()
	harness:slice(0)

	local eye: number = harness.shared.step.eyeStanding
	local hiddenHead: vector = vector.create(0, eye, -50)

	-- Before any recheck is due, a move of the hidden player makes its pair due for both viewers alone
	ask()
	AntiEsp.moved(hidden)
	harness:slice(0.01)

	if harness:endingAt(hiddenHead) ~= 2 then
		return false, `The moved player's pairs cast {harness:endingAt(hiddenHead)} head rays, not one each viewer's`
	elseif #harness.rays ~= 10 then
		return false, `Pairs other than the moved player's were tested: {#harness.rays} rays`
	end

	-- The sleeper's pair, with the viewer standing still and 0.02 s after its last test
	ask()
	AntiEsp.moved(sleeper)
	harness:slice(0.02)

	if #harness.rays ~= 3 then
		return false, `The moved sleeper's pair cast {#harness.rays} rays, not its 3`
	end

	-- The viewer itself: its three pairs, and the other viewer's pair with it as the target
	ask()
	AntiEsp.moved(ownSlot)
	harness:slice(0.03)

	local ownHead: vector = vector.create(0, eye, 0)
	if #harness.rays ~= 5 + 3 + 5 + 5 then
		return false, `The moved viewer's pairs cast {#harness.rays} rays, not its three pairs' and the other's`
	elseif harness:endingAt(ownHead) ~= 1 then
		return false, "The other viewer's pair with the moved viewer was not tested"
	end

	-- A slot no pair holds moves nothing
	ask()
	AntiEsp.moved(harness:body("Player", vector.create(0, 0, -90)))
	harness:slice(0.04)

	if #harness.rays ~= 0 then
		return false, `A move of a slot in no pair tested {#harness.rays} rays`
	end

	return true, nil
end
