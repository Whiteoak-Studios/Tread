--[[
    G5's client side: while the Workspace attribute names a window, times
    each frame's remote-character work by part through Tread's module tables,
    counts what each frame held, and sends its line over the dev scope
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages
local Player = Players.LocalPlayer

local Tread = require(Packages.Tread)

local Network = require(ReplicatedStorage.Shared.Network.Client)

-- Requiring each finds the module Tread's client already started, whose calls look each wrapped member up in it
local Animate = require(Packages.Tread.Client.Rigs.Animate)
local Client = require(Packages.Tread.Client)
local Interpolate = require(Packages.Tread.Client.Interpolate)
local Predict = require(Packages.Tread.Client.Predict)
local Rigs = require(Packages.Tread.Client.Rigs)

local CostConfig = require(script.Parent.Config).cost
local Frames = require(ReplicatedStorage.Shared.Dev.Frames)
local FramesConfig = require(ReplicatedStorage.Shared.Dev.FramesConfig)
local InterpretedLoop = require(script.Parent.InterpretedLoop)
local NativeLoop = require(script.Parent.NativeLoop)

local ATTRIBUTE: string = CostConfig.attribute
local LONGEST: number = CostConfig.longest
local LIMIT: number = CostConfig.limit
local PERCENTILES: { number } = FramesConfig.percentiles
local DRAWN: number = CostConfig.drawn
local BLOCKS: number = CostConfig.blocks
local SWITCHES: { number } = CostConfig.switches
local SPLIT: boolean = CostConfig.split
local LOOP_SAMPLES: number = CostConfig.loop.samples
local LOOP_PASSES: number = CostConfig.loop.passes
local LOOP_BYTES: number = CostConfig.loop.bytes
local MILLISECONDS: number = 1000 -- A second's, which the remote work and the frame times print in
local MICROSECONDS: number = 1e6 -- A second's, which the loops print in
local PERCENT: number = 100 -- Turns a share into the number a pNN label shows
local MEDIAN: number = 0.5 -- The share the median frame is read at
local WORST: number = 1 -- The share whose nearest rank is the largest sample
local TIME_FIGURE: string = "%.3f" -- Milliseconds, and the loops' microseconds, as the line prints them
local RATIO_FIGURE: string = "%.2f" -- The interpreted loop's time over the native one's
local COUNT_FIGURE: string = "%d" -- Calls a frame
local UNSPLIT: string = "split off, so no pose, draw, first draw or track switch was wrapped" -- Ends an unsplit line

type Slot = Tread.Slot
type Slow = Frames.Slow

-- The members Cost wraps, each a function its module's table holds and Tread's client looks up there at each call
type Frame = (self: any, dt: number) -> ()
type Advance = (dt: number) -> ()
type Layer = (self: any) -> ()
type Receive = (data: buffer) -> ()
type Sample = (slot: number, into: any) -> (boolean, number, number, number)
type Draw = (self: any, entry: any, state: any, distance: number, pitch: number, back: number) -> ()
type Finish = (self: any) -> ()
type Load = (self: any, entry: any) -> any
type Build = (self: any) -> any
type Play = (animated: any, state: any, full: boolean, speed: number?) -> ()

-- A loop the window times, handed its buffer and its passes over it
type Spin = (data: buffer, passes: number) -> number

export type Modules = {
	client: { _frame: Frame }, -- A rendered frame, the owner's prediction inside it
	predict: { frame: Advance },
	rigs: {
		_layer: Layer, -- The drawn rigs' aim, lean and legs, at each simulation step
		_draw: Draw, -- One rig's draw and its Animate calls, its root's move left to the frame's end
		frame: Finish, -- The frame's end: what waited past the caps, the pool's builds, and the one BulkMoveTo
		_animate: Load, -- A rig's tracks loaded, at its first draw
		_build: Build, -- A new clone of the rig template
	},
	interpolate: {
		receive: Receive, -- A relay block taken in
		pose: Sample, -- A remote slot's drawn state at the render time
	},
	animate: { pose: Play }, -- A rig's track picked and played
}

-- Milliseconds each part of the remote work took a frame
export type Parts = {
	pose: { number }, -- Interpolate.pose inside the frame
	draw: { number }, -- Rigs._draw and Rigs.frame inside it
	receive: { number }, -- The receives since the frame before ended
	layer: { number }, -- The layers since then
}

-- What one window measured, a sample a frame. A frame's counts hold what ran in its delta, from the frame before
-- beginning to its own start, and its times what its remote work holds
export type Window = {
	label: string,
	split: boolean, -- Whether it wrapped the pose, the draw, the first draws and the track switches too
	remote: { number }, -- Milliseconds of remote-character work each frame
	frames: { number }, -- Milliseconds of each frame, its delta
	rates: { number }, -- Frames a second at each frame, from its delta
	drawn: { number }, -- The remote rigs drawn as each frame ended
	steps: { number }, -- Simulation steps, the layers, in each frame's delta
	blocks: { number }, -- Relay blocks received in each frame's delta
	heap: { number }, -- Kilobytes of Luau heap as each frame began
	parts: Parts, -- With the split only, as are the three after it
	loads: { number }, -- Rigs._animate calls in each frame's delta, each a rig's first draw
	clones: { number }, -- Rigs._build calls in it, each a new rig
	switches: { number }, -- Track switches in it
	native: number, -- Microseconds a pass of the native loop at its median sample, 0 until timed
	interpreted: number, -- And of the interpreted loop
	pending: number, -- Seconds the layers and receives took since the last frame ended
	receiving: number, -- Seconds of that the receives took
	predicted: number, -- Seconds the owner's prediction took inside the frame running
	posing: number, -- Seconds Interpolate.pose took inside the frame running
	drawing: number, -- Seconds Rigs._draw and Rigs.frame took inside the frame running
	stepping: number, -- Layers since the last frame began
	blocking: number, -- Receives since the last frame began
	loading: number, -- Rigs._animate calls since the last frame began
	cloning: number, -- Rigs._build calls since then
	switching: number, -- Track switches since then
	restore: () -> (), -- Puts every wrapped member back as the window found it
}

-- What one set of slow frames held, each a count of its frames
type Held = { frames: number, blocks: number, drops: number, firsts: number, switches: number }

-- What the pass over a window's frames, each by its place, gives the line
type Paired = {
	blockRemote: { number }, -- The remote work of each frame with a relay block in its delta
	blockFrames: { number }, -- And its frame time
	otherRemote: { number }, -- Those of each frame without one
	otherFrames: { number },
	rest: { number }, -- The remote work each frame's parts leave, with the split
	busy: number, -- The window's median track switches a frame, 0 without the split
	pastMedian: Held, -- What the frames past the median's multiple held
	pastHitch: Held, -- And those past the threshold
}

local MODULES: Modules =
	{ client = Client, predict = Predict, rigs = Rigs, interpolate = Interpolate, animate = Animate }

local Running: boolean = false
local Drawn: { [number]: true } = {} -- Each remote rig's slot client:onSpawned named and client:onDespawned hasn't ended
local Count: number = 0 -- How many slots Drawn holds
local Open: Window? = nil -- The window measuring, nil between windows
local Ending: thread? = nil -- The open window's own deadline, which ends it if the attribute never clears

local Cost = {}

-- The samples at a share by nearest rank, in milliseconds as the line prints them. It sorts the list in place
local function figure(samples: { number }, share: number): string
	return string.format(TIME_FIGURE, Frames.percentile(samples, share))
end

--[[
    Opens a window over the modules' tables: each frame's remote work is the
    frame less the owner's prediction inside it, plus the layers and the
    relay's receives since the frame before, read with the clock given, with
    the rigs drawn as count gives them and the heap as memory gives it. With
    the split it also times the pose inside each frame, and the draws with
    the pool's frame end, and counts first draws and track switches. Each
    wrapped member hands its arguments to the one it replaced, and the
    window's restore puts them back
--]]

function Cost.open(
	label: string,
	modules: Modules,
	clock: () -> number,
	count: () -> number,
	memory: () -> number
): Window
	local client: index<Modules, "client"> = modules.client
	local predict: index<Modules, "predict"> = modules.predict
	local rigs: index<Modules, "rigs"> = modules.rigs
	local interpolate: index<Modules, "interpolate"> = modules.interpolate
	local animate: index<Modules, "animate"> = modules.animate

	local frame: Frame = client._frame
	local advance: Advance = predict.frame
	local layer: Layer = rigs._layer
	local receive: Receive = interpolate.receive
	local sample: Sample = interpolate.pose
	local draw: Draw = rigs._draw
	local finish: Finish = rigs.frame
	local load: Load = rigs._animate
	local build: Build = rigs._build
	local play: Play = animate.pose

	local function restore()
		client._frame = frame
		predict.frame = advance
		rigs._layer = layer
		interpolate.receive = receive
		interpolate.pose = sample
		rigs._draw = draw
		rigs.frame = finish
		rigs._animate = load
		rigs._build = build
		animate.pose = play
	end

	local parts: Parts = { pose = {}, draw = {}, receive = {}, layer = {} }
	local window: Window = {
		label = label,
		split = SPLIT,
		remote = {},
		frames = {},
		rates = {},
		drawn = {},
		steps = {},
		blocks = {},
		heap = {},
		parts = parts,
		loads = {},
		clones = {},
		switches = {},
		native = 0,
		interpreted = 0,
		pending = 0,
		receiving = 0,
		predicted = 0,
		posing = 0,
		drawing = 0,
		stepping = 0,
		blocking = 0,
		loading = 0,
		cloning = 0,
		switching = 0,
		restore = restore,
	}

	client._frame = function (self: any, dt: number)
		-- What ran since the frame before began lies in this one's delta, so those counts close as it begins
		local kilobytes: number = memory()
		local steps: number, blocks: number = window.stepping, window.blocking
		local loads: number, clones: number, switches: number = window.loading, window.cloning, window.switching
		window.stepping, window.blocking, window.loading, window.cloning, window.switching = 0, 0, 0, 0, 0
		window.predicted, window.posing, window.drawing = 0, 0, 0

		local started: number = clock()
		frame(self, dt)

		local spent: number = clock() - started - window.predicted + window.pending
		table.insert(window.remote, spent * MILLISECONDS)
		table.insert(window.frames, dt * MILLISECONDS)
		table.insert(window.drawn, count())
		table.insert(window.steps, steps)
		table.insert(window.blocks, blocks)
		table.insert(window.heap, kilobytes)

		if dt > 0 then
			table.insert(window.rates, Frames.rate(dt))
		end

		if SPLIT then
			table.insert(parts.pose, window.posing * MILLISECONDS)
			table.insert(parts.draw, window.drawing * MILLISECONDS)
			table.insert(parts.receive, window.receiving * MILLISECONDS)
			table.insert(parts.layer, (window.pending - window.receiving) * MILLISECONDS)
			table.insert(window.loads, loads)
			table.insert(window.clones, clones)
			table.insert(window.switches, switches)
		end

		window.pending = 0
		window.receiving = 0
	end

	predict.frame = function (dt: number)
		local started: number = clock()
		advance(dt)
		window.predicted += clock() - started
	end

	rigs._layer = function (self: any)
		local started: number = clock()
		layer(self)
		window.pending += clock() - started
		window.stepping += 1
	end

	interpolate.receive = function (data: buffer)
		local started: number = clock()
		receive(data)

		local spent: number = clock() - started
		window.pending += spent
		window.receiving += spent
		window.blocking += 1
	end

	if not SPLIT then
		return window
	end

	-- A pose or a draw outside a frame is timed too, and the next frame's start drops it, as no remote work holds it
	interpolate.pose = function (slot: number, into: any): (boolean, number, number, number)
		local started: number = clock()
		local shown: boolean, pitch: number, headYaw: number, headPitch: number = sample(slot, into)
		window.posing += clock() - started

		return shown, pitch, headYaw, headPitch
	end

	rigs._draw = function (self: any, entry: any, state: any, distance: number, pitch: number, back: number)
		local started: number = clock()
		draw(self, entry, state, distance, pitch, back)
		window.drawing += clock() - started
	end

	-- The frame's end joins the draw, a draw it grants counted once, inside it
	rigs.frame = function (self: any)
		local started: number = clock()
		local drawing: number = window.drawing
		finish(self)
		window.drawing = drawing + clock() - started
	end

	rigs._animate = function (self: any, entry: any): any
		window.loading += 1

		return load(self, entry)
	end

	rigs._build = function (self: any): any
		window.cloning += 1

		return build(self)
	end

	-- A call that leaves another track playing is a switch, a rig's first track among them
	animate.pose = function (animated: any, state: any, full: boolean, speed: number?)
		local playing: any = animated.playing
		play(animated, state, full, speed)

		if animated.playing ~= playing then
			window.switching += 1
		end
	end

	return window
end

--[[
    Times the native and the interpreted loop in turn, a sample of each at a
    time over one buffer read with the clock given, and keeps each one's
    microseconds a pass at its median sample in the window
--]]

function Cost.loops(window: Window, clock: () -> number, native: Spin, interpreted: Spin)
	local data: buffer = buffer.create(LOOP_BYTES)
	local nativeTimes: { number } = {}
	local interpretedTimes: { number } = {}

	for index: number = 1, LOOP_SAMPLES do
		local began: number = clock()
		native(data, LOOP_PASSES)

		local between: number = clock()
		interpreted(data, LOOP_PASSES)

		local ended: number = clock()
		nativeTimes[index] = (between - began) * MICROSECONDS / LOOP_PASSES
		interpretedTimes[index] = (ended - between) * MICROSECONDS / LOOP_PASSES
	end

	window.native = Frames.percentile(nativeTimes, MEDIAN)
	window.interpreted = Frames.percentile(interpretedTimes, MEDIAN)
end

-- The samples' sum
local function total(samples: { number }): number
	local sum: number = 0
	for _, value: number in samples do
		sum += value
	end

	return sum
end

-- Counts a slow frame into its set: a relay block in its delta, a heap drop since the frame before, and with the
-- split a first draw and more track switches than the window's median
local function hold(into: Held, window: Window, index: number, busy: number)
	into.frames += 1

	if window.blocks[index] > 0 then
		into.blocks += 1
	end

	if Frames.dropped(window.heap, index) then
		into.drops += 1
	end

	if window.split and window.loads[index] + window.clones[index] > 0 then
		into.firsts += 1
	end

	if window.split and window.switches[index] > busy then
		into.switches += 1
	end
end

--[[
    Pairs each frame's samples by their place, before any list is sorted:
    the frames with a relay block apart from the rest, each frame's rest
    with the split, and what the slow frames held
--]]

local function pair(window: Window): Paired
	local split: boolean = window.split
	local busy: number = 0
	if split then
		busy = Frames.percentile(table.clone(window.switches), MEDIAN)
	end

	local paired: Paired = {
		blockRemote = {},
		blockFrames = {},
		otherRemote = {},
		otherFrames = {},
		rest = {},
		busy = busy,
		pastMedian = { frames = 0, blocks = 0, drops = 0, firsts = 0, switches = 0 },
		pastHitch = { frames = 0, blocks = 0, drops = 0, firsts = 0, switches = 0 },
	}

	local parts: Parts = window.parts
	for index: number, remote: number in window.remote do
		local frame: number = window.frames[index]

		if window.blocks[index] > 0 then
			table.insert(paired.blockRemote, remote)
			table.insert(paired.blockFrames, frame)
		else
			table.insert(paired.otherRemote, remote)
			table.insert(paired.otherFrames, frame)
		end

		if split then
			local timed: number = parts.pose[index] + parts.draw[index] + parts.receive[index] + parts.layer[index]
			table.insert(paired.rest, remote - timed)
		end
	end

	local slow: Slow = Frames.slow(window.frames)
	for _, index: number in slow.pastMedian do
		hold(paired.pastMedian, window, index, busy)
	end

	for _, index: number in slow.pastHitch do
		hold(paired.pastHitch, window, index, busy)
	end

	return paired
end

-- What a set of slow frames held, as the line prints it
local function heldOf(set: Held, past: string, split: boolean, busy: number): string
	local held: string = `of the {set.frames} past {past}, {set.blocks} had a relay block`
	if not split then
		return `{held} and {set.drops} followed a heap drop`
	end

	local switched: string = `{set.switches} more than {busy} track switches`

	return `{held}, {set.drops} followed a heap drop, {set.firsts} had a first draw and {switched}`
end

--[[
    The figures after the ones every window has printed: the remote work's
    parts with the split, the simulation steps a frame, the frames with a
    relay block apart from the rest, the two loops, the first draws and the
    track switches with the split, and what each set of hitches held
--]]

local function added(window: Window, labels: string, paired: Paired): { string }
	local split: boolean = window.split
	local median: string = `p{math.round(MEDIAN * PERCENT)}`
	local share: string = `p{math.round(BLOCKS * PERCENT)}`

	local steps: string = `{Frames.percentile(window.steps, MEDIAN)}, max {Frames.percentile(window.steps, WORST)}`
	local blockRemote: string = figure(paired.blockRemote, BLOCKS)
	local withBlock: string = `{#paired.blockFrames} frames with a relay block at remote ms {share} {blockRemote}`
	local blockFrame: string = `frame ms {share} {figure(paired.blockFrames, BLOCKS)}`
	local others: string = `{figure(paired.otherRemote, BLOCKS)} and {figure(paired.otherFrames, BLOCKS)}`

	local ratio: number = 0
	if window.native > 0 then
		ratio = window.interpreted / window.native
	end

	local native: string = `{median} {string.format(TIME_FIGURE, window.native)}`
	local interpreted: string = `interpreted {string.format(TIME_FIGURE, window.interpreted)}`
	local loops: string = `{native}, {interpreted}, interpreted/native {string.format(RATIO_FIGURE, ratio)}`

	local stepped: string = `simulation steps a frame {median} {steps}`
	local blocks: string = `{withBlock} and {blockFrame}, {#paired.otherFrames} without at {others}`
	local looped: string = `native loop µs a pass of {LOOP_BYTES} B {loops}`
	local spiked: string = heldOf(paired.pastMedian, Frames.pastMedian, split, paired.busy)
	local hitched: string = heldOf(paired.pastHitch, Frames.pastHitch, split, paired.busy)

	if not split then
		return { stepped, blocks, looped, spiked, hitched, UNSPLIT }
	end

	local parts: Parts = window.parts
	local pose: string = `pose {Frames.spread(parts.pose, PERCENTILES, TIME_FIGURE)}`
	local draw: string = `draw {Frames.spread(parts.draw, PERCENTILES, TIME_FIGURE)}`
	local receive: string = `receive {Frames.spread(parts.receive, PERCENTILES, TIME_FIGURE)}`
	local layer: string = `layer {Frames.spread(parts.layer, PERCENTILES, TIME_FIGURE)}`
	local rest: string = `rest {Frames.spread(paired.rest, PERCENTILES, TIME_FIGURE)}`

	local loads: string = `{total(window.loads)} track loads, at most {Frames.percentile(window.loads, WORST)} a frame`
	local clones: string = `{total(window.clones)} clones, at most {Frames.percentile(window.clones, WORST)} a frame`
	local switches: string = Frames.spread(window.switches, SWITCHES, COUNT_FIGURE)
	local switched: string = `{switches}/{Frames.percentile(window.switches, WORST)}`

	return {
		`remote parts ms {labels} {pose}, {draw}, {receive}, {layer}, {rest}`,
		stepped,
		blocks,
		looped,
		`first draws {loads}, and {clones}`,
		`track switches a frame {Frames.labels(SWITCHES)}/max {switched}`,
		spiked,
		hitched,
	}
end

--[[
    A window's line and whether it measured anything: the player, how they
    play, the frames timed, the frame rate at its low share, the rigs drawn
    and the remote work's spread against its limit, then the frame time's
    spread and worst, the remote work's worst, and the hitches past the
    median's multiple and past the threshold, with the figures added after
    those. A window that timed no frame is refused, since Tread's client
    then reaches its frame some way the wrapper never replaced
--]]

function Cost.summary(window: Window, player: string, input: string): (boolean, string)
	local frames: number = #window.remote
	if frames == 0 then
		return false, `{player} on {input}: refused, no Client._frame call was timed, so the window measured nothing`
	end

	local paired: Paired = pair(window)
	local spiked: number = paired.pastMedian.frames
	local hitched: number = paired.pastHitch.frames

	local labels: string = Frames.labels(PERCENTILES)
	local counts: string = Frames.counted(frames, window.rates)
	local drawn: string = `rigs drawn p{math.round(DRAWN * PERCENT)} {Frames.percentile(window.drawn, DRAWN)}`
	local spread: string = Frames.spread(window.remote, PERCENTILES, TIME_FIGURE)
	local remote: string = `remote ms {labels} {spread} against {LIMIT} ms`
	local frameTimes: string = Frames.times(window.frames)
	local worst: string = `remote ms max {figure(window.remote, WORST)}`
	local hitches: string = Frames.hitches(spiked, hitched, #window.frames)
	local measured: string = `{counts}, {drawn}, {remote}, {frameTimes}, {worst}, {hitches}`

	return true, `{player} on {input}: {measured}, {table.concat(added(window, labels, paired), ", ")}`
end

-- How the player plays, as the line names it
local function inputOf(): string
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "touch"
	end

	return "mouse"
end

-- The remote rigs drawn now, which the parallel probes stand in for too
function Cost.drawn(): number
	return Count
end

--[[
    Ends the open window: every wrapped member back, its deadline
    cancelled, the two loops timed, and its line sent, marked unmeasured
    with the failure when one ended it
--]]

local function finish(failure: string?)
	local window: Window? = Open
	if not window then
		return
	end

	Open = nil
	window.restore()

	local ending: thread? = Ending
	if ending then
		Ending = nil
		task.cancel(ending)
	end

	-- Timed with every wrapper back, so no frame the window measured holds the loops
	Cost.loops(window, os.clock, NativeLoop, InterpretedLoop)

	local measured: boolean, line: string = Cost.summary(window, Player.Name, inputOf())
	if failure then
		measured = false
		line = `{line}, then {failure}`
	end

	Network.clientCost.fire(window.label, measured, line)
end

-- The open window's deadline passed with the attribute still set
local function expire()
	Ending = nil
	finish(`it passed its {LONGEST} s deadline with {ATTRIBUTE} still set`)
end

-- The attribute changed: a window it no longer names ends, and a label it now holds opens one
local function changed()
	local label: any = Workspace:GetAttribute(ATTRIBUTE)
	local window: Window? = Open
	if window and label ~= window.label then
		finish(nil)
	end

	if type(label) == "string" and not Open then
		Open = Cost.open(label, MODULES, os.clock, Cost.drawn, gcinfo)
		Ending = task.delay(LONGEST, expire)
	end
end

--[[
    Starts the cost once a client, in the frame Tread's client starts, so
    it counts every remote rig drawn. Its three listeners live for the
    client session, and each window's wrappers go when it ends
--]]

function Cost.start(client: Tread.Client)
	if Running then
		error("Cost.start runs once a client, and it has already run", 2)
	end

	Running = true

	client:onSpawned(function (slot: Slot, _: Model)
		if slot.player ~= Player and not Drawn[slot.id] then
			Drawn[slot.id] = true
			Count += 1
		end
	end)

	client:onDespawned(function (slot: Slot)
		if Drawn[slot.id] then
			Drawn[slot.id] = nil
			Count -= 1
		end
	end)

	Workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(changed)
end

return Cost
