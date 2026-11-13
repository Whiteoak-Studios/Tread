--[[
    One of the bot harness's scenarios on the dev game's server, seed by
    seed after any calibration: its bodies laid out at any render distance,
    a warm-up, a window of Tread's stats and frames, and all of it undone
--]]

--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Command = require(Packages.Tread.Codec.Command)
local Relay = require(Packages.Tread.Server.Relay)
local Tick = require(Packages.Tread.Server.Tick)

local Bot = require(ServerScriptService.Server.Bots.Bot)
local Calibration = require(ServerScriptService.Server.Calibration)
local Config = require(ServerScriptService.Server.Bots.Config)
local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Seeded = require(ServerScriptService.Server.Bots.Seeded)

local SCENARIOS: { [string]: Config.Scenario } = require(ServerScriptService.Server.Bots.Config).scenarios
local PERCENTILES: { number } = require(ServerScriptService.Server.Bots.Config).percentiles
local FPS: number = require(ServerScriptService.Server.Bots.Config).fps
local TICK_STAGES: { string } = require(ServerScriptService.Server.Bots.Config).tick.stages
local BESIDE: string = require(ServerScriptService.Server.Bots.Config).tick.beside
local COUNTS: { string } = require(ServerScriptService.Server.Bots.Config).tick.counts
local MOVED: number = require(ServerScriptService.Server.Bots.Config).moved
local EVERY: number = require(ServerScriptService.Server.Bots.Config).cheats.every
local HOLDS: { number } = require(ServerScriptService.Server.Bots.Config).cheats.holds
local AHEAD: { number } = require(ServerScriptService.Server.Bots.Config).cheats.ahead
local DROPS: number = require(ServerScriptService.Server.Bots.Config).cheats.drops
local FREEZE: number = require(ServerScriptService.Server.Bots.Config).cheats.freeze
local BATCH: number = require(ServerScriptService.Server.Bots.Config).spawn.batch
local LIFT: number = require(ServerScriptService.Server.Bots.Config).spawn.lift
local TRIES: number = require(ServerScriptService.Server.Bots.Config).spawn.tries
local PROBE: number = require(ServerScriptService.Server.Bots.Config).spawn.probe
local THICKNESS: number = require(ServerScriptService.Server.Bots.Config).spawn.thickness
local TILE: number = require(ServerScriptService.Server.Bots.Config).spawn.tile
local SINK: number = require(ServerScriptService.Server.Bots.Config).spawn.sink
local MARGIN: number = require(ServerScriptService.Server.Bots.Config).spawn.margin
local SEED_BOUND: number = 2 ^ 31 - 2 -- The largest seed a bot's own generator is drawn
local APART: number = 16807 -- Scales a spawn's redraw seed off the stream every bot's own generator walks
local TURN: number = 2 * math.pi
local MILLISECONDS: number = 1000 -- A second's, which stage times print in
local PERCENT: number = 100 -- Turns a share into the number a pNN label shows
local FIGURE: string = "%.3f" -- Each stats figure and stage time as the summaries print it
local RAW: string = "%.4g" -- Four significant digits, for frame times and Stats' figures, whose units differ
local SEPARATOR: string = "; " -- Between the parts of one line
local SUM: string = " + " -- Between the summed stages' names

-- Where an area is probed for ground: its center and its corners, as shares of its half width and half depth
local PROBES: { Vector2 } = { Vector2.zero, Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.one }

type Area = Config.Area
type Group = Config.Group
type Scenario = Config.Scenario
type Timing = Config.Timing

-- Each figure the window read, a sample a read, by its name
type Samples = { [string]: { number } }

-- What the window takes of the server beside Tread's stats: each Heartbeat's interval and Stats times, a send rate a read
type Sampled = {
	frames: { number }, -- Milliseconds
	heartbeatTimes: { number },
	physicsTimes: { number },
	dataSend: { number },
}

-- What watches a run's window beside the stats, started after the warm-up's read and stopped after the window
export type Probe = {
	start: (entries: { any }) -> (), -- With the fleet's entries
	stop: (samples: Samples) -> string, -- Gives its line, from every figure the window read
}

-- An NPC a run built, with its own command and program
type Driven = {
	npc: Tread.Npc,
	group: string,
	first: Vector3, -- Where it stood once built
	awake: boolean,
	steer: Programs.Steer?, -- nil for one left standing
	command: Tread.Command, -- Its own, which its program refills each tick
}

-- A sleeper a run laid
type Laid = {
	sleeper: Tread.Sleeper,
	group: string,
}

-- What one seeded run made, all of which it removes whatever happened
type Made = {
	floors: Folder?,
	groups: { [Volt.Bot]: string }, -- Each of its bots' group
	npcs: { Driven },
	sleepers: { Laid },
	reports: { [string]: { [string]: number } }, -- Its bots' reports by group and kind
	stopReports: (() -> ())?,
	stopDriver: (() -> ())?, -- Takes the NPCs' driver off the bots' stage
	beats: RBXScriptConnection?, -- The window's Heartbeat samples while it runs
	probing: Probe?, -- The probe while it is started and not yet stopped
	viewers: { Player }, -- The real players it set a render distance for, put back after
}

