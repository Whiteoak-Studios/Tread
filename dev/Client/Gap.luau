--[[
    The gap check's client side: each window's frames, by render time and
    whether the target's rig is drawn, from a few ticks before its Workspace
    attribute opens it, with its reveal's arrival and its frozen rig's places
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages
local Player = Players.LocalPlayer

local Tread = require(Packages.Tread)

local Network = require(ReplicatedStorage.Shared.Network.Client)

-- Requiring it finds the module Tread's client already started, whose reveals it hears
local Interpolate = require(Packages.Tread.Client.Interpolate)

local GapLine = require(ReplicatedStorage.Shared.Dev.GapLine)

local PREROLL: number = require(script.Parent.Config).gap.preroll -- Relay ticks of frames held before a window opens

type Slot = Tread.Slot
type Capture = GapLine.Capture
type Frame = GapLine.Frame
type Place = GapLine.Place
type Thaw = GapLine.Thaw

-- The window recording: the label the server opened it with, and what it holds
type Window = {
	label: string,
	capture: Capture,
}

-- Where the target's rig stood when a hide froze it, with that rig
type Frozen = {
	place: Place,
	rig: Model,
}

local Running: boolean = false
local Target: number? = nil -- The slot the server names on its slot attribute, nil while it names none
local Rigs: { [number]: Model } = {} -- Each remote slot's rig as its last spawn handed it
local Drawn: { [number]: true } = {} -- Each remote slot onSpawned named and onDespawned hasn't ended
local Stood: Frozen? = nil -- The target's frozen rig, nil while none stands
local Open: Window? = nil -- The window recording, nil between windows
local Held: { GapLine.Held } = {} -- The frames recorded while no window is open, the last PREROLL ticks of them
local Arrived: boolean = false -- Whether a reveal of the target came since the last frame recorded
local Pending: Thaw? = nil -- A thaw heard while no window is open, until a frame held carries it

local Gap = {}

-- Where a rig's root stands across the ground, nil for one out of the Workspace
local function placeOf(rig: Model): Place?
	local root: BasePart? = rig.PrimaryPart
	if not root or not rig:IsDescendantOf(Workspace) then
		return nil
	end

	return { x = root.Position.X, z = root.Position.Z }
end

-- Sends the open window's line and ends it, marked unmeasured when frames were cut
local function finish()
	local window: Window? = Open
	if not window then
		return
	end

	Open = nil
	Network.clientCost.fire(window.label, window.capture.cut == 0, GapLine.encode(window.capture))
end

-- The window attribute changed: a window it no longer names ends, and a label it now holds opens one
local function changed()
	local label: any = Workspace:GetAttribute(GapLine.ATTRIBUTE)
	local window: Window? = Open
	if window and label ~= window.label then
		finish()
	end

	if type(label) ~= "string" or Open then
		return
	end

	local frozen: Place? = nil
	local stood: Frozen? = Stood
	if stood then
		frozen = stood.place
	end

	Open = { label = label, capture = GapLine.begin(Held, frozen, Pending) }
	table.clear(Held)
	Pending = nil
end

-- The slot attribute changed: the target it names, and everything heard of the last one forgotten
local function retarget()
	local slot: any = Workspace:GetAttribute(GapLine.SLOT)
	Target = type(slot) == "number" and slot or nil
	Stood = nil
	table.clear(Held)
	Arrived = false
	Pending = nil
end

--[[
    Each frame after Tread's client has drawn it, its render time and
    whether the target's rig stands drawn: into the open window, the frame a
    reveal of the target arrived before marked and frames past what the line
    can carry counted as cut, or held while a target is named and no window
--]]

local function record(client: Tread.Client)
	local target: number? = Target
	local frame: Frame = { render = client:getRenderTime(), drawn = target ~= nil and Drawn[target] == true }
	local arrived: boolean = Arrived
	Arrived = false

	local window: Window? = Open
	if window then
		local capture: Capture = window.capture
		if #capture.frames >= GapLine.LINE_BYTES then
			capture.cut += 1
			return
		end

		table.insert(capture.frames, frame)
		if arrived and capture.arrival == nil then
			capture.arrival = #capture.frames
		end
	elseif target ~= nil then
		local thaw: Thaw? = Pending
		Pending = nil
		GapLine.hold(Held, { frame = frame, arrived = arrived, thaw = thaw }, PREROLL)
	end
end

--[[
    Starts the recorder once a client, in the frame Tread's client starts,
    so it hears every rig drawn. Its listeners live for the client session
--]]

function Gap.start(client: Tread.Client)
	if Running then
		error("Gap.start runs once a client, and it has already run", 2)
	end

	Running = true

	-- A thaw spawns the rig its hide froze, once its first pose has moved it to where the target is
	client:onSpawned(function (slot: Slot, rig: Model)
		if slot.player == Player then
			return
		end

		Rigs[slot.id] = rig
		Drawn[slot.id] = true

		local stood: Frozen? = Stood
		if slot.id ~= Target or not stood or stood.rig ~= rig then
			return
		end

		Stood = nil

		local window: Window? = Open
		if not window then
			Pending = { from = stood.place, to = placeOf(rig) }
		elseif window.capture.thawed == nil then
			window.capture.thawed = placeOf(rig)
		end
	end)

	-- A hide anti-ESP made leaves the rig standing in the Workspace, frozen; any other takes it out
	client:onDespawned(function (slot: Slot)
		Drawn[slot.id] = nil
		if slot.id ~= Target then
			return
		end

		local rig: Model? = Rigs[slot.id]
		local place: Place? = nil
		if rig then
			place = placeOf(rig)
		end

		if rig and place then
			Stood = { place = place, rig = rig }
		else
			Stood = nil
		end
	end)

	Interpolate.onReveal(function (slot: number)
		if slot == Target then
			Arrived = true
		end
	end)

	-- After Tread's own frame, which draws just ahead of Camera priority
	RunService.PreRender:Connect(function ()
		record(client)
	end)

	Workspace:GetAttributeChangedSignal(GapLine.SLOT):Connect(retarget)
	Workspace:GetAttributeChangedSignal(GapLine.ATTRIBUTE):Connect(changed)
	retarget()
end

return Gap
