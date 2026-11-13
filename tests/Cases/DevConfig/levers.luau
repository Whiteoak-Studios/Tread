--[[
    The dev server's settings keep the out-of-view rate and records as
    changes on when Workspace's TreadLeversOff is absent or false, and turn
    both off when it is true, with every other setting the same
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local CONFIG: string = "dev/Server/Config/Tread.luau"
local ATTRIBUTE: string = "TreadLeversOff"
-- The folders the settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}
local OUT_OF_VIEW: { [string]: number } = { rate = 5, cone = 70, radius = 40 } -- Hz, degrees and studs

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local workspace: any = place.game:GetService("Workspace")
	local Config: any = place.tread("Config")

	for _, path: { string } in OCCLUDERS do
		local parent: any = workspace
		for _, name: string in path do
			local folder: any = parent:FindFirstChild(name)
			if not folder then
				folder = roblox.Instance.new("Folder")
				folder.Name = name
				folder.Parent = parent
			end

			parent = folder
		end
	end

	local absent: { [string]: any } = place.load(CONFIG)
	workspace:SetAttribute(ATTRIBUTE, false)
	local unset: { [string]: any } = place.load(CONFIG)
	workspace:SetAttribute(ATTRIBUTE, true)
	local off: { [string]: any } = place.load(CONFIG)

	-- 1) Absent or false, both levers are on at the dev place's values
	if Config.hash(unset) ~= Config.hash(absent) then
		return false, `{ATTRIBUTE} false gave other settings than with it absent`
	elseif absent.tiers.outOfView == nil or Config.hash(absent.tiers.outOfView) ~= Config.hash(OUT_OF_VIEW) then
		return false, `With {ATTRIBUTE} absent, tiers.outOfView is not the dev place's rate, cone and radius`
	elseif Config.hash(absent.relay) ~= Config.hash({ changes = true }) then
		return false, `With {ATTRIBUTE} absent, relay holds more or less than changes set true`
	end

	-- 2) True, both levers are off
	if off.tiers.outOfView ~= nil then
		return false, `With {ATTRIBUTE} true, tiers.outOfView is still given`
	elseif Config.hash(off.relay) ~= Config.hash({ changes = false }) then
		return false, `With {ATTRIBUTE} true, relay holds more or less than changes set false`
	end

	-- 3) True, nothing else changed: the levers put back, the settings hash as they do absent
	local tiers: { [string]: any } = table.clone(off.tiers)
	tiers.outOfView = absent.tiers.outOfView

	local restored: { [string]: any } = table.clone(off)
	restored.tiers = tiers
	restored.relay = absent.relay

	if Config.hash(restored) ~= Config.hash(absent) then
		return false, `With {ATTRIBUTE} true, a setting besides the two levers changed`
	end

	return true, nil
end
