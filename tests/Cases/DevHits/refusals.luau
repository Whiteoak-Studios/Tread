--[[
    G7's run refuses to start beside another run's bots, with no real
    player holding a character to shoot from, and in a place with no test
    content to lay its floor in, each before it makes anything
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local HITS: string = "dev/Server/Hits.luau"

-- Each refusal's fleet, whether its player holds a character, and the words its reason carries
type Case = { entries: { any }, character: boolean, says: string }

local CASES: { Case } = {
	{ entries = { {} }, character = true, says = "bots are still on the server" },
	{ entries = {}, character = false, says = "no real player has a character" },
	{ entries = {}, character = true, says = "TestContent is missing" },
}

-- Lune's Players has no GetPlayers, so it answers with the Players parented to it, as the engine's does
roblox.implementMethod("Players", "GetPlayers", function (players: any): { any }
	local found: { any } = {}
	for _, child: any in players:GetChildren() do
		if child:IsA("Player") then
			table.insert(found, child)
		end
	end

	return found
end)

return function (): (boolean, string | nil)
	for _, case: Case in CASES do
		local loaded: Harness.Loaded = Harness.load()
		local dataModel: any = loaded.game
		local server: any = dataModel:GetService("ServerScriptService").Server

		local player: any = roblox.Instance.new("Player")
		player.Name = "Shooter"
		player.Parent = dataModel:GetService("Players")

		local character: any = { teleport = function () end }
		local made: boolean = false

		-- Stand-ins for the dev game and its fleet, which Hits requires where its run starts
		local fakeGame: any = {
			get = function (): (any, any, any)
				return {
					getAll = function (): { any }
						return {}
					end,
				}, {}, {}
			end,

			characterOf = function (_: any): any
				return case.character and character or nil
			end,
		}

		local fakeFleet: any = {
			start = function () end,

			entries = function (): { any }
				return case.entries
			end,

			add = function (_: any): any
				made = true
				return {}
			end,
		}

		local files: { [any]: string } = { [server.Hits] = HITS }
		local results: { [any]: any } = { [server.Game] = fakeGame, [server.Bots.Fleet] = fakeFleet }
		local Hits: any = Kit.loader(dataModel, files, results, loaded.require)(server.Hits)

		local ran: boolean, passed: any, reason: any = pcall(Hits.run, {})
		if not ran then
			return false, `The run threw where it should refuse with "{case.says}": {passed}`
		elseif passed ~= false or type(reason) ~= "string" or not reason:find(case.says, 1, true) then
			return false, `The run gave {passed} with "{reason}", not a refusal saying "{case.says}"`
		elseif made then
			return false, `The run refusing with "{case.says}" built a bot first`
		end
	end

	return true, nil
end
