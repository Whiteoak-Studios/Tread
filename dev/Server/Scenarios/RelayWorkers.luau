--[[
    The relay's workers on the running server: a serial copy of the relay and
    a copy on Actor workers matched over seeded layouts, then the live pool,
    each worker ready, and S4 and S3 with their bots' views on it
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Relay = require(Packages.Tread.Server.Relay)
local Tick = require(Packages.Tread.Server.Tick)

local Config = require(ServerScriptService.Server.Bots.Config)
local Game = require(ServerScriptService.Server.Game)
local RelayCheck = require(ServerScriptService.Server.RelayCheck)
local Run = require(ServerScriptService.Server.Bots.Run)

local SCENARIOS: { string } = require(ServerScriptService.Server.Bots.Config).relayWorkers.scenarios
local TIMING: Config.Timing = require(ServerScriptService.Server.Bots.Config).relayWorkers.timing
local READY: number = require(ServerScriptService.Server.Bots.Config).relayWorkers.ready
local WORKERS: number = require(ServerScriptService.Server.Config.RelayCheck).workers
local DEADLINE: number = require(ServerScriptService.Server.Config.RelayCheck).deadline
local POOL: string = require(ServerScriptService.Server.Config.RelayCheck).pool
local RENAMED: string = require(ServerScriptService.Server.Config.RelayCheck).renamed
local HOME: string = require(ServerScriptService.Server.Config.RelayCheck).home
local LAYOUTS: { string } = require(ServerScriptService.Server.Config.RelayCheck).order
local SERIAL: string = "Serial" -- Copy A's clone of the package
local ON_WORKERS: string = "Workers" -- Copy B's
local SEPARATOR: string = "; " -- Between the loads' lines

--[[
    What each load's window runs beside: the Heartbeats from its start to its
    stop, read for the relay's rounds in by the next Heartbeat and later, and
    the rounds given up as the stats read them. It throws with its line when
    no round came in by the next Heartbeat or any was given up
--]]

local function probe(): Run.Probe
	local readout: Run.Readout = { times = {}, flags = {}, bots = {}, through = 0, lost = 0 }

	local function start(_: { any })
		readout = { times = {}, flags = {}, bots = {}, through = Tick.heartbeats().count, lost = 0 }
	end

	local function stop(samples: { [string]: { number } }): string
		Run.takeBeats(readout, Tick.heartbeats(), nil)

		local inTime: number, late: number = Run.rounds(readout.flags)
		local dropped: number = 0
		for _, count: number in samples.relayDropped or {} do
			dropped += count
		end

		local rounds: string = `{inTime} rounds in by the next Heartbeat, {late} later and {dropped} given up`
		local line: string = `{rounds} over {#readout.flags} Heartbeats, {readout.lost} not read`
		if inTime == 0 or dropped > 0 then
			error(line, 0)
		end

		return line
	end

	return { start = start, stop = stop }
end

-- A module of a copy's clone, required, erroring with what stopped it
local function load(module: any): any
	local loaded: boolean, result: any = pcall(require, module)
	if not loaded then
		error(`{module:GetFullName()} did not load: {result}`, 0)
	end

	return result
end

--[[
    A copy of the relay with every module its own: Tread's whole package
    cloned into the folder given, where no script runs, and each module
    the check drives required from that clone
--]]

local function copyIn(home: Folder, name: string): RelayCheck.Copy
	local tread: Instance = Packages.Tread:Clone()
	tread.Name = name
	tread.Parent = home

	local root: any = tread

	return {
		Relay = load(root.Server.Relay),
		Slots = load(root.Server.Slots),
		Taps = load(root.Server.Taps),
		State = load(root.Step.State),
		Fields = load(root.Codec.Fields),
		Constants = load(root.Constants),
		Sequence = load(root.Codec.Sequence),
		Block = load(root.Codec.Block),
	}
end

-- The pool folders under ServerScriptService that a relay's front made, the live relay's among them
local function pools(): { Instance }
	local found: { Instance } = {}
	for _, child: Instance in ServerScriptService:GetChildren() do
		if child.Name == POOL then
			table.insert(found, child)
		end
	end

	return found
end

-- The pool folder made since the list given, renamed so it shares no name with the live relay's
local function rename(before: { Instance }): Instance
	local made: Instance? = nil
	for _, folder: Instance in pools() do
		if not table.find(before, folder) then
			if made then
				error("Copy B's start made more than one pool folder", 0)
			end

			made = folder
		end
	end

	if not made then
		error("Copy B's start made no pool folder", 0)
	end

	made.Name = RENAMED

	return made
end

--[[
    Each layout through two new copies of the relay, on the running game's
    tables: copy A serial and copy B on as many Actor workers as the server
    started, at least WORKERS, its pool renamed as it is made. Both copies'
    clones and B's pool go once the layout ends, whatever it did
--]]

local function checkCopies(started: number): (boolean, { string })
	local _, shared: Tread.Shared, server: Tread.ServerSettings = Game.get()
	local count: number = math.max(WORKERS, started)
	local passed: boolean = true
	local lines: { string } = {}

	for _, name: string in LAYOUTS do
		local home: Folder = Instance.new("Folder")
		home.Name = HOME
		home.Parent = ServerStorage

		local before: { Instance } = pools()
		local renamed: Instance? = nil
		local began: number = os.clock()

		local ran: boolean, summary: any = pcall(function (): RelayCheck.Summary
			local serial: RelayCheck.Copy = copyIn(home, SERIAL)
			local workers: RelayCheck.Copy = copyIn(home, ON_WORKERS)

			return RelayCheck.check(RelayCheck.plan(name), serial, workers, {
				shared = shared,
				server = server,
				workers = count,
				timeout = DEADLINE,
				started = function ()
					renamed = rename(before)
				end,
			}, function ()
				RunService.Heartbeat:Wait()
			end)
		end)

		local seconds: number = os.clock() - began

		-- Destroying a pool's folder ends its workers' scripts and the bindings their Actors hold
		local made: Instance? = renamed
		if made then
			made:Destroy()
		end

		for _, folder: Instance in pools() do
			if not table.find(before, folder) then
				folder:Destroy()
			end
		end

		home:Destroy()

		if ran then
			passed = passed and summary.found == 0
			table.insert(lines, RelayCheck.line(summary, seconds))
		else
			passed = false
			table.insert(lines, `RelayCheck {name}: it threw: {summary}`)
		end
	end

	return passed, lines
end

return function (): (boolean, string | nil)
	local started: number = Run.workers()
	local matched: boolean, lines: { string } = checkCopies(started)

	if started == 0 then
		table.insert(
			lines,
			"the server started with no relay workers, so there is no pool; set Workspace's TreadRelayWorkers"
		)
		return false, table.concat(lines, SEPARATOR)
	end

	-- Each worker binds and sets itself up on its own, and each relay run finds those that have
	local deadline: number = os.clock() + READY
	local _, views: { number }, ready: number = Relay.homes()

	while ready < #views and os.clock() < deadline do
		RunService.Heartbeat:Wait()
		_, views, ready = Relay.homes()
	end

	if #views ~= started then
		table.insert(lines, `the relay has {#views} workers, and the server started with {started}`)
		return false, table.concat(lines, SEPARATOR)
	elseif ready < started then
		table.insert(lines, `{ready} of the relay's {started} workers were ready after {READY} s`)
		return false, table.concat(lines, SEPARATOR)
	end

	local passed: boolean = matched
	table.insert(lines, `{started} relay workers started, every one ready`)

	for _, name: string in SCENARIOS do
		local ok: boolean, line: string = Run.runWorkers(name, TIMING, true, probe())
		passed = passed and ok
		table.insert(lines, line)
	end

	return passed, table.concat(lines, SEPARATOR)
end
