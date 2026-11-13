--[[
    G9's spectating moderators: each one's and its target's bytes read once
    a second, the targets' withheld blocks recorded through the taps part
    way into the window, and the relay's time a tick with the taps off and on
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Tap = require(Packages.Tread.Codec.Tap)
local Tick = require(Packages.Tread.Server.Tick)

local Clips = require(ServerScriptService.Server.Clips)
local Config = require(ServerScriptService.Server.Bots.Config)

local TAPS: number = require(ServerScriptService.Server.Config.Spectators).taps
local COPY: number = require(ServerScriptService.Server.Config.Spectators).copy
local FEED: number = require(ServerScriptService.Server.Config.Spectators).feed
local WITHHELD: number = require(ServerScriptService.Server.Config.Spectators).withheld
local FRAMING: number = require(ServerScriptService.Server.Config.Spectators).framing
local PERCENTILES: { number } = require(ServerScriptService.Server.Bots.Config).percentiles
local STAGE: string = "relay" -- The tick stage whose times show what the taps cost
local WRAP: number = 2 ^ 16 -- A frame's relay tick is a u16
local BYTES_PER_KB: number = 1000 -- A line's KB, as the relay's budget counts them
local MILLISECONDS: number = 1000 -- A second's, which stage times print in
local FIGURE: string = "%.3f" -- A stage time as the bot harness prints it
local RATE: string = "%.2f" -- KB/s to the ten bytes, finer than the feed's line
local SEPARATOR: string = "; " -- Between the parts of one line

type Samples = { [string]: { number } }

-- What the bot harness's runs call around their window
export type Probe = {
	start: (entries: { any }) -> (), -- After the warm-up's stats read, with the fleet's entries
	stop: (samples: Samples) -> string, -- After the window, with every figure it read
}

-- One moderator's figures for its line, its own and its target's bytes a read and the target's withheld bytes a second
export type Watched = {
	moderator: string,
	target: string,
	moderatorBytes: { number }, -- Each read's, over the second before it, from the taps' connect
	targetBytes: { number },
	withheld: { number }, -- Each second's, by relay tick from the first withheld frame
}

-- A moderator the probe follows, from its start to its stop
type Watch = {
	moderator: Volt.Bot,
	target: Volt.Bot,
	recording: Clips.Recording?, -- The target's, from the taps' connect to the stop
	moderatorBytes: { number },
	targetBytes: { number },
}

local Spectators = {}

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
local function percentile(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

-- A list's configured percentiles in one figure, each in the format given. It sorts the list in place
local function spread(values: { number }, format: string): string
	local figures: { string } = {}
	for _, share: number in PERCENTILES do
		table.insert(figures, string.format(format, percentile(values, share)))
	end

	return table.concat(figures, "/")
end

-- The times a stage's ring holds, in milliseconds, in no particular order
local function snapshot(stage: Tick.Stage): { number }
	local times: { number } = {}
	for index: number = 1, stage.held do
		table.insert(times, stage.times[index] * MILLISECONDS)
	end

	return times
end

--[[
    A target's withheld bytes a second from its withheld tap frames, oldest
    first: each block's bytes and Volt's framing in front of it, grouped by
    relay tick into seconds of rate ticks from the first frame's, with the
    newest second left out until its last tick is in
--]]

function Spectators.withheld(frames: { buffer }, rate: number): { number }
	local totals: { number } = {}
	local first: number? = nil
	local whole: number = 0

	for _, data: buffer in frames do
		local frame: Tap.Frame = Tap.read(data)
		local from: number = first or frame.tick
		first = from

		-- Unwrapped from the first frame's tick, so a recording stays under a u16's ticks long
		local offset: number = (frame.tick - from) % WRAP
		local second: number = offset // rate + 1
		for index: number = #totals + 1, second do
			totals[index] = 0
		end

		for _, part: Tap.Part in frame.blocks do
			totals[second] += buffer.len(part.data) + FRAMING
		end

		whole = (offset + 1) // rate
	end

	return table.move(totals, 1, whole, 1, {})
end

--[[
    A moderator's line over the seconds its reads and its target's withheld
    seconds pair, each read beside the withheld second it covers, in KB/s:
    its copy and feed, which are its bytes less the withheld, those less
    the target's own bytes, the withheld, and the target's own
--]]

function Spectators.line(watched: Watched): string
	local count: number = math.min(#watched.moderatorBytes, #watched.targetBytes, #watched.withheld)
	local copies: { number } = {}
	local beyond: { number } = {}
	local withheld: { number } = {}
	local own: { number } = {}

	-- Whiteoak TODO: a second of relay ticks spans more than a wall second while the server drops ticks, so the reads
	-- drift from their seconds then; keeping each read's count of withheld frames kept would pair them exactly
	for index: number = 1, count do
		local copy: number = watched.moderatorBytes[index] - watched.withheld[index]
		local target: number = watched.targetBytes[index]

		table.insert(copies, copy / BYTES_PER_KB)
		table.insert(beyond, (copy - target) / BYTES_PER_KB)
		table.insert(withheld, watched.withheld[index] / BYTES_PER_KB)
		table.insert(own, target / BYTES_PER_KB)
	end

	local who: string = `{watched.moderator} watching {watched.target} over {count} s, KB/s p50/p95/p99`
	local parts: { string } = {
		`{who}: copy and feed {spread(copies, RATE)} against {COPY}`,
		`less the target's own {spread(beyond, RATE)} against {FEED}`,
		`withheld {spread(withheld, RATE)} outside the line beside about {WITHHELD}`,
		`the target's own {spread(own, RATE)}`,
	}

	return table.concat(parts, ", ")
end

--[[
    S10's probe: from its start it follows each bot of the fleet that
    spectates another. Once the configured share of the window has run, it
    keeps the relay stage's times and starts each target's recording, then
    reads each moderator's and target's bytes once a second to the window's
    end. Its stop ends every recording first, then gives the relay's time a
    tick with the taps off and on and each moderator's line, and throws
    with that line when anything failed, so the seed fails
--]]

function Spectators.probe(timing: Config.Timing): Probe
	-- Required here, so this module's pure parts load without the dev game, as its cases load them
	local Game: any = require(ServerScriptService.Server.Game)
	local Network = require(Packages.Tread.Network.Server) -- Tread's own scope, which each bot's bytes are counted on

	local server: Tread.Server, shared: Tread.Shared = Game.get()
	local rate: number = shared.rates.relay
	local frames: number = math.ceil(timing.window * (1 - TAPS) * rate) -- The relay ticks from the taps to the end

	local found: Tick.Stage? = nil
	for _, stage: Tick.Stage in Tick.stages() do
		if stage.name == STAGE then
			found = stage
		end
	end

	if not found then
		error(`The tick has no {STAGE} stage for S10's probe to time the taps by`, 2)
	end

	local relay: Tick.Stage = found
	local watches: { Watch } = {}
	local problems: { string } = {}
	local tapsOff: { number } = {}
	local beats: RBXScriptConnection? = nil
	local tapped: boolean = false
	local connectAt: number = 0
	local ends: number = 0
	local nextRead: number = 0

	local function disconnect()
		local beating: RBXScriptConnection? = beats
		beats = nil

		if beating then
			beating:Disconnect()
		end
	end

	-- The relay's times with the taps off kept, then each target's recording started
	local function connect()
		tapped = true
		tapsOff = snapshot(relay)

		for _, watch: Watch in watches do
			local made: boolean, recording: any = pcall(Clips.record, server, watch.target, frames)
			if made then
				watch.recording = recording
			else
				table.insert(problems, `{watch.target.Name}'s recording did not start: {recording}`)
			end
		end
	end

	-- Each moderator's bytes and its target's over the second before
	local function read()
		for _, watch: Watch in watches do
			local moderator: number = Network.traffic(watch.moderator)
			local target: number = Network.traffic(watch.target)

			table.insert(watch.moderatorBytes, moderator)
			table.insert(watch.targetBytes, target)
		end
	end

	-- Reads keep to a grid from the connect, so each covers the second its paired withheld second does
	local function beat()
		local now: number = os.clock()
		if not tapped then
			if now >= connectAt then
				connect()
				nextRead = now + timing.interval
			end
		elseif now >= nextRead and nextRead <= ends then
			nextRead += timing.interval
			read()
		end
	end

	local function start(entries: { any })
		disconnect()
		table.clear(watches)
		table.clear(problems)
		tapsOff = {}
		tapped = false

		local began: number = os.clock()
		connectAt = began + timing.window * TAPS
		ends = began + timing.window

		for _, entry: any in entries do
			local target: Volt.Bot? = entry.watching
			if target then
				table.insert(watches, {
					moderator = entry.volt,
					target = target,
					recording = nil,
					moderatorBytes = {},
					targetBytes = {},
				})
			end
		end

		if #watches == 0 then
			table.insert(problems, "no bot of the fleet spectates another")
		end

		-- Disconnected at stop, which the run calls whatever its window did
		beats = RunService.Heartbeat:Connect(beat)
	end

	local function stop(_: Samples): string
		-- Every tap ends before anything that can throw
		disconnect()
		for _, watch: Watch in watches do
			local recording: Clips.Recording? = watch.recording
			if recording then
				recording.stop()
			end
		end

		local parts: { string } = { `{#watches} moderators` }
		if tapped then
			local tapsOn: { number } = snapshot(relay)
			local off: string = `taps off {spread(tapsOff, FIGURE)} over {#tapsOff} ticks`
			local on: string = `taps on {spread(tapsOn, FIGURE)} over {#tapsOn} ticks`
			table.insert(parts, `relay ms a tick p50/p95/p99 {off}, {on}`)
		else
			table.insert(problems, "the window ended before the taps connected")
		end

		for _, watch: Watch in watches do
			local recording: Clips.Recording? = watch.recording
			watch.recording = nil -- Its frames go with it

			if not recording then
				continue
			end

			local readable: boolean, withheld: any = pcall(Spectators.withheld, recording.withheld, rate)
			if not readable then
				table.insert(problems, `{watch.target.Name}'s withheld frames did not read: {withheld}`)
				continue
			end

			table.insert(
				parts,
				Spectators.line({
					moderator = watch.moderator.Name,
					target = watch.target.Name,
					moderatorBytes = watch.moderatorBytes,
					targetBytes = watch.targetBytes,
					withheld = withheld,
				})
			)
		end

		for _, problem: string in problems do
			table.insert(parts, problem)
		end

		local line: string = `G9 spectate: {table.concat(parts, SEPARATOR)}`
		if #problems > 0 then
			error(line, 0)
		end

		return line
	end

	return { start = start, stop = stop }
end

return Spectators
