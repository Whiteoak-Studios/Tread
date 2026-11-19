--[[
    The exact test casts from the eye to the hull's center and then its
    eight corners pulled inside: a hull every ray to is blocked is hidden,
    one open corner shows it, and an open center costs one ray
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local Vector3: any = roblox.Vector3
local CFrame: any = roblox.CFrame

local EYE: any = Vector3.new(0, 4, 0)
local BOX: { [string]: any } = { cframe = CFrame.new(3, 2.5, -10), size = Vector3.new(2.78, 5, 2.78) }
local POINTS: number = 9 -- The center and eight corners
local CLOSE: number = 1e-4

-- A stand-in for anti-ESP's occlusion that blocks every ray but those ending at the point given, and keeps each ray
local function blockedBut(open: any?, rays: { vector }): (origin: vector, direction: vector) -> boolean
	return function (_: vector, direction: vector): boolean
		table.insert(rays, direction)

		if open == nil then
			return true
		end

		local toOpen: any = open - EYE
		return vector.magnitude(direction - vector.create(toOpen.X, toOpen.Y, toOpen.Z)) > CLOSE
	end
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Reveals: any = loaded.require(server.Reveals)
	local inset: number = loaded.require(server.Config.Reveals).inset

	-- The corner every axis is positive at, the last one tested
	local half: any = BOX.size / 2 - Vector3.new(inset, inset, inset)
	local corner: any = BOX.cframe * half

	-- 1) Fully covered: hidden, after every ray
	local covered: { vector } = {}
	local visible: boolean, rays: number = Reveals.visible(EYE, BOX, blockedBut(nil, covered), inset)
	if visible or rays ~= POINTS or #covered ~= POINTS then
		return false, `A covered hull read visible {visible} after {rays} rays, {#covered} cast`
	end

	-- 2) One corner showing, the last one tested: visible, and its ray ended inset inside the hull's corner
	local showing: { vector } = {}
	visible, rays = Reveals.visible(EYE, BOX, blockedBut(corner, showing), inset)
	if not visible or rays ~= POINTS then
		return false, `A hull with one corner showing read visible {visible} after {rays} rays`
	end

	local reached: vector = showing[#showing]
	local outer: any = BOX.cframe * (BOX.size / 2) - EYE
	if vector.magnitude(reached - vector.create(outer.X, outer.Y, outer.Z)) < inset then
		return false, "The corner's ray ended on the hull's own corner, not inside it"
	end

	-- 3) A visible center: one ray
	local open: { vector } = {}
	visible, rays = Reveals.visible(EYE, BOX, blockedBut(BOX.cframe.Position, open), inset)
	if not visible or rays ~= 1 or #open ~= 1 then
		return false, `A hull with its center open read visible {visible} after {rays} rays, {#open} cast`
	end

	return true, nil
end
