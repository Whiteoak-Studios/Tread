--[[
    G5's client side: while the Workspace attribute names a window, times
    Tread's remote-character work each frame through its module tables and
    counts the rigs drawn, then sends the window's line over the dev scope
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
local Client = require(Packages.Tread.Client)
local Interpolate = require(Packages.Tread.Client.Interpolate)
local Predict = require(Packages.Tread.Client.Predict)
local Rigs = require(Packages.Tread.Client.Rigs)

local CostConfig = require(script.Parent.Config).cost

local ATTRIBUTE: string = CostConfig.attribute
local LONGEST: number = CostConfig.longest
local LIMIT: number = CostConfig.limit
local PERCENTILES: { number } = CostConfig.percentiles
local FPS: number = CostConfig.fps
local DRAWN: number = CostConfig.drawn
local MILLISECONDS: number = 1000 -- A second's, which the remote work prints in
local PERCENT: number = 100 -- Turns a share into the number a pNN label shows
local RATE_FIGURE: string = "%.1f" -- Frames a second as the line prints them
local TIME_FIGURE: string = "%.3f" -- Milliseconds as the line prints them

type Slot = Tread.Slot

-- The members Cost wraps, each a function its module's table holds and Tread's client looks up there at each call
type Frame = (self: any, dt: number) -> ()
type Advance = (dt: number) -> ()
type Layer = (self: any) -> ()
type Receive = (data: buffer) -> ()

export type Modules = {
	client: { _frame: Frame }, -- A rendered frame, the owner's prediction inside it
	predict: { frame: Advance },
	rigs: { _layer: Layer }, -- The drawn rigs' aim, lean and legs, at each simulation step
	interpolate: { receive: Receive }, -- A relay block taken in
}

-- What one window measured, a sample a frame
export type Window = {
	label: string,
	remote: { number }, -- Milliseconds of remote-character work each frame
	rates: { number }, -- Frames a second at each frame, from its delta
	drawn: { number }, -- The remote rigs drawn as each frame ended
	pending: number, -- Seconds the layers and receives took since the last frame ended
	predicted: number, -- Seconds the owner's prediction took inside the frame running
	restore: () -> (), -- Puts every wrapped member back as the window found it
}

local MODULES: Modules = { client = Client, predict = Predict, rigs = Rigs, interpolate = Interpolate }

local Running: boolean = false
local Drawn: { [number]: true } = {} -- Each remote rig's slot client:onSpawned named and client:onDespawned hasn't ended
local Count: number = 0 -- How many slots Drawn holds
local Open: Window? = nil -- The window measuring, nil between windows
local Ending: thread? = nil -- The open window's own deadline, which ends it if the attribute never clears

local Cost = {}

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
local function percentile(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

--[[
    Opens a window over the modules' tables: each frame's remote work is the
    frame less the owner's prediction inside it, plus the layers and the
    relay's receives since the frame before, read with the clock given, with
    the rigs drawn as count gives them. Each wrapped member hands its
    arguments to the one it replaced, and the window's restore puts them back
--]]

function Cost.open(label: string, modules: Modules, clock: () -> number, count: () -> number): Window
	local client: { _frame: Frame } = modules.client
	local predict: { frame: Advance } = modules.predict
	local rigs: { _layer: Layer } = modules.rigs
	local interpolate: { receive: Receive } = modules.interpolate

	local frame: Frame = client._frame
	local advance: Advance = predict.frame
	local layer: Layer = rigs._layer
	local receive: Receive = interpolate.receive

	local function restore()
		client._frame = frame
		predict.frame = advance
		rigs._layer = layer
		interpolate.receive = receive
	end

	local window: Window = {
		label = label,
		remote = {},
		rates = {},
		drawn = {},
		pending = 0,
		predicted = 0,
		restore = restore,
	}

	client._frame = function (self: any, dt: number)
		local started: number = clock()
		window.predicted = 0
		frame(self, dt)

		local spent: number = clock() - started - window.predicted + window.pending
		window.pending = 0
		table.insert(window.remote, spent * MILLISECONDS)
		table.insert(window.drawn, count())

		if dt > 0 then
			table.insert(window.rates, 1 / dt)
		end
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
	end

	interpolate.receive = function (data: buffer)
		local started: number = clock()
		receive(data)
		window.pending += clock() - started
	end

	return window
end

--[[
    A window's line and whether it measured anything: the player, how they
    play, the frames timed, the frame rate at its low share, the rigs drawn
    and the remote work's spread against its limit. A window that timed no
    frame is refused, since Tread's client then reaches its frame some way
    the wrapper never replaced
--]]

function Cost.summary(window: Window, player: string, input: string): (boolean, string)
	local frames: number = #window.remote
	if frames == 0 then
		return false, `{player} on {input}: refused, no Client._frame call was timed, so the window measured nothing`
	end

	local labels: { string } = {}
	local figures: { string } = {}
	for _, share: number in PERCENTILES do
		table.insert(labels, `p{math.round(share * PERCENT)}`)
		table.insert(figures, string.format(TIME_FIGURE, percentile(window.remote, share)))
	end

	local rate: string = string.format(RATE_FIGURE, percentile(window.rates, FPS))
	local counts: string = `{frames} frames, FPS p{math.round(FPS * PERCENT)} {rate}`
	local drawn: string = `rigs drawn p{math.round(DRAWN * PERCENT)} {percentile(window.drawn, DRAWN)}`
	local remote: string = `remote ms {table.concat(labels, "/")} {table.concat(figures, "/")} against {LIMIT} ms`

	return true, `{player} on {input}: {counts}, {drawn}, {remote}`
end

-- How the player plays, as the line names it
local function inputOf(): string
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "touch"
	end

	return "mouse"
end

-- The remote rigs drawn now
local function counted(): number
	return Count
end

--[[
    Ends the open window: every wrapped member back, its deadline
    cancelled, and its line sent, marked unmeasured with the failure when
    one ended it
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
		Open = Cost.open(label, MODULES, os.clock, counted)
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
