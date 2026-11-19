--[[
    G5's cost times a frame's remote work on stand-in module tables as the
    frame less the prediction inside it, plus the layers and receives since
    the frame before, keeps each frame's delta, hands every call on, and
    puts each member back
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local COST: string = "dev/Client/Cost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local NATIVE_LOOP: string = "dev/Client/NativeLoop.luau"
local INTERPRETED_LOOP: string = "dev/Client/InterpretedLoop.luau"
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
local SLOT: number = 4 -- The slot the stand-in pose is asked for
local PITCH: number = 0.25 -- What the stand-in pose gives beside true: the aim pitch and the head offset
local HEAD_YAW: number = 3
local HEAD_PITCH: number = -2
local DISTANCE: number = 12 -- What the stand-in draw is handed: the distance, the pitch and the studs back
local DRAW_PITCH: number = 0.5
local BACK: number = 1
local SPEED: number = 0.75 -- The track speed the stand-in play is handed
local KILOBYTES: number = 64 -- What the stand-in heap reads
local EVERY_WINDOW: number = 4 -- The members every window wraps, first among the originals, the split's after them

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
		[create("ModuleScript", "NativeLoop", folder)] = NATIVE_LOOP,
		[create("ModuleScript", "InterpretedLoop", folder)] = INTERPRETED_LOOP,
	}

	local results: { [any]: any } = { [replicated.Shared.Network.Client] = { clientCost = { fire = function () end } } }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)

	-- With the split on whatever the dev client sets, so every member it wraps is checked
	load(folder.Config).cost.split = true
	local Cost: any = load(folder.Cost)

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

	-- The members the split wraps, each naming what it was handed and giving back what it was given to
	local animated: { name: string } = { name = "tracks" }
	local built: { name: string } = { name = "clone" }

	rigs._draw = function (self: any, entry: any, state: any, distance: number, pitch: number, back: number)
		table.insert(calls, `draw {self.name} {entry.name} {state.name} {distance} {pitch} {back}`)
	end

	rigs._animate = function (self: any, entry: any): any
		table.insert(calls, `animate {self.name} {entry.name}`)

		return animated
	end

	rigs._build = function (self: any): any
		table.insert(calls, `build {self.name}`)

		return built
	end

	rigs.frame = function (self: any)
		table.insert(calls, `finish {self.name}`)
	end

	local interpolate: any = {}
	interpolate.receive = function (data: buffer)
		table.insert(calls, `receive {buffer.len(data)}`)
		now += RECEIVE * UNIT
	end

	interpolate.pose = function (slot: number, into: any): (boolean, number, number, number)
		table.insert(calls, `pose {slot} {into.name}`)

		return true, PITCH, HEAD_YAW, HEAD_PITCH
	end

	local animate: any = {}
	animate.pose = function (tracks: any, state: any, full: boolean, speed: number?)
		table.insert(calls, `play {tracks.name} {state.name} {full} {speed}`)
	end

	local originals: { any } = {
		client._frame,
		predict.frame,
		rigs._layer,
		interpolate.receive,
		interpolate.pose,
		rigs._draw,
		rigs._animate,
		rigs._build,
		rigs.frame,
		animate.pose,
	}

	local drawn: number = 7
	local modules: { [string]: any } =
		{ client = client, predict = predict, rigs = rigs, interpolate = interpolate, animate = animate }
	local window: any = Cost.open("case", modules, clock, function (): number
		return drawn
	end, function (): number
		return KILOBYTES
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
	elseif table.concat(window.frames, ",") ~= "250,500" then
		return false, `The frames read {table.concat(window.frames, ",")} ms long, not 250 and then 500`
	end

	-- 3) The members the split wraps are wrapped, and hand back what the ones they replaced gave
	local wrapped: { any } = { interpolate.pose, rigs._draw, rigs._animate, rigs._build, rigs.frame, animate.pose }
	for index: number, member: any in wrapped do
		if member == originals[EVERY_WINDOW + index] then
			return false, `Member {EVERY_WINDOW + index} of the {#originals} was left unwrapped with the split on`
		end
	end

	local entry: { name: string } = { name = "entry" }
	local state: { name: string } = { name = "state" }
	local shown: boolean, pitch: number, headYaw: number, headPitch: number = interpolate.pose(SLOT, state)
	rigs._draw(pool, entry, state, DISTANCE, DRAW_PITCH, BACK)
	local tracks: any = rigs._animate(pool, entry)
	local cloned: any = rigs._build(pool)
	rigs.frame(pool)
	animate.pose(animated, state, true, SPEED)

	if not shown or pitch ~= PITCH or headYaw ~= HEAD_YAW or headPitch ~= HEAD_PITCH then
		return false, `The pose gave {shown}, {pitch}, {headYaw} and {headPitch}, not what the stand-in gave`
	elseif tracks ~= animated or cloned ~= built then
		return false, "The track load or the clone gave back something other than the stand-in's"
	end

	-- 4) Every call reached the member it replaced with its own arguments, in order
	local wanted: string = table.concat({
		`receive {DATA_BYTES}`,
		"layer pool",
		`frame handle {FIRST_DT}`,
		`prediction {FIRST_DT}`,
		`frame handle {SECOND_DT}`,
		`prediction {SECOND_DT}`,
		`pose {SLOT} state`,
		`draw pool entry state {DISTANCE} {DRAW_PITCH} {BACK}`,
		"animate pool entry",
		"build pool",
		"finish pool",
		`play tracks state true {SPEED}`,
	}, ", ")

	if table.concat(calls, ", ") ~= wanted then
		return false, `The stand-ins were handed {table.concat(calls, ", ")}, not {wanted}`
	end

	-- 5) Restored, each table holds its own member again, and nothing after it is timed
	window.restore()
	local held: { any } = {
		client._frame,
		predict.frame,
		rigs._layer,
		interpolate.receive,
		interpolate.pose,
		rigs._draw,
		rigs._animate,
		rigs._build,
		rigs.frame,
		animate.pose,
	}

	for index: number, original: any in originals do
		if held[index] ~= original then
			return false, `Member {index} of the {#originals} was not put back as the window found it`
		end
	end

	interpolate.receive(buffer.create(DATA_BYTES))
	client._frame(handle, FIRST_DT)
	if #window.remote ~= 2 or window.pending ~= 0 then
		return false, `After the restore the window holds {#window.remote} frames and {window.pending} s pending`
	end

	return true, nil
end
