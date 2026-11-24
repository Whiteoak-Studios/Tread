--[[
    The dev place draws other players from one delay: the dev client's
    interpolation.delay, the dev server's rewind.delayMin and the delay a
    bot's Move reports are each the 0.10 s floor
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local CLIENT: string = "dev/Client/Config.luau"
local SERVER: string = "dev/Server/Config/Tread.luau"
local BOTS: string = "dev/Server/Bots/Config.luau"
local DELAY: number = 0.10 -- Seconds, the floor other players are drawn behind

-- The folders the server settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local workspace: any = place.game:GetService("Workspace")

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

	local delays: { [string]: number } = {
		["The dev client's interpolation.delay"] = place.load(CLIENT).interpolation.delay,
		["The dev server's rewind.delayMin"] = place.load(SERVER).rewind.delayMin,
		["The delay a bot's Move reports"] = place.load(BOTS).delay,
	}

	for name: string, delay: number in delays do
		if delay ~= DELAY then
			return false, `{name} is {delay} s, not the {DELAY} s floor`
		end
	end

	return true, nil
end
