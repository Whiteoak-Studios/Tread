--[[
    A step benchmark half's areas move onto the plaza's first spawn point
    wherever the real player stands, the same load's otherwise onto the
    player, and a load that follows no one's nowhere, fixed or not
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"
local AREA_MIN: any = roblox.Vector3.new(3830, 0.5, -75) -- The dev place's plaza spawn area, as the grid's case has it
local AREA_MAX: any = roblox.Vector3.new(3930, 0.5, -15)
local GROUND: any = roblox.Vector3.new(3835, 0.5, -70) -- The first of its 10 by 6 cells' centers, on the floor
local STANDING: any = roblox.Vector3.new(3690, 12.5, -274) -- Where the real player stands, off the plaza
local TOLERANCE: number = 1e-6 -- Studs

-- A target's stand-in, which the run reads only for its player and its root
local function target(player: any, root: any): any
	return {
		player = player,
		getState = function (_: any): any
			return { root = root }
		end,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server

	local testContent: any = roblox.Instance.new("Folder")
	testContent.Name = "TestContent"
	testContent.Parent = dataModel:GetService("Workspace")

	local cityBlock: any = roblox.Instance.new("Folder")
	cityBlock.Name = "CityBlock"
	cityBlock:SetAttribute("SpawnAreaMin", AREA_MIN)
	cityBlock:SetAttribute("SpawnAreaMax", AREA_MAX)
	cityBlock.Parent = testContent

	-- A bot's character, whose player is no Instance, an NPC's with none, then the real player's
	local targets: { any } = {
		target({ Name = "Bot1" }, roblox.Vector3.new(1, 0, 1)),
		target(nil, roblox.Vector3.new(2, 0, 2)),
		target(roblox.Instance.new("Folder"), STANDING),
	}

	local tread: any = {
		getAll = function (_: any): { any }
			return targets
		end,
	}

	local stand: any = {
		get = function (): any
			return tread
		end,
	}

	local results: { [any]: any } = { [server.Game] = stand, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)
	local Config: any = loaded.require(server.Bots.Config)
	local Spawns: any = loaded.require(server.Spawns)

	-- 1) Before the spawn grid is laid there is no fixed ground to stand on
	if pcall(Spawns.first) then
		return false, "The first spawn point's ground was given before the grid was laid"
	end

	Spawns.start()
	if (Spawns.first() - GROUND).Magnitude > TOLERANCE then
		return false, `The first spawn point's ground is {Spawns.first()}, not {GROUND}`
	end

	-- 2) Each step load's viewer point lands on that ground in a half, and on the real player otherwise
	for _, load: any in Config.step.loads do
		local scenario: any = Config.scenarios[load.scenario]
		local fixed: any = scenario.viewer + Run.offset(scenario, true)
		local following: any = scenario.viewer + Run.offset(scenario, false)

		if (fixed - GROUND).Magnitude > TOLERANCE then
			return false, `{load.scenario}'s half stood its viewer point at {fixed}, not {GROUND}`
		elseif (following - STANDING).Magnitude > TOLERANCE then
			return false, `{load.scenario} outside a half stood its viewer point at {following}, not {STANDING}`
		end
	end

	-- 3) A load that follows no one stays where its config has it, fixed or not
	local city: any = Config.scenarios.S3
	if Run.offset(city, true).Magnitude > 0 or Run.offset(city, false).Magnitude > 0 then
		return false, "S3, which follows no one, moved its areas"
	end

	-- 4) With no real player in, a half still stands on the ground, and a following load stays put
	table.remove(targets)
	local fight: any = Config.scenarios.S4
	if (fight.viewer + Run.offset(fight, true) - GROUND).Magnitude > TOLERANCE then
		return false, "With no real player in, S4's half left the plaza's spawn"
	elseif Run.offset(fight, false).Magnitude > 0 then
		return false, "With no real player in, S4 outside a half moved its areas"
	end

	return true, nil
end
