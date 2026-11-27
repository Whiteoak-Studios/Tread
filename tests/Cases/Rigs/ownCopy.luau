--[[
    The local player's own checkout takes a second rig from the pool as its
    first-person copy, dressed as the copy, with the world rig hidden on this
    screen and the copy's head out of view. A second own rig is refused
    before any hook, and another slot's checkout makes no copy
--]]

--!strict
local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local OWN: number = 9
local OTHER: number = 3
local HIDDEN: number = 1
local SHOWN: number = 0

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local outfit: { [string]: any } = { shirt = 2 }
	local world: any = rigs:checkout(OWN, outfit, true)

	if #calls ~= 2 or calls[1].hook ~= "dress" or calls[2].hook ~= "dress" then
		return false, `The own checkout made {#calls} hook calls, not two dresses`
	elseif calls[1].rig ~= world or calls[1].copy ~= false or calls[1].outfit ~= outfit then
		return false, "The own checkout didn't dress its world rig first, as a world rig, with the look"
	elseif calls[2].rig == world or calls[2].copy ~= true or calls[2].outfit ~= outfit then
		return false, "The own checkout didn't dress a second rig as the copy, with the look"
	end

	local copy: any = calls[2].rig
	if copy.Parent ~= nil or not copy:FindFirstChild("LeftFoot") then
		return false, "The copy is no clone of the template kept out of Workspace until a pose draws it"
	end

	local hidden: string? = Owner.all(world, HIDDEN)
	if hidden then
		return false, `The own world rig wasn't hidden on this screen: {hidden}`
	end

	local head: string? = Owner.differs(copy, Owner.head, HIDDEN)
	local body: string? = Owner.differs(copy, Owner.body, SHOWN)
	local arms: string? = Owner.differs(copy, Owner.arms, SHOWN)
	if head or body or arms then
		return false, `The copy showed its head or hid its body: {head or body or arms}`
	end

	-- A second rig as the local player's own is refused before any hook runs
	table.clear(calls)
	local twice: boolean, problem: any = pcall(rigs.checkout, rigs, OTHER, outfit, true)
	if twice then
		return false, "A second own checkout was taken"
	elseif not tostring(problem):find("already the local player's own", 1, true) then
		return false, `A second own checkout failed with the wrong reason: {problem}`
	elseif #calls ~= 0 then
		return false, `The refused own checkout made {#calls} hook calls`
	end

	-- Another slot's rig takes no copy and isn't hidden
	local other: any = rigs:checkout(OTHER, outfit)
	if #calls ~= 1 or calls[1].rig ~= other or calls[1].copy ~= false then
		return false, `Another slot's checkout made {#calls} hook calls, not one world dress`
	elseif Owner.all(other, SHOWN) ~= nil then
		return false, "Another slot's rig was hidden on this screen"
	end

	rigs:destroy()

	return true, nil
end
