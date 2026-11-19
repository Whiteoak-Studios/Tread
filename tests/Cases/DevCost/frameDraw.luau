--[[
    G5's cost adds the pool's frame end into each frame's draw part, a draw
    the frame end grants counted once inside it, so the rest stays the
    frame's own steps; restored, the frame end is the pool's own again
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local NATIVE_LOOP: string = "dev/Client/NativeLoop.luau"
local INTERPRETED_LOOP: string = "dev/Client/InterpretedLoop.luau"
local UNIT: number = 2 ^ -6 -- Seconds each step of the stand-in clock is, so every figure is exact
local BEFORE: number = 1 -- Steps the stand-in frame takes before its prediction, the prediction, and after it
local PREDICTION: number = 3
local AFTER: number = 2
local POSE: number = 4 -- Steps a pose takes, a draw, and the frame end's own work
local DRAW: number = 5
local FINISH: number = 6
local FRAME_DT: number = 0.25 -- Seconds the frame's delta is
local KILOBYTES: number = 64 -- What the stand-in heap reads
local ROUNDING: number = 1e-9 -- Milliseconds a sample may sit from the one worked out here

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A frame's part as the case works it out, in milliseconds
local function milliseconds(steps: number): number
	return steps * UNIT * 1000
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")

	local folder: any = create("Folder", "Client", replicated)
	local files: { [any]: string } = {
		[create("ModuleScript", "Config", folder)] = CONFIG,
		[create("ModuleScript", "Cost", folder)] = COST,
		[create("ModuleScript", "NativeLoop", folder)] = NATIVE_LOOP,
		[create("ModuleScript", "InterpretedLoop", folder)] = INTERPRETED_LOOP,
	}

	local results: { [any]: any } = { [replicated.Shared.Network.Client] = { clientCost = { fire = function () end } } }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)

	-- With the split on whatever the dev client sets, so the frame end is wrapped
	load(folder.Config).cost.split = true
	local Cost: any = load(folder.Cost)

	local now: number = 0
	local function clock(): number
		return now
	end

	-- Tread's client calls each member through its module's table, so the stand-ins do too
	local predict: any = {}
	predict.frame = function (_: number)
		now += PREDICTION * UNIT
	end

	local interpolate: any = {}
	interpolate.receive = function (_: buffer) end
	interpolate.pose = function (_: number, _: any): (boolean, number, number, number)
		now += POSE * UNIT

		return true, 0, 0, 0
	end

	local animate: any = {}
	animate.pose = function (_: any, _: any, _: boolean, _: number?) end

	local rigs: any = {}
	rigs._layer = function (_: any) end
	rigs._animate = function (_: any, _: any): any
		return {}
	end
	rigs._build = function (_: any): any
		return {}
	end

	rigs._draw = function (_: any, _: any, _: any, _: number, _: number, _: number)
		now += DRAW * UNIT
	end

	-- The frame end grants one draw that waited, which the pool makes through its own table
	rigs.frame = function (self: any)
		now += FINISH * UNIT
		rigs._draw(self, {}, {}, 0, 0, 0)
	end

	local finish: any = rigs.frame

	-- One rig posed and drawn, then the pool's frame end, as Tread's client ends its frame
	local client: any = {}
	client._frame = function (self: any, dt: number)
		now += BEFORE * UNIT
		predict.frame(dt)
		interpolate.pose(1, {})
		rigs._draw(self, {}, {}, 0, 0, 0)
		rigs.frame(self)
		now += AFTER * UNIT
	end

	local modules: { [string]: any } =
		{ client = client, predict = predict, rigs = rigs, interpolate = interpolate, animate = animate }
	local window: any = Cost.open("case", modules, clock, function (): number
		return 1
	end, function (): number
		return KILOBYTES
	end)

	-- 1) The frame's draw part holds its own draw, the frame end and the draw it granted, each once
	local handle: { [string]: any } = {}
	client._frame(handle, FRAME_DT)

	local draw: number = window.parts.draw[1]
	local wanted: number = milliseconds(DRAW + FINISH + DRAW)
	local remote: number = window.remote[1]
	local whole: number = milliseconds(BEFORE + AFTER + POSE + DRAW + FINISH + DRAW)
	if math.abs(draw - wanted) > ROUNDING then
		return false, `The frame's draw part read {draw} ms, not its draw, frame end and granted draw's {wanted}`
	elseif math.abs(remote - whole) > ROUNDING then
		return false, `The frame timed {remote} ms of remote work, not {whole}`
	end

	-- 2) Restored, the pool's own frame end is back
	window.restore()
	if rigs.frame ~= finish then
		return false, "The restore left the frame end wrapped"
	end

	return true, nil
end
