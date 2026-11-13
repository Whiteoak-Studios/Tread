--[[
    G5's cost times a frame's remote work on stand-in module tables as the
    frame less the prediction inside it, plus the layers and receives since
    the frame before, hands every call on, and puts each member back
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local UNIT: number = 2 ^ -10 -- Seconds each step of the stand-in clock is, so every sum is exact
local BEFORE: number = 1 -- Steps the stand-in frame takes before its prediction, the prediction, and after it
local PREDICTION: number = 2
local AFTER: number = 4
local LAYER: number = 8 -- Steps a layer takes, and a receive
local RECEIVE: number = 16
local FIRST_DT: number = 0.25 -- Seconds each frame's delta is, 4 and then 2 frames a second
local SECOND_DT: number = 0.5
local DATA_BYTES: number = 3
local ROUNDING: number = 1e-9 -- Milliseconds a sample may sit from the one worked out here

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A frame's remote work as the case works it out, in milliseconds
local function milliseconds(steps: number): number
	return steps * UNIT * 1000
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")

	-- The dev client's folder, with its Config and the cost, and the dev scope's client module standing in
	local folder: any = create("Folder", "Client", replicated)
	local files: { [any]: string } = {
		[create("ModuleScript", "Config", folder)] = CONFIG,
		[create("ModuleScript", "Cost", folder)] = COST,
	}

	local results: { [any]: any } = { [replicated.Shared.Network.Client] = { clientCost = { fire = function () end } } }
	local Cost: any = Kit.loader(dataModel, files, results, loaded.require)(folder.Cost)

	local now: number = 0
	local calls: { string } = {} -- What each stand-in was handed, in the order called

	local function clock(): number
		return now
	end

	-- Tread's client calls its prediction through the prediction's table, so the stand-in frame does too
	local predict: any = {}
	predict.frame = function (dt: number)
		table.insert(calls, `prediction {dt}`)
		now += PREDICTION * UNIT
	end

	local client: any = {}
	client._frame = function (self: any, dt: number)
		table.insert(calls, `frame {self.name} {dt}`)
		now += BEFORE * UNIT
		predict.frame(dt)
		now += AFTER * UNIT
	end

	local rigs: any = {}
	rigs._layer = function (self: any)
		table.insert(calls, `layer {self.name}`)
		now += LAYER * UNIT
	end

	local interpolate: any = {}
	interpolate.receive = function (data: buffer)
		table.insert(calls, `receive {buffer.len(data)}`)
		now += RECEIVE * UNIT
	end

	local originals: { any } = { client._frame, predict.frame, rigs._layer, interpolate.receive }
	local drawn: number = 7
	local modules: { [string]: any } = { client = client, predict = predict, rigs = rigs, interpolate = interpolate }
	local window: any = Cost.open("case", modules, clock, function (): number
		return drawn
	end)

	local handle: { name: string } = { name = "handle" }
	local pool: { name: string } = { name = "pool" }

	-- 1) A receive and a layer before the frame count into it, and the prediction inside it is left out
	interpolate.receive(buffer.create(DATA_BYTES))
	rigs._layer(pool)
	client._frame(handle, FIRST_DT)

	local first: number = milliseconds(BEFORE + AFTER + LAYER + RECEIVE)
	if #window.remote ~= 1 or math.abs(window.remote[1] - first) > ROUNDING then
		return false, `The first frame timed {window.remote[1]} ms of remote work, not {first}`
	end

	-- 2) The next frame, with nothing between, counts its own work alone
	drawn = 9
	client._frame(handle, SECOND_DT)

	local second: number = milliseconds(BEFORE + AFTER)
	if #window.remote ~= 2 or math.abs(window.remote[2] - second) > ROUNDING then
		return false, `The second frame timed {window.remote[2]} ms of remote work, not {second}`
	elseif table.concat(window.drawn, ",") ~= "7,9" then
		return false, `The frames read {table.concat(window.drawn, ",")} rigs drawn, not 7 and then 9`
	elseif table.concat(window.rates, ",") ~= "4,2" then
		return false, `The frames read {table.concat(window.rates, ",")} frames a second, not 4 and then 2`
	end

	-- 3) Every call reached the member it replaced with its own arguments, in order
	local wanted: string = table.concat({
		`receive {DATA_BYTES}`,
		"layer pool",
		`frame handle {FIRST_DT}`,
		`prediction {FIRST_DT}`,
		`frame handle {SECOND_DT}`,
		`prediction {SECOND_DT}`,
	}, ", ")

	if table.concat(calls, ", ") ~= wanted then
		return false, `The stand-ins were handed {table.concat(calls, ", ")}, not {wanted}`
	end

	-- 4) Restored, each table holds its own member again, and nothing after it is timed
	window.restore()
	local held: { any } = { client._frame, predict.frame, rigs._layer, interpolate.receive }
	for index: number, original: any in originals do
		if held[index] ~= original then
			return false, `Member {index} of the four was not put back as the window found it`
		end
	end

	interpolate.receive(buffer.create(DATA_BYTES))
	client._frame(handle, FIRST_DT)
	if #window.remote ~= 2 or window.pending ~= 0 then
		return false, `After the restore the window holds {#window.remote} frames and {window.pending} s pending`
	end

	return true, nil
end
