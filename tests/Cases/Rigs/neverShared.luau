--[[
    Every slot checked out at once holds a rig of its own, and a rig given
    back goes to one new slot only
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local held: { [any]: number } = {}
	for slot: number = 0, 2 do
		local rig: any = rigs:checkout(slot, {})
		if held[rig] ~= nil then
			return false, `Slot {slot} got the rig slot {held[rig]} already holds`
		end
		held[rig] = slot
	end

	local fourth: any = rigs:checkout(9, {})
	held[fourth] = 9
	rigs:release(1)

	local reused: any = rigs:checkout(10, {})
	local fresh: any = rigs:checkout(11, {})

	if held[reused] ~= 1 then
		return false, "Slot 10 did not get the rig slot 1 gave back"
	elseif held[fresh] ~= nil then
		return false, `Slot 11 got the rig slot {held[fresh]} holds or held, where only one was given back`
	end

	rigs:destroy()

	return true, nil
end
