--[[
    The dev client's replay of the clips the dev server sends: each clip's
    parts put back together, played on a key with pause, slow motion, ticks,
    seeks and stop, a label of where it stands, and its end reported back
--]]

--!strict
local Replay = {}
Replay.__index = Replay

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Packages = ReplicatedStorage.Packages
local Player = Players.LocalPlayer

local Tread = require(Packages.Tread)

local Network = require(ReplicatedStorage.Shared.Network.Client)

local ClipParts = require(ReplicatedStorage.Shared.Dev.ClipParts)
local Clock = require(script.Parent.Clock)

local ReplayConfig = require(script.Parent.Config).replay

local PLAY: Enum.KeyCode = ReplayConfig.keys.play
local SLOWER: Enum.KeyCode = ReplayConfig.keys.slower
local BACK: Enum.KeyCode = ReplayConfig.keys.back
local FORWARD: Enum.KeyCode = ReplayConfig.keys.forward
local REWIND: Enum.KeyCode = ReplayConfig.keys.rewind
local SKIP: Enum.KeyCode = ReplayConfig.keys.skip
local STOP: Enum.KeyCode = ReplayConfig.keys.stop
local SPEEDS: { number } = ReplayConfig.speeds
local SEEK: number = ReplayConfig.seek
local LABEL_WAIT: number = ReplayConfig.labelWait
local READY: string = ReplayConfig.ready
local PLAYING: string = ReplayConfig.playing
local PAUSED: string = ReplayConfig.paused
local NOT_PAUSED: string = "" -- What the label shows in the paused text's place while the clip plays
local ONE_TICK: number = 1 -- The relay ticks a single step moves
local WRAP: number = 2 ^ 16 -- The values a frame's u16 relay tick holds

type Fields = {
	_client: Tread.Client,
	_relay: number, -- The shared table's relay rate, ticks a second
	_assembly: ClipParts.ClipParts, -- The parts of the clip arriving
	_clip: ClipParts.Clip?, -- The newest whole clip, which the play key plays
	_playback: Tread.Playback?, -- The clip playing, nil while none is
	_clock: Clock.Clock?, -- What the clip playing renders at
	_reported: boolean, -- Whether the server has been told this playback ended
	_screen: ScreenGui,
	_label: TextLabel,
	_stopListening: (() -> ())?, -- Disconnects the clip listener, nil once destroyed
	_input: RBXScriptConnection?, -- The keys, nil once destroyed
}

-- Seconds from a clip's keyframe to the newest frame of either list, the time its playback runs to
local function lengthOf(clip: ClipParts.Clip, relay: number): number
	local keyframe: buffer = clip.ticks[1]
	local start: number = Tread.decode(Tread.CODEC_VERSION, "keyframe", keyframe).tick
	local ahead: number = 0

	local lists: { { buffer } } = { clip.ticks, clip.withheld }
	for _, list: { buffer } in lists do
		local newest: buffer? = list[#list]
		if newest and newest ~= keyframe then
			local tick: number = Tread.decode(Tread.CODEC_VERSION, "tap", newest).tick
			ahead = math.max(ahead, (tick - start) % WRAP)
		end
	end

	return ahead / relay
end

--[[
    The replay for a client: its label, hidden until a clip arrives, and
    the clip listener and the keys connected, both of which destroy
    disconnects. It waits at boot for the PlayerGui
--]]

function Replay.new(client: Tread.Client, shared: Tread.Shared): Self
	-- Boot-time wait: the PlayerGui may not have arrived when the client's scripts start
	local playerGui = Player:WaitForChild("PlayerGui", LABEL_WAIT) :: PlayerGui?
	if not playerGui then
		error(`The dev replay's label found no PlayerGui within {LABEL_WAIT} s`)
	end

	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = "DevReplay"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	local label: TextLabel = Instance.new("TextLabel")
	label.Name = "Clip"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.04)
	label.Size = UDim2.fromOffset(300, 28)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 16
	label.ZIndex = 1
	label.Visible = false
	label.Parent = screen

	local self: Self = setmetatable({
		_client = client,
		_relay = shared.rates.relay,
		_assembly = ClipParts.new(),
		_clip = nil :: ClipParts.Clip?,
		_playback = nil :: Tread.Playback?,
		_clock = nil :: Clock.Clock?,
		_reported = false,
		_screen = screen,
		_label = label,
		_stopListening = nil :: (() -> ())?,
		_input = nil :: RBXScriptConnection?,
	}, Replay)

	self._stopListening = Network.clip.on(function (withheld: boolean, index: number, total: number, bytes: buffer)
		self:_part(withheld, index, total, bytes)
	end)

	self._input = UserInputService.InputBegan:Connect(function (input: InputObject, processed: boolean)
		if not processed then
			self:_press(input.KeyCode)
		end
	end)

	return self
