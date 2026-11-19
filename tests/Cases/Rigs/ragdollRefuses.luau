--[[
    A ragdoll refuses a dying slot with no rig, a body slot that is no slot
    and one that already holds a rig, and the dying rig stays where it was
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

	local unknown: boolean = pcall(rigs.ragdoll, rigs, 1, 2, nil)
	if unknown then
		return false, "A ragdoll of slot 1, with no rig checked out, was taken"
	end

	local dying: any = rigs:checkout(1, {})
	rigs:checkout(2, {})

	local taken: boolean, problem: any = pcall(rigs.ragdoll, rigs, 1, 2, nil)
	if taken then
		return false, "A ragdoll into slot 2, which holds a rig, was taken"
	elseif not tostring(problem):find("already has a rig", 1, true) then
		return false, `A ragdoll into a held slot failed with the wrong reason: {problem}`
	end

	local bounds: { any } = { 4096, -1, 0.5 }
	for _, body: any in bounds do
		local took: boolean = pcall(rigs.ragdoll, rigs, 1, body, nil)
		if took then
			return false, `A ragdoll into {body} was taken as a body's slot`
		end
	end

	table.clear(calls)
	rigs:release(1)
	if #calls ~= 1 or calls[1].rig ~= dying then
		return false, "Slot 1 lost its rig to a refused ragdoll"
	elseif dying.Parent ~= nil or #dying:GetChildren() == 0 then
		return false, "The refused ragdolls left slot 1's rig out of the pool"
	end

	rigs:destroy()

	return true, nil
end
