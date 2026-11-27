--[[
    G5's cost says what its slow frames held on stand-in module tables: a
    relay block, a heap drop, a first draw and more track switches than the
    median, each counted in the delta of the frame it lengthened
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local NATIVE_LOOP: string = "dev/Client/NativeLoop.luau"
local INTERPRETED_LOOP: string = "dev/Client/InterpretedLoop.luau"
local MILLISECONDS: number = 1000 -- A second's

-- Ten frames' deltas in milliseconds around a 10 ms median: the 5th, 6th, 8th and 10th past twice it, and the 6th
-- and 8th past 33.3 ms too
local DELTAS: { number } = { 10, 10, 10, 10, 25, 40, 10, 50, 10, 25 }

-- What the heap reads as each frame begins, dropping at the 5th and the 8th
local HEAP: { number } = { 100, 110, 120, 130, 90, 95, 105, 80, 85, 86 }

-- What runs, by the frame it runs before or inside: a block before the 3rd and the 6th, three track switches inside
-- the 4th and one inside the 5th, a track load inside the 7th and a clone before the 10th. A call inside a frame lies
-- in the next one's delta, so the 5th and 6th hold the switches, the 8th the load
local BLOCKS_BEFORE: { [number]: boolean } = { [3] = true, [6] = true }
local SWITCHES_INSIDE: { [number]: number } = { [4] = 3, [5] = 1 }
local LOAD_INSIDE: number = 7
local CLONE_BEFORE: number = 10

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

-- What the line says the slow frames held, after its unchanged hitch counts
local HITCHES: string = "hitches 4 (40.00%) past 2x the median frame, 2 (20.00%) past 33.3 ms"
local PAST_MEDIAN: string =
	"of the 4 past 2x the median frame, 1 had a relay block, 2 followed a heap drop, 2 had a first draw and 2 more than 0 track switches"
local PAST_HITCH: string =
	"of the 2 past 33.3 ms, 1 had a relay block, 1 followed a heap drop, 1 had a first draw and 1 more than 0 track switches"

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

	local animate: any = {}
	animate.pose = function (tracks: any, state: any, _: boolean, _: number?)
		tracks.playing = state.track
	end

	local rigs: any = {}
	rigs._animate = function (_: any, _: any): any
		return { playing = nil }
	end

	rigs._build = function (_: any): any
		return {}
	end

	rigs._draw = function (_: any, _: any, _: any, _: number, _: number, _: number) end
	rigs._layer = function (_: any) end

	local interpolate: any = {}
	interpolate.receive = function (_: buffer) end
	interpolate.pose = function (_: number, _: any): (boolean, number, number, number)
		return true, 0, 0, 0
	end

	-- Each frame runs what the plan puts inside it, through the tables as Tread's client does
	local frameIndex: number = 0
	local client: any = {}
	client._frame = function (self: any, _: number)
		for _ = 1, SWITCHES_INSIDE[frameIndex] or 0 do
			animate.pose({ playing = nil }, { track = "walk" }, true, 1)
		end

		if frameIndex == LOAD_INSIDE then
			rigs._animate(self, {})
		end
	end

	local modules: { [string]: any } = {
		client = client,
		predict = { frame = function (_: number) end },
		rigs = rigs,
		interpolate = interpolate,
		animate = animate,
	}

	local window: any = Cost.open("case", modules, os.clock, function (): number
		return 0
	end, function (): number
		return HEAP[frameIndex]
	end)

	local handle: { [string]: any } = {}
	for index: number, delta: number in DELTAS do
		if BLOCKS_BEFORE[index] then
			interpolate.receive(buffer.create(1))
		end

		if index == CLONE_BEFORE then
			rigs._build(handle)
		end

		frameIndex = index
		client._frame(handle, delta / MILLISECONDS)
	end

	window.restore()

	-- 1) The heap is read as each frame begins
	if table.concat(window.heap, ",") ~= table.concat(HEAP, ",") then
		return false, `The frames read the heap at {table.concat(window.heap, ",")}, not {table.concat(HEAP, ",")}`
	end

	-- 2) Each set of slow frames counts what lay in their deltas
	local _, line: string = Cost.summary(window, "Mike", "mouse")
	if not line:find(HITCHES, 1, true) then
		return false, `The line "{line}" holds no "{HITCHES}"`
	elseif not line:find(PAST_MEDIAN, 1, true) then
		return false, `The line "{line}" holds no "{PAST_MEDIAN}"`
	elseif not line:find(PAST_HITCH, 1, true) then
		return false, `The line "{line}" holds no "{PAST_HITCH}"`
	end

	return true, nil
end
