--[[
    The Playback scenario's work: a walking bot's clip recorded through the
    taps, sent to a real player's client in parts over the dev scope, and
    the wait for that client to say it played the clip
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local ClipParts = require(ReplicatedStorage.Shared.Dev.ClipParts)
local Programs = require(ServerScriptService.Server.Bots.Programs)

local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Clips).rate
local CENTER: Vector3 = require(ServerScriptService.Server.Config.Clips).center
local FLOOR: Vector3 = require(ServerScriptService.Server.Config.Clips).floor
local LIFT: number = require(ServerScriptService.Server.Config.Clips).lift
local START: number = require(ServerScriptService.Server.Config.Clips).start
local ASIDE: number = require(ServerScriptService.Server.Config.Clips).aside
local SETTLE: number = require(ServerScriptService.Server.Config.Clips).settle
local SECONDS: number = require(ServerScriptService.Server.Config.Clips).seconds
local RECORD_WAIT: number = require(ServerScriptService.Server.Config.Clips).recordWait
local STREAM_WAIT: number = require(ServerScriptService.Server.Config.Clips).streamWait
local PART_BYTES: number = require(ServerScriptService.Server.Config.Clips).partBytes
local PLAY_WAIT: number = require(ServerScriptService.Server.Config.Clips).playWait
local FOLDER: string = "Playback" -- The folder the run lays its floor in
local GROUP: string = "playback" -- What the fleet's entries call the run's bots
local SEED: number = 1 -- Neither bot has faults, so nothing either draws ever matters
local FULL_INPUT: number = 1 -- A move axis's largest value
local TIME_FORMAT: string = "%.2f" -- A clip time to the hundredth of a second
local SEPARATOR: string = "; " -- Between the problems in one report

type Key = Player | Volt.Bot

-- A clip being recorded, as client:play takes it, and the closure that disconnects both its sinks
export type Recording = {
	ticks: { buffer }, -- The keyframe, then the observed frames, oldest first
	withheld: { buffer }, -- The withheld frames over the same ticks
	stop: () -> (),
}

-- What a player's client said when it last played a clip
type Played = {
	time: number, -- The clip time it ended at, seconds
	stopped: boolean, -- Whether its stop key ended it, rather than the clip's end
}

-- What one run made that its cleanup ends, whatever the run did
type Made = {
	recording: Recording?,
}

local Reports: { [Key]: Played } = {} -- Each player's newest, dropped when they leave
local Started: boolean = false

local Clips = {}

-- Keeps a player's newest report of a playback's end
local function heard(key: Key, time: number, stopped: boolean)
	Reports[key] = { time = time, stopped = stopped }
end

--[[
    Binds the played event at the dev game's own rate and keeps each
    player's newest report. It runs once a server, and its listener and
    leave, which forgets a player who left, live as long as the server
--]]

function Clips.start()
	if Started then
		error("Clips.start runs once a server, and it has already run", 2)
	end

	Started = true
	Network.rate("played", RATE.perSecond, RATE.burst)
	Network.played.on(heard)
	Network.onLeave(function (key: Key)
		Reports[key] = nil
	end)
end

--[[
    Records a viewer's clip as a clip recorder does: the viewer's keyframe
    taken inside its observe sink's first call, then that call's frame and
    every one after it until frames of them are kept, and its withheld
    frames over the same ticks. Once full it keeps nothing more, and its
    stop disconnects both sinks
--]]

function Clips.record(server: Tread.Server, viewer: Key, frames: number): Recording
	local ticks: { buffer } = {}
	local withheld: { buffer } = {}

	local stopObserving: () -> () = server:observe(viewer, function (_: number, frame: buffer)
		if #ticks > frames then
			return
		end

		-- Taken after this tick's relay, so the keyframe and this tick's frame hold the same view
		if #ticks == 0 then
			table.insert(ticks, server:keyframe(viewer))
		end

		table.insert(ticks, frame)
	end)

	-- Its frames hold no block unless a moderator spectates the viewer, since the relay builds the withheld set only
	-- then. A tick's withheld sink runs after its observe sink, so each keeps the tick an observed frame just kept
	local stopWithholding: () -> () = server:observeWithheld(viewer, function (_: number, frame: buffer)
		if #withheld < #ticks - 1 then
			table.insert(withheld, frame)
		end
	end)

	return {
		ticks = ticks,
		withheld = withheld,

		stop = function ()
			stopObserving()
			stopWithholding()
		end,
	}
end

-- Waits a frame at a time until done says so or seconds pass, and gives whether it got there
local function waitFor(seconds: number, done: () -> boolean): boolean
	local deadline: number = os.clock() + seconds

	while not done() do
		if os.clock() >= deadline then
			return false
		end

		RunService.Heartbeat:Wait()
	end

	return true
end

--[[
    Sends one list to a player in parts, a part a frame, so each of Volt's
    flushes carries one part and its packet stays under maxPacket. Gives
    how many parts it sent
--]]

local function send(player: Player, withheld: boolean, list: { buffer }): number
	local parts: { buffer } = ClipParts.split(list, PART_BYTES)

	for index: number, part: buffer in parts do
		Network.clip.fire(player, withheld, index, #parts, part)
		RunService.Heartbeat:Wait()
	end

	return #parts
end

--[[
    The run on the floor laid: the watcher standing beside the walker's
    line and the walker down it, the walker's clip recorded once both have
    settled, the floor streamed in for the player and the clip sent, then
    the wait for the player's client to say it played it
--]]

local function film(
	made: Made,
	Fleet: any,
	server: Tread.Server,
	shared: Tread.Shared,
	player: Player
): (boolean, string)
	local frames: number = math.round(SECONDS * shared.rates.relay)
	local raised: Vector3 = CENTER + Vector3.new(0, LIFT, 0)

	-- A command at rest looks along -Z, the line, so a full forward walks it, until its clip is full
	local function walk(command: Tread.Command, _: number, _: vector)
		local recording: Recording? = made.recording
		if recording and #recording.ticks > frames then
			return
		end

		command.forward = FULL_INPUT
	end

	-- Each faces -Z, as a CFrame with no turn does
	Fleet.add({
		name = "PlaybackWatcher",
		group = GROUP,
		at = CFrame.new(raised + Vector3.new(ASIDE, 0, 0)),
		steer = Programs.idle(),
		faults = nil,
		seed = SEED,
	})

	local walker: any = Fleet.add({
		name = "PlaybackWalker",
		group = GROUP,
		at = CFrame.new(raised + Vector3.new(0, 0, START)),
		steer = walk,
		faults = nil,
		seed = SEED,
	})

	task.wait(SETTLE)

	local recording: Recording = Clips.record(server, walker.volt, frames)
	made.recording = recording

	local recorded: boolean = waitFor(RECORD_WAIT, function (): boolean
		return #recording.ticks > frames
	end)

	recording.stop()
	if not recorded then
		local held: number = math.max(#recording.ticks - 1, 0)
		return false, `the walker's clip held {held} of {frames} frames after {RECORD_WAIT} s`
	end

	-- A stream that fails leaves the clip's bots over nothing on the player's screen, and the clip still plays
	local streamed: boolean, failure: any = pcall(player.RequestStreamAroundAsync, player, CENTER, STREAM_WAIT)
	if not streamed then
		warn(`The Playback floor may not have streamed in for {player.Name}: {failure}`)
	end

	Reports[player] = nil
	local parts: number = send(player, false, recording.ticks)
	parts += send(player, true, recording.withheld)

	local reported: boolean = waitFor(PLAY_WAIT, function (): boolean
		return Reports[player] ~= nil or player.Parent == nil
	end)

	local report: Played? = Reports[player]
	if not reported then
		return false, `{player.Name}'s client did not say it played the clip within {PLAY_WAIT} s`
	elseif not report then
		return false, `{player.Name} left before their client said it played the clip`
	end

	local sent: string = `the walker's clip of {frames} frames and {#recording.withheld} withheld went in {parts} parts`
	local ending: string = report.stopped and "stopped it" or "played it to its end"

	return true, `{sent}, and {player.Name}'s client {ending} at {string.format(TIME_FORMAT, report.time)} s`
end

--[[
    The Playback scenario: refused beside other fleet bots or with no real
    player who has a character. It lays a floor away from everything, films
    a bot walking past another, sends the clip to the player's client and
    waits for that client to play it. The recording's sinks, the fleet and
    the floor go whatever the run did, and every wait is its own deadline
--]]

function Clips.run(): (boolean, string)
	-- Required here, so the binding and the recorder load without the dev game, as their cases load them
	local Fleet: any = require(ServerScriptService.Server.Bots.Fleet)
	local Game: any = require(ServerScriptService.Server.Game)

	local server: Tread.Server, shared: Tread.Shared = Game.get()
	Fleet.start()
	if #Fleet.entries() > 0 then
		return false, `another run's {#Fleet.entries()} bots are still on the server`
	end

	local player: Player? = nil
	for _, candidate: Player in Players:GetPlayers() do
		if Game.characterOf(candidate) then
			player = candidate
			break
		end
	end

	if not player then
		return false, "no real player has a character to play the clip on"
	end

	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return false, "Workspace.TestContent is missing, so the dev game's casts take no floor laid"
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = FOLDER

	local floor: Part = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.CanCollide = true
	floor.CanQuery = true
	floor.CanTouch = false
	floor.Size = FLOOR
	floor.CFrame = CFrame.new(CENTER - Vector3.new(0, FLOOR.Y / 2, 0))
	floor.Parent = folder
	folder.Parent = testContent

	local made: Made = { recording = nil }
	local ran: boolean, passed: any, line: any = pcall(film, made, Fleet, server, shared, player)

	-- Everything it made goes, whatever the run did
	local recording: Recording? = made.recording
	if recording then
		recording.stop()
	end

	local problems: { string } = Fleet.clear()
	folder:Destroy()

	if not ran then
		table.insert(problems, `the run threw: {passed}`)
	elseif not passed then
		table.insert(problems, line)
	end

	print(`Playback: {ran and line or passed}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end

return Clips