local Run = {}

-- An area moved by an offset, its size kept
local function shifted(area: Area, offset: Vector3): Area
	return { center = area.center + offset, size = area.size }
end

--[[
    How far a scenario's areas move so its viewer point lands on the first
    real player's character, or nowhere when no real player has one
--]]

local function viewerOffset(server: Tread.Server, viewer: Vector3): Vector3
	-- Whiteoak TODO: set the real players down at the viewer point with character:teleport once step 3 adds it, as
	-- the A0 arm does, in place of moving the scenario's areas to them
	for _, target: Tread.Target in server:getAll() do
		-- An NPC has no player, and a bot's is no Instance
		local owner: any = (target :: any).player
		if typeof(owner) == "Instance" then
			return (target :: Tread.Character):getState().root - viewer
		end
	end

	return Vector3.zero
end

-- What a cast meets in the dev game's collision, which Tread's own casts take too, colliding parts alone
local function castParams(testContent: Instance): RaycastParams
	local params: RaycastParams = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { testContent, Workspace.Terrain }
	params.RespectCanCollide = true

	return params
end

-- What a spawn's hull is tested against in the dev game's collision, the test content's colliding parts alone
local function overlapParams(testContent: Instance): OverlapParams
	local params: OverlapParams = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { testContent }
	params.RespectCanCollide = true

	return params
end

-- The ground's height under a point, cast down from PROBE above a height to as far below it, or nil over nothing
local function groundAt(x: number, z: number, height: number, params: RaycastParams): number?
	local origin: Vector3 = Vector3.new(x, height + PROBE, z)
	local hit: RaycastResult? = Workspace:Raycast(origin, Vector3.new(0, -2 * PROBE, 0), params)
	if not hit then
		return nil
	end

	return hit.Position.Y
end

-- One area's floor, its top just under the area's height, in as few tiles edge to edge as a part's largest size allows
local function layFloor(area: Area, folder: Folder)
	local width: number = area.size.X + 2 * MARGIN
	local depth: number = area.size.Y + 2 * MARGIN
	local across: number = math.ceil(width / TILE)
	local deep: number = math.ceil(depth / TILE)
	local size: Vector3 = Vector3.new(width / across, THICKNESS, depth / deep)
	local first: Vector3 = area.center - Vector3.new((width - size.X) / 2, SINK + THICKNESS / 2, (depth - size.Z) / 2)

	for column: number = 0, across - 1 do
		for row: number = 0, deep - 1 do
			local floor: Part = Instance.new("Part")
			floor.Name = "Floor"
			floor.Anchored = true
			floor.CanCollide = true
			floor.CanQuery = true
			floor.CanTouch = false
			floor.Size = size
			floor.CFrame = CFrame.new(first + Vector3.new(column * size.X, 0, row * size.Z))
			floor.Parent = folder
		end
	end
end

--[[
    Lays a floor under each of a scenario's areas that has no ground at
    its center or a corner, reaching past its edges, as the A0 arm lays its
    own. Gives the folder and how many areas it floored
--]]

local function layFloors(
	scenario: Scenario,
	offset: Vector3,
	testContent: Instance,
	params: RaycastParams
): (Folder, number)
	local folder: Folder = Instance.new("Folder")
	folder.Name = "Bots"
	folder.Parent = testContent

	local laid: { [Area]: boolean } = {}
	local floored: number = 0

	for _, group: Group in scenario.groups do
		for _, configured: Area? in { group.spawn, group.roam } do
			if not configured or laid[configured] then
				continue
			end

			laid[configured] = true

			local area: Area = shifted(configured, offset)
			local center: Vector3 = area.center
			local bare: boolean = false

			for _, share: Vector2 in PROBES do
				local x: number = center.X + share.X * area.size.X / 2
				local z: number = center.Z + share.Y * area.size.Y / 2
				if groundAt(x, z, center.Y, params) == nil then
					bare = true
				end
			end

			if bare then
				layFloor(area, folder)
				floored += 1
			end
		end
	end

	return folder, floored
end

--[[
    A seeded point of an area, on the ground there or at the area's height
    over nothing, facing a seeded way. Given a hull, it is drawn again while
    that hull standing there meets a part's bounds or a body, and the last
    of the configured tries is kept
--]]

