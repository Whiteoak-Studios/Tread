--[[
    The dev server's settings leave relay.split out when the attribute the
    bot panel's config names is absent, false or no boolean, and set it true
    beside the rest of the relay table when it is true, nothing else changed
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local CONFIG: string = "dev/Server/Config/Tread.luau"
local PANEL_CONFIG: string = "dev/Server/Config/BotPanel.luau"
local RELAY_BUDGET: number = 0.005 -- Seconds, the dev place's relay budget

-- The folders the settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}

local OFF: { any } = { false, "true", 1 } -- Values the attribute leaves the split out at

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local workspace: any = place.game:GetService("Workspace")
	local Config: any = place.tread("Config")
	local attribute: string = place.load(PANEL_CONFIG).splitAttribute

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

	-- 1) Absent, false or no boolean, the relay table holds records as changes and the budget alone
	local absent: { [string]: any } = place.load(CONFIG)
	if Config.hash(absent.relay) ~= Config.hash({ changes = true, budget = RELAY_BUDGET }) then
		return false, `With {attribute} absent, relay holds more or less than changes set true and the budget`
	end

	for _, value: any in OFF do
		workspace:SetAttribute(attribute, value)
		if Config.hash(place.load(CONFIG)) ~= Config.hash(absent) then
			return false, `With {attribute} {value}, the settings differ from those with it absent`
		end
	end

	-- 2) True, the split beside records as changes and the budget, and every other setting as with it absent
	workspace:SetAttribute(attribute, true)
	local on: { [string]: any } = place.load(CONFIG)
	local restored: { [string]: any } = table.clone(on)
	restored.relay = absent.relay

	if Config.hash(on.relay) ~= Config.hash({ changes = true, budget = RELAY_BUDGET, split = true }) then
		return false, `With {attribute} true, relay is not records as changes and the budget with the split on`
	elseif Config.hash(restored) ~= Config.hash(absent) then
		return false, `With {attribute} true, a setting besides relay changed`
	end

	return true, nil
end
