--[[
    G5's cost splits each frame's remote work by part on stand-in module
    tables: the pose and the draws inside it, the receives and the layers
    before it, and the rest they leave, and leaves both unwrapped unsplit
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
local BEFORE: number = 1 -- Steps the stand-in frame takes before its prediction, the prediction, and after it
local PREDICTION: number = 3
local AFTER: number = 2
local POSE: number = 4 -- Steps a pose takes, a draw, a layer and a receive
local DRAW: number = 5
local LAYER: number = 6
local RECEIVE: number = 7
local FIRST_DT: number = 0.25 -- Seconds each frame's delta is
local SECOND_DT: number = 0.5
local KILOBYTES: number = 64 -- What the stand-in heap reads
local ROUNDING: number = 1e-9 -- Milliseconds a sample may sit from the one worked out here

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

-- The cost, loaded fresh into a fake game on the case's own values with the split as given
local function costOf(split: boolean): any
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

	local values: { [string]: any } = table.clone(COST_VALUES)
	values.split = split
	load(folder.Config).cost = values

	return load(folder.Cost)
end

-- Whether a list holds exactly the milliseconds of the steps given, in order
local function holds(list: { number }, steps: { number }): boolean
	if #list ~= #steps then
		return false
	end

	for index: number, step: number in steps do
		if math.abs(list[index] - milliseconds(step)) > ROUNDING then
			return false
		end
	end

	return true
end

return function (): (boolean, string | nil)
	local now: number = 0
	local rigsDrawn: number = 0 -- The rigs the stand-in frame poses and draws

	local function clock(): number
		return now
	end

	-- Tread's client calls each member through its module's table, so the stand-ins do too
	local predict: any = {}
	predict.frame = function (_: number)
		now += PREDICTION * UNIT
	end

	local interpolate: any = {}
	interpolate.receive = function (_: buffer)
		now += RECEIVE * UNIT
	end

	interpolate.pose = function (_: number, _: any): (boolean, number, number, number)
		now += POSE * UNIT

		return true, 0, 0, 0
	end

	local animate: any = {}
	animate.pose = function (_: any, _: any, _: boolean, _: number?) end

	local rigs: any = {}
	rigs._layer = function (_: any)
		now += LAYER * UNIT
	end

	rigs._draw = function (_: any, entry: any, state: any, _: number, _: number, _: number)
		now += DRAW * UNIT
		animate.pose(entry, state, true, 1)
	end

	rigs._animate = function (_: any, _: any): any
		return {}
	end

	rigs._build = function (_: any): any
		return {}
	end

	local client: any = {}
	client._frame = function (self: any, dt: number)
		now += BEFORE * UNIT
		predict.frame(dt)

		for _ = 1, rigsDrawn do
			local state: { [string]: any } = {}
			interpolate.pose(1, state)
			rigs._draw(self, {}, state, 0, 0, 0)
		end

		now += AFTER * UNIT
	end

	local modules: { [string]: any } =
		{ client = client, predict = predict, rigs = rigs, interpolate = interpolate, animate = animate }

	local function count(): number
		return rigsDrawn
	end

	local function memory(): number
		return KILOBYTES
	end

	-- 1) A receive and two layers before a frame posing and drawing two rigs, then a pose and a draw outside any
	-- frame, a layer, and a frame drawing one rig: each part lands in its frame, and the outside draw in none
	local Cost: any = costOf(true)
	local window: any = Cost.open("case", modules, clock, count, memory)
	local handle: { [string]: any } = {}

	interpolate.receive(buffer.create(1))
	rigs._layer(handle)
	rigs._layer(handle)
	rigsDrawn = 2
	client._frame(handle, FIRST_DT)

	interpolate.pose(1, {})
	rigs._draw(handle, {}, {}, 0, 0, 0)
	rigs._layer(handle)
	rigsDrawn = 1
	client._frame(handle, SECOND_DT)

	local parts: { [string]: { number } } = window.parts
	local rest: number = BEFORE + AFTER
	if not holds(window.remote, { rest + 2 * (POSE + DRAW) + RECEIVE + 2 * LAYER, rest + POSE + DRAW + LAYER }) then
		return false, `The frames timed {table.concat(window.remote, ", ")} ms of remote work, not their parts' sums`
	elseif not holds(parts.pose, { 2 * POSE, POSE }) or not holds(parts.draw, { 2 * DRAW, DRAW }) then
		local poses: string = table.concat(parts.pose, ", ")

		return false, `The poses read {poses} ms and the draws {table.concat(parts.draw, ", ")}`
	elseif not holds(parts.receive, { RECEIVE, 0 }) or not holds(parts.layer, { 2 * LAYER, LAYER }) then
		local receives: string = table.concat(parts.receive, ", ")

		return false, `The receives read {receives} ms and the layers {table.concat(parts.layer, ", ")}`
	end

	-- 2) The line gives each part's spread and the rest the parts leave, which is the frame's own steps alone
	local _, line: string = Cost.summary(window, "Mike", "mouse")
	local split: string =
		"remote parts ms p50/p95/p99 pose 62.500/125.000/125.000, draw 78.125/156.250/156.250, receive 0.000/109.375/109.375, layer 93.750/187.500/187.500, rest 46.875/46.875/46.875"
	if not line:find(split, 1, true) then
		return false, `The line "{line}" holds no "{split}"`
	end

	window.restore()

	-- 3) Unsplit, the pose and the draw stay unwrapped, so their time is the rest, and the line says so
	local wrapped: { any } = { interpolate.pose, rigs._draw, rigs._animate, rigs._build, animate.pose }
	local Unsplit: any = costOf(false)
	local plain: any = Unsplit.open("case", modules, clock, count, memory)
	local unwrapped: { any } = { interpolate.pose, rigs._draw, rigs._animate, rigs._build, animate.pose }
	for index: number, member: any in wrapped do
		if unwrapped[index] ~= member then
			return false, `Unsplit, member {index} of the split's {#wrapped} was wrapped anyway`
		end
	end

	client._frame(handle, FIRST_DT)

	local _, unsplitLine: string = Unsplit.summary(plain, "Mike", "mouse")
	if not holds(plain.remote, { rest + POSE + DRAW }) or #plain.parts.pose ~= 0 or #plain.loads ~= 0 then
		return false, `Unsplit, a frame drawing one rig timed {plain.remote[1]} ms and kept {#plain.parts.pose} poses`
	elseif unsplitLine:find("remote parts", 1, true) or not unsplitLine:find("split off, so", 1, true) then
		return false, `Unsplit, the line "{unsplitLine}" splits the parts or never says the split was off`
	end

	plain.restore()

	return true, nil
end
