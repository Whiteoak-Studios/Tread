--[[
    The doorway and window check refuses to start beside another run's
    bots, in a place with no test content, and when a configured marker
    folder is missing, each before it builds anything
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local REVEALS: string = "dev/Server/Reveals.luau"

-- Each refusal's fleet, whether the place holds its test content, and the words its reason carries
type Case = { entries: { any }, content: boolean, says: string }

local CASES: { Case } = {
	{ entries = { {} }, content = true, says = "bots are still on the server" },
	{ entries = {}, content = false, says = "TestContent is missing" },
	{ entries = {}, content = true, says = "Workspace.TestContent.CityBlock.Markers" },
}

return function (): (boolean, string | nil)
	for _, case: Case in CASES do
		local loaded: Harness.Loaded = Harness.load()
		local dataModel: any = loaded.game
		local server: any = dataModel:GetService("ServerScriptService").Server

		-- Test content with no city block, so its marker folder is the one missing
		if case.content then
			local content: any = roblox.Instance.new("Folder")
			content.Name = "TestContent"
			content.Parent = dataModel:GetService("Workspace")
		end

		local made: boolean = false

		-- Stand-ins for the dev game and its fleet, which Reveals requires where the check starts
		local fakeGame: any = {
			get = function (): (any, any, any)
				return {}, { collision = { include = {} } }, { antiEsp = { include = {} } }
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

		local files: { [any]: string } = { [server.Reveals] = REVEALS }
		local results: { [any]: any } = { [server.Game] = fakeGame, [server.Bots.Fleet] = fakeFleet }
		local Reveals: any = Kit.loader(dataModel, files, results, loaded.require)(server.Reveals)

		local ran: boolean, passed: any, reason: any = pcall(Reveals.openings, nil)
		if not ran then
			return false, `The check threw where it should refuse with "{case.says}": {passed}`
		elseif passed ~= false or type(reason) ~= "string" or not reason:find(case.says, 1, true) then
			return false, `The check gave {passed} with "{reason}", not a refusal saying "{case.says}"`
		elseif made then
			return false, `The check refusing with "{case.says}" built a bot first`
		end
	end

	return true, nil
end
