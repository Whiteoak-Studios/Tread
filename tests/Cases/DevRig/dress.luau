--[[
    A look tints each worn piece's parts in its own item's color, a piece
    worn over another on top, the first-person copy leaves the head's pieces
    off, and undress puts the bare body back
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local RIG: string = "dev/Client/Rig.luau"

-- A look with every slot worn, each by its own item
local OUTFIT: { [string]: number } = { face = 11, head = 12, shirt = 13, torso = 14, pants = 15, leg = 16 }

-- Which item each part shows under that look
local SHOWN: { [string]: string } = {
	Head = "head",
	UpperTorso = "torso",
	LeftUpperArm = "shirt",
	RightLowerArm = "shirt",
	LowerTorso = "pants",
	LeftUpperLeg = "pants",
	RightLowerLeg = "leg",
	LeftFoot = "leg",
}

local BARE: { string } = { "LeftHand", "RightHand" } -- Parts no slot covers

local function color(rig: any, name: string): any
	return rig:FindFirstChild(name).Color
end

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local Rig: any = place.load(RIG)

	local rig: any = Rig.template()
	local skin: any = color(rig, "Head")

	Rig.dress(rig, OUTFIT, false)

	-- Each part shows the piece worn over it, and each piece's color is its item's alone
	local colors: { [string]: any } = {}
	for name: string, slot: string in SHOWN do
		local shown: any = color(rig, name)
		if shown == skin then
			return false, `{name} stayed bare under a look worn everywhere`
		elseif colors[slot] ~= nil and colors[slot] ~= shown then
			return false, `{name} shows {slot}'s item in another color than another part does`
		end

		colors[slot] = shown
	end

	for slot: string, shown: any in colors do
		for other: string, otherColor: any in colors do
			if other ~= slot and otherColor == shown then
				return false, `{slot}'s and {other}'s items show the same color`
			end
		end
	end

	for _, name: string in BARE do
		if color(rig, name) ~= skin then
			return false, `{name}, which no slot covers, was tinted`
		end
	end

	-- The face alone shows on the head, and the same item gives the same color on another rig
	local faced: any = Rig.template()
	Rig.dress(faced, { face = OUTFIT.face }, false)
	local other: any = Rig.template()
	Rig.dress(other, { head = OUTFIT.head }, false)
	if color(faced, "Head") == skin or color(faced, "Head") == colors.head then
		return false, "A face worn alone did not show its own color on the head"
	elseif color(other, "Head") ~= colors.head then
		return false, "The same head item showed another color on another rig"
	end

	-- The first-person copy leaves the head's pieces off and wears the rest
	local copy: any = Rig.template()
	Rig.dress(copy, OUTFIT, true)
	if color(copy, "Head") ~= skin then
		return false, "The first-person copy wore a head piece"
	elseif color(copy, "UpperTorso") ~= colors.torso then
		return false, "The first-person copy left off its torso piece"
	end

	-- Undress puts every part back to the bare body
	Rig.undress(rig)
	for name: string in SHOWN do
		if color(rig, name) ~= skin then
			return false, `{name} kept its tint after undress`
		end
	end

	return true, nil
end
