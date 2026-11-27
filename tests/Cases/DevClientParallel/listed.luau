--[[
    The client parallel probes' run is a scenario the panel lists outside
    Run all, saved under its start and its name, and the dev client watches
    the two attributes the scenario opens its windows on
--]]

--!strict
local Kit = require("../../Fixtures/Exploits/Kit")
local Mount = require("../../Fixtures/DevClientParallel/Mount")

local NAME: string = "ClientParallel"
local LIVE: string = "dev/Server/Live.luau"
local SCENARIO: string = "dev/Server/Scenarios/ClientParallel.luau"
local MINUTES: number = 3 -- About how long it runs
local STARTED: number = 1763900000 -- The os.time() a stand-in run started at

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount()
	local loaded: any = mounted.loaded
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)

	-- 1) Listed for the panel at about 3 minutes, out of Run all's queue, and a scenario's function once loaded over
	-- stand-ins for the bot harness and the game
	local listed: any = nil
	for _, run: any in LiveRuns.runs do
		if run.name == NAME then
			listed = run
		end
	end

	local stands: { [any]: any } = {
		[server.Bots.ClientLines] = {},
		[server.Bots.Fleet] = {},
		[server.Bots.Run] = {},
		[server.Game] = {},
	}

	local scenario: any =
		Kit.loader(dataModel, { [server.Scenarios[NAME]] = SCENARIO }, stands, loaded.require)(server.Scenarios[NAME])

	if listed == nil or listed.minutes ~= MINUTES then
		return false, `The panel lists {NAME} as {listed and listed.minutes} minutes, not {MINUTES}`
	elseif table.find(LiveRuns.queue, NAME) then
		return false, `Run all's queue runs {NAME}`
	elseif type(scenario) ~= "function" then
		return false, `{NAME}'s module gives a {type(scenario)}, not a scenario's function`
	end

	-- 2) Saved as a single run under its start and its name, through a game whose DataStoreService keeps each key
	local written: { string } = {}
	local opened: { string } = {}
	local store: any = {
		GetDataStore = function (_: any, name: string): any
			table.insert(opened, name)

			return {
				SetAsync = function (_: any, key: string, _: any)
					table.insert(written, key)
				end,
			}
		end,
	}

	local place: any = {
		GetService = function (_: any, name: string): any
			if name == "DataStoreService" then
				return store
			end

			return dataModel:GetService(name)
		end,
	}

	local results: { [any]: any } = {
		[shared.Network.Server] = {},
		[server.BotPanel] = {},
		[server.Runner] = {},
	}

	local Live: any = Kit.loader(place, { [server.Live] = LIVE }, results, loaded.require)(server.Live)
	Live.saveRun(STARTED, NAME, `{NAME}'s report`)

	if table.concat(written, ",") ~= `{STARTED}-{NAME}` or table.concat(opened, ",") ~= "LiveRuns" then
		return false, `{NAME}'s report was written under {table.concat(written, ",")} in {table.concat(opened, ",")}`
	end

	-- 3) The dev client watches each window's attribute the server's scenario sets
	local set: any = loaded.require(server.Config.ClientParallel).attributes
	local watched: any = mounted.config.parallel.attributes
	for _, probe: string in { "cores", "bend" } do
		if watched[probe] ~= set[probe] then
			return false, `The dev client watches {watched[probe]} for {probe}, while the scenario sets {set[probe]}`
		end
	end

	return true, nil
end