local function spawnPoint(
	area: Area,
	own: Seeded.Seeded,
	params: RaycastParams,
	hull: Vector3?,
	overlap: OverlapParams
): CFrame
	local server: Tread.Server = Game.get()
	local draws: Seeded.Seeded = own
	local at: CFrame = CFrame.identity

	for try: number = 1, TRIES do
		local x: number = area.center.X + draws:number(-area.size.X / 2, area.size.X / 2)
		local z: number = area.center.Z + draws:number(-area.size.Y / 2, area.size.Y / 2)
		local y: number = (groundAt(x, z, area.center.Y, params) or area.center.Y) + LIFT
		at = CFrame.new(x, y, z) * CFrame.Angles(0, draws:number(0, TURN), 0)

		if not hull then
			break
		end

		local center: CFrame = CFrame.new(x, y + hull.Y / 2, z)
		if not server:overlaps(center, hull) and #Workspace:GetPartBoundsInBox(center, hull, overlap) == 0 then
			break
		end

		-- A bot's own seed is the run generator's state, so its own next draws are later bots' spawns
		if try == 1 then
			draws = Seeded.new(own:integer(1, SEED_BOUND) * APART)
		end
	end

	return at
end

-- Seconds as ticks, at least one
local function ticksOf(seconds: number, context: Bot.Context): number
	return math.max(1, math.round(seconds * context.simulation))
end

--[[
    A cheat's windows for one bot, its first at a seeded tick: a lag switch
    and a relabel hold for each configured length in turn, a freeze sends
    nothing for its length, a crouched bot loses its Moves in a row, and a
    tamper sends one differing second copy. A long move is its program's
--]]

local function cheatOf(kind: Config.Cheat, own: Seeded.Seeded, context: Bot.Context): Bot.Cheat?
	if kind == "longMove" then
		return nil
	end

	local every: number = ticksOf(EVERY, context)
	local perMove: number = math.ceil(context.simulation / context.relay) -- Ticks each relay tick spans
	local lengths: { number } = { perMove }
	local ahead: { number } = { AHEAD[1] }

	if kind == "lagSwitch" or kind == "relabel" then
		lengths = {}
		for _, seconds: number in HOLDS do
			table.insert(lengths, ticksOf(seconds, context))
		end

		ahead = {}
		for ticks: number = AHEAD[1], AHEAD[2] do
			table.insert(ahead, ticks)
		end
	elseif kind == "freeze" then
		lengths = { ticksOf(FREEZE, context) }
	elseif kind == "crouchLoss" then
		lengths = { DROPS * perMove }
	end

	return { kind = kind, every = every, phase = own:integer(0, every - 1), lengths = lengths, ahead = ahead }
end

-- A group's bot's faults, its lag and loss drawn from the group's ranges and its cheat's windows from its generator
local function faultsOf(group: Group, own: Seeded.Seeded, context: Bot.Context): Bot.Faults
	local faults: Bot.Faults = { lag = 0, loss = 0, cheat = nil }
	local lag: { number }? = group.lag
	local loss: { number }? = group.loss
	local cheat: Config.Cheat? = group.cheat

	if lag then
		faults.lag = math.round(own:number(lag[1], lag[2]) * context.simulation)
	end

	if loss then
		faults.loss = own:number(loss[1], loss[2])
	end

	if cheat then
		faults.cheat = cheatOf(cheat, own, context)
	end

	return faults
end

--[[
    Parks a moderator bot, as a game parks its moderators, and starts its
    spectate of the bot built in the same place of the group it watches
--]]

local function watch(server: Tread.Server, moderator: Fleet.Entry, watched: { Fleet.Entry }?, place: number)
	local target: Fleet.Entry? = watched and watched[place]
	if not target then
		error(`{moderator.volt.Name} of {moderator.group} has no bot {place} of the group it spectates to watch`, 0)
	end

	moderator.character:setMode("Parked")
	server:spectate(moderator.volt, target.character)
	moderator.watching = target.volt
end

--[[
    Builds an NPC into the run's list before anything else can fail, then
    idles it or gives it its program, which the driver steers it by
--]]

local function addNpc(group: Group, at: CFrame, roam: Area?, own: Seeded.Seeded, gait: Programs.Gait, made: Made)
	local server: Tread.Server = Game.get()
	local npc: Tread.Npc = server:createNpc(at)
	local driven: Driven = {
		npc = npc,
		group = group.name,
		first = at.Position,
		awake = group.awake ~= false,
		steer = nil,
		command = Command.new(),
	}

	table.insert(made.npcs, driven)
	driven.first = npc:getState().root

	if not driven.awake then
		npc:setAwake(false)
	elseif roam then
		driven.steer = Programs.roam(roam, own, gait)
	end
end

--[[
    Builds every group's bodies in order from the run's one seeded
    generator, each with a generator of its own, so a seed puts each body
    at the same start and gives it the same path and the same faults, a
    batch a frame. A bot or an NPC whose standing hull would meet test
    content or a body already built draws its spawn again from a generator
    its own seeds, which draws no other body's numbers. A bot takes its
    group's team and any spectate
--]]

