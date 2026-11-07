--[[
    A held item is one block welded to the rig's right hand, tinted by its
    skin over the item, that collides with nothing; a new item takes its
    place, and nil, or fields naming no item, clear the hand
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local RIG: string = "dev/Client/Rig.luau"
local HELD: string = "Held"
local HAND: string = "RightHand"
local ITEM: number = 21
local OTHER: number = 22
local SKIN: number = 23

-- Every held block on a rig
local function blocks(rig: any): { any }
	local found: { any } = {}
	for _, item: any in rig:GetChildren() do
		if item.Name == HELD then
			table.insert(found, item)
		end
	end

	return found
end

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local Rig: any = place.load(RIG)

	local rig: any = Rig.template()
	Rig.hold(rig, { item = ITEM })

	local held: { any } = blocks(rig)
	if #held ~= 1 then
		return false, `Holding an item put {#held} blocks on the rig, not 1`
	end

	local block: any = held[1]
	local weld: any = block:FindFirstChildOfClass("Weld")
	if not weld or weld.Part0 ~= rig:FindFirstChild(HAND) or weld.Part1 ~= block then
		return false, `The held block is welded to {weld and weld.Part0}, not the right hand`
	elseif block.CanCollide or block.CanQuery or block.CanTouch or not block.Massless then
		return false, "The held block collides, is queried or touched, or weighs something"
	end

	local itemColor: any = block.Color

	-- Another item takes the hand's place, in its own color
	Rig.hold(rig, { item = OTHER })
	held = blocks(rig)
	if #held ~= 1 or held[1].Color == itemColor then
		return false, `A second item left {#held} blocks, or showed the first's color`
	end

	-- A skin tints the item, the same as that id's own color
	Rig.hold(rig, { item = ITEM, skin = SKIN })
	local skinned: any = blocks(rig)[1].Color
	Rig.hold(rig, { item = SKIN })
	if skinned == itemColor or skinned ~= blocks(rig)[1].Color then
		return false, "A skinned item did not show its skin's color"
	end

	-- Nil, and held-item fields naming no item, clear the hand
	Rig.hold(rig, nil)
	if #blocks(rig) ~= 0 then
		return false, "Holding nil left a block in the hand"
	end

	Rig.hold(rig, { item = ITEM })
	Rig.hold(rig, { skin = SKIN })
	if #blocks(rig) ~= 0 then
		return false, "Fields naming no item left a block in the hand"
	end

	return true, nil
end