end

--[[
    Draws this frame of the clip playing, from the dev client's own
    PreRender handler ahead of its camera, so the camera reads the clip's
    eye this frame. Tells the server once the clip reaches its end, and
    brings the label up to date
--]]

function Replay.frame(self: Self, dt: number)
	local playback: Tread.Playback? = self._playback
	local clock: Clock.Clock? = self._clock
	if playback and clock then
		playback:render(clock:advance(dt))

		if clock:ended() then
			self:_report(false)
		end
	end

	self:_show()
end

--[[
    Ends the replay: a clip still playing stopped and reported, the clip
    listener and the keys disconnected, and the label taken away
--]]

function Replay.destroy(self: Self)
	self:_stop()

	local stopListening: (() -> ())? = self._stopListening
	if stopListening then
		stopListening()
		self._stopListening = nil
	end

	local input: RBXScriptConnection? = self._input
	if input then
		input:Disconnect()
		self._input = nil
	end

	self._screen:Destroy()
end

--[[
    Keeps a part as it arrives, and once both lists have ended keeps the
    clip they make as the one the play key plays. A part refused or a part
    missing is warned, and the clip it belonged to dropped
--]]

function Replay._part(self: Self, withheld: boolean, index: number, total: number, bytes: buffer)
	local kept: boolean, refusal: string? = self._assembly:add(withheld, index, total, bytes)
	if not kept then
		warn(`The dev replay dropped a clip: {refusal}`)
		self._assembly = ClipParts.new()
		return
	end

	if not self._assembly:ready() then
		return
	end

	local took: boolean, result: string | ClipParts.Clip = self._assembly:take()
	self._assembly = ClipParts.new()
	if not took then
		warn(`The dev replay dropped a clip: {result}`)
		return
	end

	self._clip = result :: ClipParts.Clip
end

-- What a key does: the play key plays the newest clip or pauses and plays the one playing, and the rest work its clock
function Replay._press(self: Self, key: Enum.KeyCode)
	local clock: Clock.Clock? = self._clock
	if key == PLAY then
		if clock then
			clock:toggle()
		else
			self:_play()
		end
	elseif not clock then
		return
	elseif key == SLOWER then
		clock:cycle()
	elseif key == BACK then
		clock:step(-ONE_TICK)
	elseif key == FORWARD then
		clock:step(ONE_TICK)
	elseif key == REWIND then
		clock:seek(-SEEK)
	elseif key == SKIP then
		clock:seek(SEEK)
	elseif key == STOP then
		self:_stop()
	end
end

--[[
    Plays the newest clip from its start at the first speed. A clip whose
    frames don't decode, or that the client refuses, is warned and left
    unplayed
--]]

function Replay._play(self: Self)
	local clip: ClipParts.Clip? = self._clip
	if not clip then
		return
	end

	local measured: boolean, length: any = pcall(lengthOf, clip, self._relay)
	if not measured then
		warn(`The dev replay could not read the clip's length: {length}`)
		return
	end

	local client: Tread.Client = self._client
	local started: boolean, playback: any = pcall(client.play, client, clip.ticks, clip.withheld)
	if not started then
		warn(`The dev replay's clip was refused: {playback}`)
		return
	end

	self._playback = playback
	self._clock = Clock.new(length, 1 / self._relay, SPEEDS)
	self._reported = false
end

-- Ends the clip playing, telling the server first, and the live view comes back on the next frame
function Replay._stop(self: Self)
	local playback: Tread.Playback? = self._playback
	if not playback then
		return
	end

	self:_report(true)
	self._playback = nil
	self._clock = nil
	playback:destroy()
end

-- Tells the server, once a playback, the clip time it ended at and whether the stop key ended it
function Replay._report(self: Self, stopped: boolean)
	local clock: Clock.Clock? = self._clock
	if self._reported or not clock then
		return
	end

	self._reported = true
	Network.played.fire(clock:time(), stopped)
end

-- The label: the clip time, the length, the speed and whether it is paused, or that a clip is ready, or nothing
function Replay._show(self: Self)
	local label: TextLabel = self._label
	local clock: Clock.Clock? = self._clock

	if clock then
		local paused: string = clock:paused() and PAUSED or NOT_PAUSED
		label.Text = string.format(PLAYING, clock:time(), clock:length(), clock:speed(), paused)
		label.Visible = true
	elseif self._clip then
		label.Text = string.format(READY, PLAY.Name)
		label.Visible = true
	else
		label.Visible = false
	end
end

export type Replay = Self
type Self = typeof(setmetatable({} :: Fields, Replay))

return Replay
