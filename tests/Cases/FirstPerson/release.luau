--[[
    A release shows every part and decal of both rigs again, as the pool
    and a body need them, and the game's settings stay for the next body's
    rigs: hidden arms and a shown world rig both hold across it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local FIRST_PERSON: string = "src/Client/Rigs/FirstPerson.luau"
local HIDDEN: number = 1
local SHOWN: number = 0

return function (): (boolean, string | nil)
	local FirstPerson = Environment.load(FIRST_PERSON)
	local world: Model, copy: Owner.Copy = Owner.rigs()

	local face: any = roblox.Instance.new("Decal")
	face.Parent = Owner.find(copy.rig, "Head")

	local view = FirstPerson.new()
	view:build(world, copy)
	view:show("arms", false)
	view:show("copy", false)

	if Owner.level(copy.rig, "Decal") ~= HIDDEN or Owner.level(copy.rig, "LeftFoot") ~= HIDDEN then
		return false, "The copy wasn't hidden before its release, so the case proves nothing"
	end

	view:release()

	local worldShown: string? = Owner.all(world, SHOWN)
	local copyShown: string? = Owner.all(copy.rig, SHOWN)
	if worldShown or copyShown then
		return false, `A release left a part hidden: {worldShown or copyShown}`
	end

	-- A setting a release keeps no longer touches the rigs it gave back
	view:show("rig", true)
	view:show("copy", true)
	view:show("chest", false)
	if Owner.all(copy.rig, SHOWN) ~= nil or Owner.all(world, SHOWN) ~= nil then
		return false, "A setting changed after the release still reached the old rigs"
	end

	-- The next body: the rig stays shown and the arms and chest hidden
	local nextWorld: Model, nextCopy: Owner.Copy = Owner.rigs()
	view:build(nextWorld, nextCopy)

	local worldSeen: string? = Owner.all(nextWorld, SHOWN)
	local arms: string? = Owner.differs(nextCopy.rig, Owner.arms, HIDDEN)
	local chest: string? = Owner.differs(nextCopy.rig, Owner.chest, HIDDEN)
	local head: string? = Owner.differs(nextCopy.rig, Owner.head, HIDDEN)
	local body: string? = Owner.differs(nextCopy.rig, Owner.body, SHOWN)
	if worldSeen or arms or chest or head or body then
		return false, `The next body's rigs lost the settings: {worldSeen or arms or chest or head or body}`
	end

	return true, nil
end
