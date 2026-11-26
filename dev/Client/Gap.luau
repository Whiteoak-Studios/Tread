--[[
    The gap check's client side: while the Workspace attribute names a
    window, each frame's render time and whether the target's rig is drawn,
    its reveal's arrival, and where its frozen rig stood and was thawed to
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

type Slot = Tread.Slot
type Capture = GapLine.Capture
type Place = GapLine.Place

-- The window recording: the label the server opened it with, what it holds, and whether a reveal of the target came
type Window = {
	label: string,
	capture: Capture,
	arrived: boolean,
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

	Open = {
		label = label,
		capture = { frames = {}, arrival = nil, frozen = frozen, thawed = nil, cut = 0 },
		arrived = false,
	}
end

-- The slot attribute changed: the target it names, its frozen rig forgotten
local function retarget()
	local slot: any = Workspace:GetAttribute(GapLine.SLOT)
	Target = type(slot) == "number" and slot or nil
	Stood = nil
end

--[[
    Each frame while a window is open, after Tread's client has drawn it:
    its render time and whether the target's rig stands drawn, the frame a
    reveal of the target arrived before marked, and frames past what the
    line can carry counted as cut
--]]

local function record(client: Tread.Client)
	local window: Window? = Open
	if not window then
		return
	end

	local capture: Capture = window.capture
	if #capture.frames >= GapLine.LINE_BYTES then
		capture.cut += 1
		return
	end

	local target: number? = Target
	local drawn: boolean = target ~= nil and Drawn[target] == true
	table.insert(capture.frames, { render = client:getRenderTime(), drawn = drawn })

	if window.arrived and capture.arrival == nil then
		capture.arrival = #capture.frames
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
		if window and window.capture.thawed == nil then
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
		local window: Window? = Open
		if window and slot == Target then
			window.arrived = true
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
