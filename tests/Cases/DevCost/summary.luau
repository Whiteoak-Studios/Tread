--[[
    G5's cost gives a window's line with known answers, by nearest rank, its
    frame times and hitches among them, refuses a window that timed no frame,
    and watches the attribute the dev server's ClientCost scenario opens
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local NATIVE_LOOP: string = "dev/Client/NativeLoop.luau"
local INTERPRETED_LOOP: string = "dev/Client/InterpretedLoop.luau"
local PLAYER: string = "Mike"
local INPUT: string = "touch"
local FRAMES: number = 100
local STEP: number = 0.125 -- Milliseconds between the remote samples, so each percentile prints exactly
local RATES: number = 20 -- Frame rates of 41 to 60 a second, whose p10 by nearest rank is the second lowest
local LOWEST_RATE: number = 41
local DRAWN: { number } = { 150, 149, 148, 149, 149 } -- Rigs drawn at each frame, whose p50 by nearest rank is 149

-- Each frame's milliseconds, out of order: 93 at 10, the median, one at exactly twice it, which is no hitch, 4 at 25,
-- then 40 and 50 past the 33.3 ms threshold too
local SLOW_FRAMES: { number } = { 50, 25, 40 }
local STEADY_FRAMES: number = 93
local STEADY_FRAME: number = 10
local LATE_FRAMES: { number } = { 20, 25, 25, 25 }

-- What each frame held, by its place: a step count cycling 1, 2, 3, 4, 0, a relay block every 4th frame from the
-- first, a track switch count cycling 1, 2, 0 with the last frame's at 9, heap drops at the 3rd and 99th frames,
-- a track load at the 2nd and 50th, and clones at the 3rd and 60th
local STEPS_CYCLE: number = 5
local BLOCK_EVERY: number = 4
local SWITCH_CYCLE: number = 3
local LAST_SWITCHES: number = 9
local HEAP: number = 1000 -- Kilobytes before the first frame, the heap growing a kilobyte a frame between its drops
local DROPS: { [number]: number } = { [3] = 900, [99] = 500 }
local LOADS: { [number]: number } = { [2] = 1, [50] = 1 }
local CLONES: { [number]: number } = { [3] = 2, [60] = 1 }

-- Each part's milliseconds by the frame's place: the pose through the 60th frame, the draw on odd frames, the
-- receive on block frames and the layer on every 10th frame from the 5th, none leaving a negative rest
local POSE: number = 0.125
local POSED_FRAMES: number = 60
local DRAW: number = 0.25
local RECEIVE: number = 0.125
local LAYER: number = 0.375
local LAYER_EVERY: number = 10
local LAYER_FROM: number = 5

local NATIVE: number = 10.5 -- Microseconds a pass of each loop
local INTERPRETED: number = 157.5

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

-- The line those samples give, a clause at a time, every figure printed before the frame times first and unchanged
local COUNTS: string = "Mike on touch: 100 frames, FPS p10 42.0, rigs drawn p50 149"
local REMOTE: string = "remote ms p50/p95/p99 6.250/11.875/12.375 against 2 ms"
local FRAME_TIMES: string = "frame ms p50/p95/p99/max 10.000/25.000/40.000/50.000, remote ms max 12.500"
local HITCHES: string = "hitches 6 (6.00%) past 2x the median frame, 2 (2.00%) past 33.3 ms"
local LINE: string = `{COUNTS}, {REMOTE}, {FRAME_TIMES}, {HITCHES}`

-- And the clauses after them
local PARTS: string =
	"remote parts ms p50/p95/p99 pose 0.125/0.125/0.125, draw 0.000/0.250/0.250, receive 0.000/0.125/0.125, layer 0.000/0.375/0.375, rest 6.000/11.500/12.000"
local STEPPED: string = "simulation steps a frame p50 2, max 4"
local BLOCKED: string =
	"25 frames with a relay block at remote ms p95 12.000 and frame ms p95 20.000, 75 without at 11.875 and 25.000"
local LOOPS: string = "native loop µs a pass of 1024 B p50 10.500, interpreted 157.500, interpreted/native 15.00"
local FIRSTS: string = "first draws 2 track loads, at most 1 a frame, and 3 clones, at most 2 a frame"
local SWITCHED: string = "track switches a frame p50/p99/max 1/2/9"
local SPIKES: string =
	"of the 6 past 2x the median frame, 1 had a relay block, 2 followed a heap drop, 2 had a first draw and 3 more than 1 track switches"
local PAST: string =
	"of the 2 past 33.3 ms, 1 had a relay block, 1 followed a heap drop, 1 had a first draw and 0 more than 1 track switches"
local SPLIT_LINE: string = `{LINE}, {PARTS}, {STEPPED}, {BLOCKED}, {LOOPS}, {FIRSTS}, {SWITCHED}, {SPIKES}, {PAST}`

-- The same window without the split
local UNSPLIT_SPIKES: string = "of the 6 past 2x the median frame, 1 had a relay block and 2 followed a heap drop"
local UNSPLIT_PAST: string = "of the 2 past 33.3 ms, 1 had a relay block and 1 followed a heap drop"
local UNSPLIT: string = "split off, so no pose, draw, first draw or track switch was wrapped"
local UNSPLIT_LINE: string = `{LINE}, {STEPPED}, {BLOCKED}, {LOOPS}, {UNSPLIT_SPIKES}, {UNSPLIT_PAST}, {UNSPLIT}`

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A list of a value for each frame, from its place
local function byFrame(value: (index: number) -> number): { number }
	local list: { number } = {}
	for index: number = 1, FRAMES do
		table.insert(list, value(index))
	end

	return list
end

-- A window as the cost keeps one, holding copies of the samples given, so each summary sorts only its own
local function windowOf(
	remote: { number },
	frames: { number },
	rates: { number },
	drawn: { number },
	split: boolean
): { [string]: any }
	local blocks: { number } = byFrame(function (index: number): number
		return index % BLOCK_EVERY == 1 and 1 or 0
	end)

	return {
		label = "case",
		split = split,
		remote = table.clone(remote),
		frames = table.clone(frames),
		rates = table.clone(rates),
		drawn = table.clone(drawn),
		steps = byFrame(function (index: number): number
			return index % STEPS_CYCLE
		end),
		blocks = blocks,
		heap = byFrame(function (index: number): number
			return DROPS[index] or HEAP + index
		end),
		parts = {
			pose = byFrame(function (index: number): number
				return index <= POSED_FRAMES and POSE or 0
			end),
			draw = byFrame(function (index: number): number
				return DRAW * (index % 2)
			end),
			receive = byFrame(function (index: number): number
				return RECEIVE * blocks[index]
			end),
			layer = byFrame(function (index: number): number
				return index % LAYER_EVERY == LAYER_FROM and LAYER or 0
			end),
		},
		loads = byFrame(function (index: number): number
			return LOADS[index] or 0
		end),
		clones = byFrame(function (index: number): number
			return CLONES[index] or 0
		end),
		switches = byFrame(function (index: number): number
			return index == FRAMES and LAST_SWITCHES or index % SWITCH_CYCLE
		end),
		native = NATIVE,
		interpreted = INTERPRETED,
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

	local frames: { number } = table.clone(SLOW_FRAMES)
	for _ = 1, STEADY_FRAMES do
		table.insert(frames, STEADY_FRAME)
	end

	for _, frame: number in LATE_FRAMES do
		table.insert(frames, frame)
	end

	local measured: boolean, line: string = Cost.summary(windowOf(remote, frames, rates, DRAWN, true), PLAYER, INPUT)
	if not measured or line ~= SPLIT_LINE then
		return false, `A window of known samples gave {measured} with "{line}", not true with "{SPLIT_LINE}"`
	end

	-- 3) The same window without the split prints every figure that needs no added wrapper, and says so
	local unsplit: boolean, plain: string = Cost.summary(windowOf(remote, frames, rates, DRAWN, false), PLAYER, INPUT)
	if not unsplit or plain ~= UNSPLIT_LINE then
		return false, `The window without the split gave {unsplit} with "{plain}", not true with "{UNSPLIT_LINE}"`
	end

	-- 4) A window that timed no frame is refused
	local timed: boolean, refusal: string = Cost.summary(windowOf({}, {}, {}, {}, true), PLAYER, INPUT)
	if timed or not refusal:find(`{PLAYER} on {INPUT}: refused`, 1, true) then
		return false, `A window with no frame gave {timed} with "{refusal}", not a refusal`
	end

	return true, nil
end
