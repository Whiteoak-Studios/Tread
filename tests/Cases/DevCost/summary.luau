--[[
    G5's cost gives a window's line with known answers, by nearest rank,
    refuses a window that timed no frame, and watches the attribute the
    dev server's ClientCost scenario opens each window with
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local PLAYER: string = "Mike"
local INPUT: string = "touch"
local FRAMES: number = 100
local STEP: number = 0.125 -- Milliseconds between the remote samples, so each percentile prints exactly
local RATES: number = 20 -- Frame rates of 41 to 60 a second, whose p10 by nearest rank is the second lowest
local LOWEST_RATE: number = 41
local DRAWN: { number } = { 150, 149, 148, 149, 149 } -- Rigs drawn at each frame, whose p50 by nearest rank is 149

-- The case's own cost values, so its answers stand whatever the dev client tunes
local COST_VALUES: { [string]: any } = {
	attribute = "ClientCost",
	longest = 180,
	limit = 2,
	percentiles = { 0.5, 0.95, 0.99 },
	fps = 0.1,
	drawn = 0.5,
}

-- The line those samples give, a clause at a time
local COUNTS: string = "Mike on touch: 100 frames, FPS p10 42.0, rigs drawn p50 149"
local REMOTE: string = "remote ms p50/p95/p99 6.250/11.875/12.375 against 2 ms"
local LINE: string = `{COUNTS}, {REMOTE}`

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A window as the cost keeps one, holding the samples given
local function windowOf(remote: { number }, rates: { number }, drawn: { number }): { [string]: any }
	return {
		label = "case",
		remote = remote,
		rates = rates,
		drawn = drawn,
		pending = 0,
		predicted = 0,
		restore = function () end,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- The dev client's folder, with its Config and the cost, and the dev scope's client module standing in
	local folder: any = create("Folder", "Client", replicated)
	local files: { [any]: string } = {
		[create("ModuleScript", "Config", folder)] = CONFIG,
		[create("ModuleScript", "Cost", folder)] = COST,
	}

	local results: { [any]: any } = { [replicated.Shared.Network.Client] = { clientCost = { fire = function () end } } }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)

	-- 1) The client watches the attribute the server's scenario sets, read before the case's own values replace it
	local watched: string = load(folder.Config).cost.attribute
	local set: string = loaded.require(server.Config.ClientCost).attribute
	if watched ~= set then
		return false, `The dev client watches {watched}, while the ClientCost scenario sets {set}`
	end

	load(folder.Config).cost = COST_VALUES
	local Cost: any = load(folder.Cost)

	-- 2) Known answers: the samples in no order, each spread read by nearest rank
	local remote: { number } = {}
	for index: number = FRAMES, 1, -1 do
		table.insert(remote, index * STEP)
	end

	local rates: { number } = {}
	for index: number = RATES - 1, 0, -1 do
		table.insert(rates, LOWEST_RATE + index)
	end

	local measured: boolean, line: string = Cost.summary(windowOf(remote, rates, DRAWN), PLAYER, INPUT)
	if not measured or line ~= LINE then
		return false, `A window of known samples gave {measured} with "{line}", not true with "{LINE}"`
	end

	-- 3) A window that timed no frame is refused
	local timed: boolean, refusal: string = Cost.summary(windowOf({}, {}, {}), PLAYER, INPUT)
	if timed or not refusal:find(`{PLAYER} on {INPUT}: refused`, 1, true) then
		return false, `A window with no frame gave {timed} with "{refusal}", not a refusal`
	end

	return true, nil
end
