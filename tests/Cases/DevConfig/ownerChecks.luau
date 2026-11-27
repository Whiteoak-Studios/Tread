--[[
    The dev server's settings turn owner.checks on when Workspace's
    TreadLeversOff is absent or false and off when it is true, and take
    every bot as agreeing beside its round trip either way
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local CONFIG: string = "dev/Server/Config/Tread.luau"
local ATTRIBUTE: string = "TreadLeversOff"
local BOT_RTT: number = 0.1 -- Seconds, the dev place's bot round trip

-- The folders the settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}

-- Each attribute value, the first left unset, and whether the owner's checks are on under it
local CASES: { { value: any, checks: boolean } } = {
	{ value = nil, checks = true },
	{ value = false, checks = true },
	{ value = true, checks = false },
}

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

	for _, case: { value: any, checks: boolean } in CASES do
		workspace:SetAttribute(ATTRIBUTE, case.value)
		local settings: { [string]: any } = place.load(CONFIG)
		local label: string = `With {ATTRIBUTE} {case.value}`

		if Config.hash(settings.owner) ~= Config.hash({ checks = case.checks }) then
			return false, `{label}, owner is not checks set {case.checks}`
		elseif Config.hash(settings.bots) ~= Config.hash({ rtt = BOT_RTT, agree = true }) then
			return false, `{label}, bots is not a {BOT_RTT} s round trip with every bot agreeing`
		end
	end

	return true, nil
end