local function spawnAll(
	scenario: Scenario,
	seeded: Seeded.Seeded,
	offset: Vector3,
	made: Made,
	params: RaycastParams,
	overlap: OverlapParams
)
	local context: Bot.Context = Fleet.start()
	local server: Tread.Server, shared: Tread.Shared = Game.get()
	local built: { [string]: { Fleet.Entry } } = {} -- Each bot group's entries in build order, for a spectate to watch
	local width: number = 2 * shared.step.radius
	local standing: Vector3 = Vector3.new(width, shared.step.standing, width)
	local index: number = 0

	for _, group: Group in scenario.groups do
		local spawn: Area = shifted(group.spawn, offset)
		local roam: Area? = group.roam and shifted(group.roam, offset)
		local speed: number = shared.step.walk
		local entries: { Fleet.Entry } = {}
		built[group.name] = entries

		-- A sleeper's lying body blocks no one, so it keeps its first draw
		local hull: Vector3? = standing
		if group.kind == "sleeper" then
			hull = nil
		end

		if group.crouch then
			speed = shared.step.crouch
		elseif group.sprint then
			speed = shared.step.sprint
		end

		local gait: Programs.Gait = {
			speed = speed,
			rate = context.simulation,
			sprint = group.sprint == true,
			crouch = group.crouch == true,
			long = group.cheat == "longMove",
		}

		for _ = 1, group.count do
			index += 1

			local own: Seeded.Seeded = Seeded.new(seeded:integer(1, SEED_BOUND))
			local at: CFrame = spawnPoint(spawn, own, params, hull, overlap)

			if group.kind == "npc" then
				addNpc(group, at, roam, own, gait, made)
			elseif group.kind == "sleeper" then
				local sleeper: Tread.Sleeper? = server:createSleeper(at, {})
				if sleeper then
					table.insert(made.sleepers, { sleeper = sleeper, group = group.name })
				end
			else
				local steer: Programs.Steer = Programs.idle()
				if roam then
					steer = Programs.roam(roam, own, gait)
				end

				local entry: Fleet.Entry = Fleet.add({
					name = `Bot{index}`,
					group = group.name,
					at = at,
					steer = steer,
					faults = faultsOf(group, own, context),
					seed = own:integer(1, SEED_BOUND),
				})

				made.groups[entry.volt] = group.name
				table.insert(entries, entry)
				entry.character:setTeam(group.team)

				local spectate: string? = group.spectate
				if spectate then
					watch(server, entry, built[spectate], #entries)
				end
			end

			-- A frame between batches, each bot's client side being a module of its own to load
			if index % BATCH == 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end
end

--[[
    Sets every viewer to a render distance as its client would, none when
    it is nil: each bot's own client side sends it over View, and each real
    player with a character is set on the path View's listener runs
--]]

local function setViewers(distance: number?, made: Made)
	if not distance then
		return
	end

	for _, entry: Fleet.Entry in Fleet.entries() do
		entry.bot:view(distance)
	end

	for _, player: Player in Players:GetPlayers() do
		if Game.characterOf(player) and not table.find(made.viewers, player) then
			Relay.setDistance(player, distance)
			table.insert(made.viewers, player)
		end
	end
end

--[[
    Puts each real player the run set, and still in, back at the server's
    radius, what a client has before its first View and what the dev
    client's desktop draw distance sends. A bot's view goes with the bot
--]]

local function restoreViewers(made: Made, problems: { string })
	local _, _, settings: Tread.ServerSettings = Game.get()

	-- Whiteoak TODO: put each player back to the distance its client last sent once Tread's relay gives a viewer's
	-- distance; until then a client set shorter, such as a phone or the dev place's render key, is sent the radius
	for _, player: Player in made.viewers do
		if player.Parent == nil then
			continue
		end

		local restored: boolean, failure: any = pcall(Relay.setDistance, player, settings.relevancy.leave)
		if not restored then
			table.insert(problems, `{player.Name}'s render distance was not put back: {failure}`)
		end
	end
end

-- Steers an awake NPC by its program from where its body stands, as a bot's client side steers from its OwnerState
local function steerNpc(driven: Driven, tick: number)
	local steer: Programs.Steer? = driven.steer
	if not steer then
		return
	end

	local root: Vector3 = driven.npc:getState().root
	steer(driven.command, tick, vector.create(root.X, root.Y, root.Z))
	driven.npc:command(driven.command)
end

-- Runs where an NPC's steer raised its error, so its warning keeps the stack
local function warnNpc(message: any)
	warn(`An NPC's program threw, and the other NPCs were still steered: {debug.traceback(tostring(message), 2)}`)
end

-- A lever's state as the start line prints it
local function onOff(on: any): string
	return on and "on" or "off"
end

--[[
    The line a seed's warm-up starts on: the real players in, the relay's
    two levers as the running server's settings hold them, any render
    distance every viewer was set to, the floors laid, the NPCs awake and
    the sleepers made of those its groups ask for
--]]

local function startLine(
	label: string,
	scenario: Scenario,
	offset: Vector3,
	floored: number,
	made: Made,
	distance: number?
): string
	local server: Tread.Server, _, settings: Tread.ServerSettings = Game.get()
	local relay: { read changes: boolean? }? = settings.relay
	local asked: number = 0

	for _, group: Group in scenario.groups do
		if group.kind == "sleeper" then
			asked += group.count
		end
	end

	local real: string = `{#Players:GetPlayers()} real players in`
	local levers: string = `outOfView {onOff(settings.tiers.outOfView)}, changes {onOff(relay and relay.changes)}`
	if distance then
		levers = `{levers}, every viewer's render distance {distance} studs`
	end

	local bodies: string =
		`{floored} floors laid, {server:stats().npcs} NPCs awake, {#made.sleepers} sleepers made of {asked}`

	return `{label}: starting with {real}, {levers}, {bodies}, its areas moved {offset}`
end

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

-- Each figure's percentiles over the window, in one line
local function summary(samples: Samples): string
	local names: { string } = {}
	for name: string in samples do
		table.insert(names, name)
	end

	table.sort(names)

	local parts: { string } = {}
	for _, name: string in names do
		table.insert(parts, `{name} {spread(samples[name], FIGURE)}`)
	end

	return table.concat(parts, SEPARATOR)
end

local function push(samples: Samples, name: string, value: number)
	local list: { number } = samples[name] or {}
	samples[name] = list
	table.insert(list, value)
end

--[[
    The server's line over the window, as the A0 arm's: Heartbeats a
    second, each one's interval as its frame time and its low share as the
    server's frame rate, and Stats' figures raw, since their units are
    unproven
--]]

local function serverLine(label: string, sampled: Sampled, elapsed: number): string
	local rates: { number } = {}
	for _, frame: number in sampled.frames do
		table.insert(rates, MILLISECONDS / frame)
	end

	local parts: { string } = {
		`{label} server: {string.format(RAW, #sampled.frames / elapsed)} Heartbeats a second`,
		`frame ms p50/p95/p99 {spread(sampled.frames, RAW)}`,
		`server FPS p{math.round(FPS * PERCENT)} {string.format(RAW, percentile(rates, FPS))}`,
		`Stats.HeartbeatTime p50/p95/p99 {spread(sampled.heartbeatTimes, RAW)}`,
		`Stats.PhysicsStepTime p50/p95/p99 {spread(sampled.physicsTimes, RAW)}`,
		`Stats.DataSendKbps p50/p95/p99 {spread(sampled.dataSend, RAW)}`,
	}

	return table.concat(parts, SEPARATOR)
end

-- The tick stages' line: their total a tick over the window, with the stage beside them's p95 as each read gave it
local function tickLine(label: string, totals: { number }, samples: Samples): string
	local besideKey: string = `{BESIDE}P95Ms`
	local parts: { string } = {
		`{label} Tread tick stages a tick, {table.concat(TICK_STAGES, SUM)}, ms p50/p95/p99 {spread(totals, FIGURE)}`,
		`{#totals} ticks`,
		`{BESIDE} p95 ms beside them, p50/p95/p99 over the reads {spread(samples[besideKey] or {}, FIGURE)}`,
	}

	return table.concat(parts, SEPARATOR)
end

-- The configured counts a tick over the window, each read's change over the ticks that read ran
local function countsLine(label: string, perTick: Samples): string
	local parts: { string } = {}
	for _, name: string in COUNTS do
		table.insert(parts, `{name} {spread(perTick[name] or {}, FIGURE)}`)
	end

	return `{label} counts a tick, p50/p95/p99 over the reads: {table.concat(parts, SEPARATOR)}`
end

--[[
    The window: Tread's stats read once each interval with the real player
    count and each real player's bytes over the last second beside it, each
    read printed as it comes, the server's frames, every tick's summed
    stages and the counts a tick taken beside, their lines printed after,
    and the percentiles of every stats figure, with every figure's samples.
    It ends on its own deadline
--]]

local function window(label: string, scenario: Scenario, timing: Timing, made: Made): (string, Samples)
	local server: Tread.Server = Game.get()
	local Network = require(Packages.Tread.Network.Server) -- Tread's own scope, which each viewer's bytes are counted on
	local samples: Samples = {}
	local perTick: Samples = {}
	local sampled: Sampled = { frames = {}, heartbeatTimes = {}, physicsTimes = {}, dataSend = {} }
	local totals: { number } = {}
	local counted: number = Tick.counts()
	local started: number = os.clock()
	local deadline: number = started + timing.window
	local stalled: boolean = false
	local second: number = 0

	-- Disconnected as the window closes, or by the run's removal of all it made should the window throw
	local beats: RBXScriptConnection = RunService.Heartbeat:Connect(function (delta: number)
		table.insert(sampled.frames, delta * MILLISECONDS)
		table.insert(sampled.heartbeatTimes, Stats.HeartbeatTime)
		table.insert(sampled.physicsTimes, Stats.PhysicsStepTime)
	end)

	made.beats = beats

	while os.clock() < deadline do
		task.wait(timing.interval)
		second += 1

		local stats: { [string]: any } = server:stats()
		local viewers: { [string]: number } = {}
		local real: { Player } = Players:GetPlayers()

		for _, player: Player in real do
			local sent: number = Network.traffic(player)
			viewers[player.Name] = sent
			push(samples, "viewerBytes", sent)
		end

		for name: string, value: any in stats do
			if type(value) == "number" then
				push(samples, name, value)
			end
		end

		for name: string, times: any in stats.stages do
			push(samples, `{name}Ms`, times.last * MILLISECONDS)
			push(samples, `{name}P95Ms`, times.p95 * MILLISECONDS)
		end

		-- A read whose ticks all dropped ran none to count over
		local ticks: any = stats.ticks
		if type(ticks) == "number" and ticks > 0 then
			for _, name: string in COUNTS do
				local count: any = stats[name]
				if type(count) == "number" then
					push(perTick, name, count / ticks)
				end
			end
		end

		-- The ticks run since the last read, each one's stages summed from their rings
		local ran: number = Tick.counts()
		for _, total: number in Run.tickTotals(Tick.stages(), ran - counted) do
			table.insert(totals, total * MILLISECONDS)
		end

		counted = ran
		table.insert(sampled.dataSend, Stats.DataSendKbps)

		local counts: string = `real players {#real}, viewers {HttpService:JSONEncode(viewers)}`
		print(`{label} second {second}: {counts}, stats {HttpService:JSONEncode(stats)}`)

		-- A hitch half way through, once, as a live server's would come
		local stall: number? = scenario.stall
		if stall and not stalled and os.clock() - started >= timing.window / 2 then
			stalled = true
			Fleet.stall(stall)
		end
	end

	local elapsed: number = os.clock() - started
	beats:Disconnect()
	made.beats = nil

	print(serverLine(label, sampled, elapsed))
	print(tickLine(label, totals, samples))
	print(countsLine(label, perTick))

	return `{label} summary over {second} reads, p50/p95/p99: {summary(samples)}`, samples
end

-- A bot group's line: its bots' counts and motion, the holds, and its reports. A moderator's need not hear or send
local function botsDrove(group: Group, made: Made, problems: { string }): string
	local bots: number, heard: number, sent: number, dropped: number, held: number = 0, 0, 0, 0, 0
	local silent: number, moved: number, fastest: number, holds: number, farthest: number = 0, 0, 0, 0, 0

	for _, entry: Fleet.Entry in Fleet.entries() do
		if entry.group ~= group.name then
			continue
		end

		local measure: Bot.Measure = entry.bot:measure()
		local first: vector? = measure.first
		local position: vector? = measure.position

		bots += 1
		heard += measure.heard
		sent += measure.sent
		dropped += measure.dropped
		held += measure.held
		fastest = math.max(fastest, measure.fastest)

		if measure.heard == 0 or measure.sent + measure.held + measure.dropped == 0 then
			silent += 1
		end

		if first and position then
			local x: number, z: number = position.x - first.x, position.z - first.z
			moved += math.sqrt(x * x + z * z)
		end

		for _, hold: Bot.Hold in measure.holds do
			holds += 1
			farthest = math.max(farthest, hold.moved)
		end
	end

	local average: number = 0
	if bots > 0 then
		average = moved / bots
	end

	-- A parked moderator's body neither moves nor, unverified, hears an OwnerState, so its group skips the check
	if silent > 0 and not group.spectate then
		table.insert(problems, `{silent} of {group.name}'s {bots} bots heard no OwnerState or sent nothing`)
	elseif group.roam and bots > 0 and average < MOVED then
		table.insert(problems, `{group.name}'s bots moved {average} studs on average, under {MOVED}`)
	end

	local counts: string = `{bots} bots, {heard} OwnerStates heard, {sent} Moves sent, {dropped} lost, {held} held`
	local motion: string = string.format("moved %.2f studs on average, fastest %.2f studs/s", average, fastest)
	local holding: string = string.format("%d holds, the body moving %.2f studs at most in one", holds, farthest)
	local reports: string = HttpService:JSONEncode(made.reports[group.name] or {})

	return `{counts}, {motion}, {holding}, reports {reports}`
end

-- An NPC group's line: how many, how many awake and how far they moved on average, which an awake roaming group must
local function npcsDrove(group: Group, made: Made, problems: { string }): string
	local count: number, awake: number, moved: number = 0, 0, 0

	for _, driven: Driven in made.npcs do
		if driven.group ~= group.name then
			continue
		end

		local root: Vector3 = driven.npc:getState().root
		local x: number, z: number = root.X - driven.first.X, root.Z - driven.first.Z
		count += 1
		moved += math.sqrt(x * x + z * z)

		if driven.awake then
			awake += 1
		end
	end

	local average: number = 0
	if count > 0 then
		average = moved / count
	end

	if group.roam and awake > 0 and average < MOVED then
		table.insert(problems, `{group.name}'s NPCs moved {average} studs on average, under {MOVED}`)
	end

	return string.format("%d NPCs, %d awake, moved %.2f studs on average", count, awake, average)
end

-- A sleeper group's line: how many Tread made of the group's count, every one of which it must
local function sleepersLaid(group: Group, made: Made, problems: { string }): string
	local laid: number = 0
	for _, entry: Laid in made.sleepers do
		if entry.group == group.name then
			laid += 1
		end
	end

	if laid < group.count then
		table.insert(problems, `{group.name} made {laid} of its {group.count} sleepers`)
	end

	return `{laid} sleepers made of {group.count}`
end

--[[
    Whether every group drove: each bot heard its OwnerState and sent,
    held or lost its Moves, a roaming group's bots or awake NPCs moved on
    average, and every sleeper asked for was made. Each prints a line
--]]

local function drove(label: string, scenario: Scenario, made: Made, problems: { string })
	for _, group: Group in scenario.groups do
		local line: string = ""
		if group.kind == "npc" then
			line = npcsDrove(group, made, problems)
		elseif group.kind == "sleeper" then
			line = sleepersLaid(group, made, problems)
		else
			line = botsDrove(group, made, problems)
		end

		print(`{label} group {group.name}: {line}`)
	end
end

--[[
    Removes every body the run made, the NPCs' driver first, each under its
    own pcall, and checks that the handle lists none of them after
--]]

local function removeAll(server: Tread.Server, made: Made, problems: { string })
	local stopDriver: (() -> ())? = made.stopDriver
	if stopDriver then
		stopDriver()
	end

	local ours: { [any]: string } = {} -- Each NPC's and sleeper's group, by its handle

	for _, driven: Driven in made.npcs do
		ours[driven.npc] = driven.group

		local ended: boolean, failure: any = pcall(driven.npc.destroy, driven.npc)
		if not ended then
			table.insert(problems, `one of {driven.group}'s NPCs was not destroyed: {failure}`)
		end
	end

	for _, laid: Laid in made.sleepers do
		ours[laid.sleeper] = laid.group

		local ended: boolean, failure: any = pcall(laid.sleeper.destroy, laid.sleeper)
		if not ended then
			table.insert(problems, `one of {laid.group}'s sleepers was not destroyed: {failure}`)
		end
	end

	for _, problem: string in Fleet.clear() do
		table.insert(problems, problem)
	end

	local left: { [string]: number } = {}
	for _, target: Tread.Target in server:getAll() do
		local owner: any = (target :: any).player
		local group: string? = ours[target]

		if group then
			left[group] = (left[group] or 0) + 1
		elseif owner ~= nil and made.groups[owner] ~= nil then
			table.insert(problems, `{owner.Name}'s character is still on the server`)
		end
	end

	for group: string, count: number in left do
		table.insert(problems, `{count} of {group}'s NPCs or sleepers are still on the server`)
	end
end

--[[
    One seeded run: the layout with every viewer at any render distance
    given, the warm-up, the window with any probe beside it, and then the
    removal of everything it made, checked against what the handle lists,
    and the real players put back. A probe that started is stopped whatever
    happened
--]]

local function runSeed(
	name: string,
	scenario: Scenario,
	seed: number,
	timing: Timing,
	probe: Probe?,
	distance: number?
): (boolean, string)
	local label: string = `Bots {name} seed {seed}`
	local server: Tread.Server = Game.get()
	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return false, `{label}: Workspace.TestContent is missing, so the dev game's casts take no floor laid`
	elseif #Fleet.entries() > 0 then
		return false, `{label}: another run's {#Fleet.entries()} bots are still on the server`
	end

	local params: RaycastParams = castParams(testContent)
	local overlap: OverlapParams = overlapParams(testContent)
	local seeded: Seeded.Seeded = Seeded.new(seed)
	local offset: Vector3 = Vector3.zero
	if scenario.follow then
		offset = viewerOffset(server, scenario.viewer)
	end

	local made: Made = {
		floors = nil,
		groups = {},
		npcs = {},
		sleepers = {},
		reports = {},
		stopReports = nil,
		stopDriver = nil,
		beats = nil,
		probing = nil,
		viewers = {},
	}

	local problems: { string } = {}

	made.stopReports = server:onReport(function (player: (Player | Tread.Bot)?, kind: string, _: number | string)
		if player == nil then
			return
		end

		local group: string? = made.groups[player :: Volt.Bot]
		if group then
			local kinds: { [string]: number } = made.reports[group] or {}
			made.reports[group] = kinds
			kinds[kind] = (kinds[kind] or 0) + 1
		end
	end)

	-- Each NPC under its own xpcall, so one whose program throws stops none after it
	made.stopDriver = Fleet.onTick(function (tick: number)
		for _, driven: Driven in made.npcs do
			xpcall(steerNpc, warnNpc, driven, tick)
		end
	end)

	local ran: boolean, result: any = pcall(function (): string
		local folder: Folder, floored: number = layFloors(scenario, offset, testContent, params)
		made.floors = folder

		if not scenario.storm then
			spawnAll(scenario, seeded, offset, made, params, overlap)
			setViewers(distance, made)
		end

		print(startLine(label, scenario, offset, floored, made, distance))
		task.wait(timing.warmup)

		-- The read the window's first change counts from
		server:stats()

		if probe then
			probe.start(Fleet.entries())
			made.probing = probe
		end

		if scenario.storm then
			spawnAll(scenario, seeded, offset, made, params, overlap)
			setViewers(distance, made)
		end

		local line: string, samples: Samples = window(label, scenario, timing, made)
		drove(label, scenario, made, problems)

		if probe then
			made.probing = nil
			print(`{label} probe: {probe.stop(samples)}`)
		end

		return line
	end)

	if ran then
		print(result)
	else
		table.insert(problems, `it threw: {result}`)
	end

	-- Everything it made goes, whatever the run did
	local probing: Probe? = made.probing
	if probing then
		local stopped: boolean, stopFailure: any = pcall(probing.stop, {})
		if not stopped then
			table.insert(problems, `its probe did not stop: {stopFailure}`)
		end
	end

	local beats: RBXScriptConnection? = made.beats
	if beats then
		beats:Disconnect()
	end

	local stopReports: (() -> ())? = made.stopReports
	if stopReports then
		stopReports()
	end

	restoreViewers(made, problems)
	removeAll(server, made, problems)

	local floors: Folder? = made.floors
	if floors then
		floors:Destroy()
	end

	if #problems > 0 then
		return false, `{label}: {table.concat(problems, SEPARATOR)}`
	end

	return true, `{label}: drove and cleaned up`
end

--[[
    Runs a scenario for each of the timing's seeds in turn, after the
    server's speed calibration, a probe beside each window and every viewer
    at a render distance when given, and gives whether every run drove and
    cleaned up, with a line for each. Every read, summary and probe's line
    prints as it comes
--]]

function Run.run(name: string, timing: Timing, probe: Probe?, distance: number?): (boolean, string)
	local scenario: Scenario? = SCENARIOS[name]
	if not scenario then
		return false, `Bots {name}: no scenario has that name`
	end

	-- A run at a render distance is named for it too, in one word, so the report still drops its per-second lines
	local run: string = name
	if distance then
		run = `{name}@{distance}`
	end

	-- Before the first load, so it times nothing a load does
	local calibrated: boolean, calibration: string = Calibration.run()
	if not calibrated then
		return false, `Bots {run}: {calibration}`
	end

	print(`Bots {run} calibration: {calibration}`)

	local passed: boolean = true
	local lines: { string } = {}

	for _, seed: number in timing.seeds do
		local ok: boolean, line: string = runSeed(run, scenario, seed, timing, probe, distance)
		passed = passed and ok
		table.insert(lines, line)
	end

	return passed, table.concat(lines, SEPARATOR)
end

--[[
    The configured tick stages' times summed tick by tick, for the newest
    count ticks their rings still hold, oldest first, in seconds. Any other
    stage in the list is left out; a configured one missing, or whose ring
    stands apart from the rest, is refused
--]]

function Run.tickTotals(stages: { Tick.Stage }, count: number): { number }
	local summed: { Tick.Stage } = {}
	for _, stage: Tick.Stage in stages do
		if table.find(TICK_STAGES, stage.name) then
			table.insert(summed, stage)
		end
	end

	local first: Tick.Stage? = summed[1]
	if not first or #summed ~= #TICK_STAGES then
		error(`Run.tickTotals sums the stages {table.concat(TICK_STAGES, SUM)}, and the tick has {#summed} of them`, 2)
	end

	for _, stage: Tick.Stage in summed do
		if stage.head ~= first.head or stage.held ~= first.held then
			error(
				`Run.tickTotals sums rings that advance together, and {stage.name}'s stands apart from {first.name}'s`,
				2
			)
		end
	end

	local capacity: number = #first.times
	local totals: { number } = {}

	for back: number = math.min(count, first.held), 1, -1 do
		local index: number = (first.head - back) % capacity + 1
		local total: number = 0

		for _, stage: Tick.Stage in summed do
			total += stage.times[index]
		end

		table.insert(totals, total)
	end

	return totals
end

return Run
