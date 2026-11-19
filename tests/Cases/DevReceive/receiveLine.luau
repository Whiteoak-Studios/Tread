--[[
    The versus run's receive line gives the data and physics rates and their
    sum taken sample by sample with known answers, by nearest rank, marks an
    empty window and a failed one unmeasured, and watches Versus's attribute
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RECEIVE: string = "dev/Client/Receive.luau"
local CONFIG: string = "dev/Client/Config.luau"
local PLAYER: string = "Mike"
local FAILURE: string = "it passed its 90 s deadline with ClientReceive still set"

-- Each sample's two rates, out of order, so a sum taken after either list sorts pairs the wrong samples
local DATA: { number } = { 8, 1, 6, 3, 10, 2, 7, 4, 9, 5 }
local PHYSICS: { number } = { 3, 2, 1, 0, 0, 0, 2, 1, 0, 1 }

-- The case's own receive values, so its answers stand whatever the dev client tunes
local RECEIVE_VALUES: { [string]: any } = {
	attribute = "ClientReceive",
	interval = 1,
	longest = 90,
	percentiles = { 0.5, 0.95, 0.99 },
}

-- The line those samples give, a figure at a time: the sum's p95 is 11, not the 13 that data's and physics' p95 make
local DATA_LINE: string = "Mike: Stats.DataReceiveKbps p50 5 p95 10 p99 10 n 10"
local PHYSICS_LINE: string = "Stats.PhysicsReceiveKbps p50 1 p95 3 p99 3 n 10"
local SUM_LINE: string = "Stats.DataReceiveKbps + Stats.PhysicsReceiveKbps p50 6 p95 11 p99 11 n 10"
local NO_FRAMES: string = "no frame was sampled" -- The frame figures of a window whose render step never ran
local LINE: string = `{DATA_LINE}; {PHYSICS_LINE}; {SUM_LINE}; {NO_FRAMES}`
local EMPTY: string = "Mike: no receive rate was sampled, so the window measured nothing"

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A window as the receive keeps one, holding copies of the samples given and no frame
local function windowOf(data: { number }, physics: { number }): { [string]: any }
	return {
		label = "case",
		data = table.clone(data),
		physics = table.clone(physics),
		frames = {},
		heap = {},
		cpu = {},
		gpu = {},
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- The dev client's folder, with its Config and the receive, and the dev scope's client module standing in
	local folder: any = create("Folder", "Client", replicated)
	local files: { [any]: string } = {
		[create("ModuleScript", "Config", folder)] = CONFIG,
		[create("ModuleScript", "Receive", folder)] = RECEIVE,
	}

	local results: { [any]: any } = { [replicated.Shared.Network.Client] = { clientCost = { fire = function () end } } }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)

	-- 1) The client watches the attribute the server's scenario sets, read before the case's own values replace it
	local watched: string = load(folder.Config).receive.attribute
	local set: string = loaded.require(server.Config.Versus).attribute
	if watched ~= set then
		return false, `The dev client watches {watched}, while the Versus scenario sets {set}`
	end

	load(folder.Config).receive = RECEIVE_VALUES
	local Receive: any = load(folder.Receive)

	-- 2) Known answers, the sum taken sample by sample
	local measured: boolean, line: string = Receive.summary(windowOf(DATA, PHYSICS), PLAYER, nil)
	if not measured or line ~= LINE then
		return false, `A window of known samples gave {measured} with "{line}", not true with "{LINE}"`
	end

	-- 3) A window with no sample is unmeasured
	local sampled: boolean, empty: string = Receive.summary(windowOf({}, {}), PLAYER, nil)
	if sampled or empty ~= EMPTY then
		return false, `A window with no sample gave {sampled} with "{empty}", not false with "{EMPTY}"`
	end

	-- 4) A window its deadline ended is unmeasured, its line kept with the failure after it
	local failed: string = `{LINE}, then {FAILURE}`
	local whole: boolean, ended: string = Receive.summary(windowOf(DATA, PHYSICS), PLAYER, FAILURE)
	if whole or ended ~= failed then
		return false, `A window its deadline ended gave {whole} with "{ended}", not false with "{failed}"`
	end

	return true, nil
end
