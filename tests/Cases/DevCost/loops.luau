--[[
    G5's cost times the native and the interpreted loop in turn at their
    median samples on a stand-in clock, and both client loops run the server
    calibration's loop body, one module native and the other not
--]]

--!strict
local fs = require("@lune/fs")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local NATIVE_LOOP: string = "dev/Client/NativeLoop.luau"
local INTERPRETED_LOOP: string = "dev/Client/InterpretedLoop.luau"
local WORK: string = "dev/Server/Parallel/Work.luau" -- The server calibration's loop
local NATIVE: string = "\n--!native\n" -- The directive line
local BODY_START: string = "local size: number = buffer.len(data)" -- The loop body's first line and its last
local BODY_END: string = "return total"
local UNIT: number = 2 ^ -20 -- Seconds each step of the stand-in clock is
local NATIVE_STEPS: number = 8 -- Steps each sample of the stand-in native loop takes, but its first
local SLOW_STEPS: number = 100 -- Its first sample's, which the median leaves out
local INTERPRETED_STEPS: number = 120
local SAMPLES: number = 5
local PASSES: number = 4
local BYTES: number = 16
local MIXED_BYTES: number = 1000 -- The buffer the real loops are compared over, its bytes counting up and wrapping
local BYTE_VALUES: number = 256
local MIXED_PASSES: number = 3
local ROUNDING: number = 1e-9 -- Microseconds a median may sit from the one worked out here

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
	loop = { samples = SAMPLES, passes = PASSES, bytes = BYTES },
}

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A file's text from its loop body's first line to its last, nil when it holds none
local function bodyOf(path: string): string?
	local source: string = fs.readFile(path)
	local first: number? = source:find(BODY_START, 1, true)
	if not first then
		return nil
	end

	local _, last: number? = source:find(BODY_END, first, true)
	if not last then
		return nil
	end

	return source:sub(first, last)
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
	load(folder.Config).cost = COST_VALUES
	local Cost: any = load(folder.Cost)

	-- 1) The loops run in turn, each handed the configured buffer and passes, and each keeps its median sample
	local now: number = 0
	local calls: { string } = {}

	local function clock(): number
		return now
	end

	local function native(data: buffer, passes: number): number
		table.insert(calls, `native {buffer.len(data)} {passes}`)
		now += (#calls == 1 and SLOW_STEPS or NATIVE_STEPS) * UNIT

		return 0
	end

	local function interpreted(data: buffer, passes: number): number
		table.insert(calls, `interpreted {buffer.len(data)} {passes}`)
		now += INTERPRETED_STEPS * UNIT

		return 0
	end

	local window: { [string]: any } = { native = 0, interpreted = 0 }
	Cost.loops(window, clock, native, interpreted)

	local wanted: { string } = {}
	for _ = 1, SAMPLES do
		table.insert(wanted, `native {BYTES} {PASSES}`)
		table.insert(wanted, `interpreted {BYTES} {PASSES}`)
	end

	if table.concat(calls, ", ") ~= table.concat(wanted, ", ") then
		return false, `The loops were run as {table.concat(calls, ", ")}, not {table.concat(wanted, ", ")}`
	end

	local nativeMedian: number = NATIVE_STEPS * UNIT * 1e6 / PASSES
	local interpretedMedian: number = INTERPRETED_STEPS * UNIT * 1e6 / PASSES
	if math.abs(window.native - nativeMedian) > ROUNDING then
		return false, `The native loop kept {window.native} µs a pass, not its median {nativeMedian}`
	elseif math.abs(window.interpreted - interpretedMedian) > ROUNDING then
		return false, `The interpreted loop kept {window.interpreted} µs a pass, not its median {interpretedMedian}`
	end

	-- 2) Both client loops give the server calibration's total, and their files hold its loop body, the native one
	-- alone carrying the directive
	local data: buffer = buffer.create(MIXED_BYTES)
	for at: number = 0, MIXED_BYTES - 1 do
		buffer.writeu8(data, at, at % BYTE_VALUES)
	end

	local expected: number = loaded.require(server.Parallel.Work).spin(data, MIXED_PASSES)
	local nativeTotal: number = load(folder.NativeLoop)(data, MIXED_PASSES)
	local interpretedTotal: number = load(folder.InterpretedLoop)(data, MIXED_PASSES)
	if nativeTotal ~= expected or interpretedTotal ~= expected then
		return false, `The loops gave {nativeTotal} and {interpretedTotal}, not the calibration's {expected}`
	end

	local body: string? = bodyOf(WORK)
	local nativeDirective: boolean = fs.readFile(NATIVE_LOOP):find(NATIVE, 1, true) ~= nil
	local interpretedDirective: boolean = fs.readFile(INTERPRETED_LOOP):find(NATIVE, 1, true) ~= nil
	if body == nil or bodyOf(NATIVE_LOOP) ~= body or bodyOf(INTERPRETED_LOOP) ~= body then
		return false, "A client loop's body differs from the server calibration's"
	elseif not nativeDirective or interpretedDirective then
		return false, "The native directive is not on the native loop alone"
	end

	return true, nil
end
