--[[
    G5's cost counts track switches, track loads and clones on stand-in
    module tables, each in the delta of the frame after the call that made
    it, since a frame's own work lengthens the next frame's delta
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local NATIVE_LOOP: string = "dev/Client/NativeLoop.luau"
local INTERPRETED_LOOP: string = "dev/Client/InterpretedLoop.luau"
local DT: number = 0.125 -- Seconds of each frame's delta
local KILOBYTES: number = 64 -- What the stand-in heap reads

-- The tracks each frame draws its two rigs with, a new rig loading its tracks at its first draw: both start
-- playing in the first, the second rig switches in the second, the first rig in the third, and the fourth draws none
local PLANS: { { string } } = {
	{ "walk", "idle" },
	{ "walk", "run" },
	{ "idle", "run" },
	{},
}

-- The case's own cost values, so its answers stand whatever the dev client tunes
local COST_VALUES: { [string]: any } = {
	attribute = "ClientCost",
	longest = 180,
	limit = 2,
	percentiles = { 0.5, 0.95, 0.99 },
	fps = 0.1,
	drawn = 0.5,
	spike = 2,
	hitch = 33.3,
	blocks = 0.95,
	switches = { 0.5, 0.99 },
	split = true,
	loop = { samples = 100, passes = 4, bytes = 1024 },
}

-- What the line says of them
local FIRSTS: string = "first draws 2 track loads, at most 2 a frame, and 2 clones, at most 2 a frame"
local SWITCHED: string = "track switches a frame p50/p99/max 1/2/2"

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")

	-- The dev client's folder, with its Config, the cost and its loops, and the dev scope's client module standing in
	local folder: any = create("Folder", "Client", replicated)
	local files: { [any]: string } = {
		[create("ModuleScript", "Config", folder)] = CONFIG,
		[create("ModuleScript", "Cost", folder)] = COST,
		[create("ModuleScript", "NativeLoop", folder)] = NATIVE_LOOP,
		[create("ModuleScript", "InterpretedLoop", folder)] = INTERPRETED_LOOP,
	}

	local results: { [any]: any } = { [replicated.Shared.Network.Client] = { clientCost = { fire = function () end } } }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)
	load(folder.Config).cost = COST_VALUES
	local Cost: any = load(folder.Cost)

	-- Each stand-in calls the others through their tables, as Tread's rig pool does
	local animate: any = {}
	animate.pose = function (tracks: any, state: any, _: boolean, _: number?)
		tracks.playing = state.track
	end

	local rigs: any = {}
	rigs._animate = function (_: any, entry: any): any
		entry.animated = { playing = nil }

		return entry.animated
	end

	rigs._build = function (_: any): any
		return { animated = nil }
	end

	rigs._draw = function (self: any, entry: any, state: any, _: number, _: number, _: number)
		local tracks: any = entry.animated or rigs._animate(self, entry)
		animate.pose(tracks, state, true, 1)
	end

	rigs._layer = function (_: any) end

	local handle: { [string]: any } = {}
	local entries: { any } = {}
	local drawing: { string } = {}

	local client: any = {}
	client._frame = function (self: any, _: number)
		for index: number, track: string in drawing do
			rigs._draw(self, entries[index], { track = track }, 0, 0, 0)
		end
	end

	local modules: { [string]: any } = {
		client = client,
		predict = { frame = function (_: number) end },
		rigs = rigs,
		interpolate = {
			receive = function (_: buffer) end,
			pose = function (_: number, _: any): (boolean, number, number, number)
				return true, 0, 0, 0
			end,
		},
		animate = animate,
	}

	local window: any = Cost.open("case", modules, os.clock, function (): number
		return #entries
	end, function (): number
		return KILOBYTES
	end)

	-- 1) Two clones before the first frame, as a reveal's checkouts make them, then the frames as planned
	table.insert(entries, rigs._build(handle))
	table.insert(entries, rigs._build(handle))

	for _, plan: { string } in PLANS do
		drawing = plan
		client._frame(handle, DT)
	end

	window.restore()

	local loads: string = table.concat(window.loads, ",")
	local clones: string = table.concat(window.clones, ",")
	local switches: string = table.concat(window.switches, ",")
	if loads ~= "0,2,0,0" or clones ~= "2,0,0,0" or switches ~= "0,2,1,1" then
		return false, `The frames counted loads {loads}, clones {clones} and switches {switches}`
	end

	-- 2) The line totals the first draws with the most in one frame, and spreads the switches
	local _, line: string = Cost.summary(window, "Mike", "mouse")
	if not line:find(FIRSTS, 1, true) then
		return false, `The line "{line}" holds no "{FIRSTS}"`
	elseif not line:find(SWITCHED, 1, true) then
		return false, `The line "{line}" holds no "{SWITCHED}"`
	end

	return true, nil
end
