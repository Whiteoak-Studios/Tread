--[[
    G5's cost counts the relay blocks and the simulation steps in each
    frame's delta on stand-in module tables, and reads the frames with a
    block apart from the rest at their own share
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local NATIVE_LOOP: string = "dev/Client/NativeLoop.luau"
local INTERPRETED_LOOP: string = "dev/Client/InterpretedLoop.luau"
local UNIT: number = 2 ^ -6 -- Seconds each step of the stand-in clock is, 15.625 ms, so every figure prints exactly
local FRAME: number = 2 -- Steps the stand-in frame takes, a receive and a layer
local RECEIVE: number = 4
local LAYER: number = 2
local DELTAS: { number } = { 0.125, 0.25, 0.375, 0.5 } -- Seconds of each frame's delta, in order
local KILOBYTES: number = 64 -- What the stand-in heap reads

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

-- What the line says of the frames with a block and those without, and of the steps
local BLOCKED: string =
	"2 frames with a relay block at remote ms p95 187.500 and frame ms p95 375.000, 2 without at 62.500 and 500.000"
local STEPPED: string = "simulation steps a frame p50 0, max 3"

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

	local now: number = 0
	local function clock(): number
		return now
	end

	local client: any = {}
	client._frame = function (_: any, _: number)
		now += FRAME * UNIT
	end

	local interpolate: any = {}
	interpolate.receive = function (_: buffer)
		now += RECEIVE * UNIT
	end

	interpolate.pose = function (_: number, _: any): (boolean, number, number, number)
		return true, 0, 0, 0
	end

	local rigs: any = {}
	rigs._layer = function (_: any)
		now += LAYER * UNIT
	end

	rigs._draw = function (_: any, _: any, _: any, _: number, _: number, _: number) end
	rigs._animate = function (_: any, _: any): any
		return {}
	end

	rigs._build = function (_: any): any
		return {}
	end

	local modules: { [string]: any } = {
		client = client,
		predict = { frame = function (_: number) end },
		rigs = rigs,
		interpolate = interpolate,
		animate = { pose = function (_: any, _: any, _: boolean, _: number?) end },
	}

	local window: any = Cost.open("case", modules, clock, function (): number
		return 0
	end, function (): number
		return KILOBYTES
	end)

	-- 1) A block and three steps before the first frame, a step before the second, two blocks before the third and
	-- nothing before the fourth, each frame counting what came since the one before
	local handle: { [string]: any } = {}
	interpolate.receive(buffer.create(1))
	for _ = 1, 3 do
		rigs._layer(handle)
	end
	client._frame(handle, DELTAS[1])

	rigs._layer(handle)
	client._frame(handle, DELTAS[2])

	interpolate.receive(buffer.create(1))
	interpolate.receive(buffer.create(1))
	client._frame(handle, DELTAS[3])

	client._frame(handle, DELTAS[4])

	-- A block after the last frame lies in no frame's delta
	interpolate.receive(buffer.create(1))

	local blocks: string = table.concat(window.blocks, ",")
	local steps: string = table.concat(window.steps, ",")
	if blocks ~= "1,0,2,0" or steps ~= "3,1,0,0" then
		return false, `The frames counted {blocks} blocks and {steps} steps, not 1,0,2,0 and 3,1,0,0`
	end

	-- 2) The first and third frames read apart from the other two, the remote work holding each frame's blocks
	local _, line: string = Cost.summary(window, "Mike", "mouse")
	window.restore()

	if not line:find(BLOCKED, 1, true) then
		return false, `The line "{line}" holds no "{BLOCKED}"`
	elseif not line:find(STEPPED, 1, true) then
		return false, `The line "{line}" holds no "{STEPPED}"`
	end

	return true, nil
end
