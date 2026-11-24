--[[
    The dev server's settings turn every frame cap on at the dev place's
    values, with Workspace's TreadLeversOff absent and with it true, since
    the caps are no lever that flag boots off
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local CONFIG: string = "dev/Server/Config/Tread.luau"
local ATTRIBUTE: string = "TreadLeversOff"
local NPC_BUDGET: number = 0.001 -- Seconds a tick's NPC steps may take
local RELAY_BUDGET: number = 0.005 -- Seconds of the server's own script a relay run may take
local UNDER_LOAD: { [string]: number } = { runs = 20, scale = 0.5 } -- Relay runs in a row, and the far band's scale

-- The folders the settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}

local STATES: { any } = { false, true } -- The attribute's values after it starts unset

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

	local loads: { { label: string, settings: { [string]: any } } } = {
		{ label = `{ATTRIBUTE} absent`, settings = place.load(CONFIG) },
	}

	for _, value: any in STATES do
		workspace:SetAttribute(ATTRIBUTE, value)
		table.insert(loads, { label = `{ATTRIBUTE} {value}`, settings = place.load(CONFIG) })
	end

	for _, loaded: { label: string, settings: { [string]: any } } in loads do
		local settings: { [string]: any } = loaded.settings
		local label: string = `With {loaded.label}`

		if settings.antiEsp.whole ~= true then
			return false, `{label}, antiEsp.whole is {settings.antiEsp.whole}, not true`
		elseif settings.npcs.budget ~= NPC_BUDGET then
			return false, `{label}, npcs.budget is {settings.npcs.budget}, not {NPC_BUDGET} s`
		elseif settings.relay.budget ~= RELAY_BUDGET then
			return false, `{label}, relay.budget is {settings.relay.budget}, not {RELAY_BUDGET} s`
		elseif settings.tiers.underLoad == nil or Config.hash(settings.tiers.underLoad) ~= Config.hash(UNDER_LOAD) then
			return false, `{label}, tiers.underLoad is not {UNDER_LOAD.runs} runs at a scale of {UNDER_LOAD.scale}`
		end
	end

	return true, nil
end
