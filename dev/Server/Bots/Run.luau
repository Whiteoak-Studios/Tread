--[[
    One of the bot harness's scenarios on the dev game's server, seed by
    seed after any calibration: bodies laid out at any render distance and
    relay mode, a warm-up, a window of Tread's stats and frames, all undone
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

local AntiEsp = require(Packages.Tread.Server.AntiEsp)
local Command = require(Packages.Tread.Codec.Command)
local Commands = require(Packages.Tread.Server.Commands)
local Relay = require(Packages.Tread.Server.Relay)
local Tick = require(Packages.Tread.Server.Tick)

local Bot = require(ServerScriptService.Server.Bots.Bot)
local Calibration = require(ServerScriptService.Server.Calibration)
local Cells = require(ServerScriptService.Server.Bots.Cells)
local Compare = require(ServerScriptService.Server.Bots.Compare)
local Config = require(ServerScriptService.Server.Bots.Config)
local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Seeded = require(ServerScriptService.Server.Bots.Seeded)
local Spawns = require(ServerScriptService.Server.Spawns)

local SCENARIOS: { [string]: Config.Scenario } = require(ServerScriptService.Server.Bots.Config).scenarios
local PERCENTILES: { number } = require(ServerScriptService.Server.Bots.Config).percentiles
local FPS: number = require(ServerScriptService.Server.Bots.Config).fps
local TICK_STAGES: { string } = require(ServerScriptService.Server.Bots.Config).tick.stages
local BESIDE: string = require(ServerScriptService.Server.Bots.Config).tick.beside
local COUNTS: { string } = require(ServerScriptService.Server.Bots.Config).tick.counts
local RELAY_COUNTS: { string } = require(ServerScriptService.Server.Bots.Config).tick.relayCounts
local BY_HEARTBEAT: { number } = require(ServerScriptService.Server.Bots.Config).tick.byHeartbeat
local BOTS_STAGE: string = require(ServerScriptService.Server.Bots.Config).stage
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
local P50: number = 0.5
local P95: number = 0.95
local LOOP: string = "^native loop .-p50/p95 ([%d%.]+)/" -- The calibration line's native loop p50, its first figure
local FIGURE: string = "%.3f" -- Each stats figure and stage time as the summaries print it
local RAW: string = "%.4g" -- Four significant digits, for frame times and Stats' figures, whose units differ
local SEPARATOR: string = "; " -- Between the parts of one line
local SUM: string = " + " -- Between the summed stages' names
local FINISH: string = "finish" -- What the lines call the relay's finish, which a held tick's sum takes
local VIEWS: string = "/" -- Between the workers' view counts
local STUDS: string = "%.2f" -- A distance as the real player's line prints it

-- Where an area is probed for ground: its center and its corners, as shares of its half width and half depth
local PROBES: { Vector2 } = { Vector2.zero, Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.one }

-- Each place a Heartbeat takes in its tick as the readout names it, from the one that ran the tick, the last any later
local PLACES: { string } = { "the tick's Heartbeat", "the one after", "the one after that", "later" }

type Area = Config.Area
type Figures = Compare.Figures
type Group = Config.Group
type Scenario = Config.Scenario
type Timing = Config.Timing

-- What a sum reads of a ring of times, a stage's or the finishes'
type Timed = { times: { number }, ticks: { number }, held: number, head: number }

-- Each figure the window read, a sample a read, by its name
type Samples = { [string]: { number } }

-- What the window takes of the server beside Tread's stats: each Heartbeat's interval and Stats times, a send rate a read
type Sampled = {
	frames: { number }, -- Milliseconds
	heartbeatTimes: { number },
	physicsTimes: { number },
	dataSend: { number },
	tickFrames: { number }?, -- A step half's: the milliseconds of each Heartbeat after one a tick began in
}

-- Where a step half's real player stood from its load's point as the window opened, and the studs walked read to read
export type Walked = { from: number, moved: number, last: Vector3 }

-- Verdict memory's running totals as a window last read them: the tests a kept answer settled and the rays a kept box
-- blocked
export type Memory = { kept: number, boxRays: number }

-- Tread's work each Heartbeat of a window, oldest first, taken from the tick loop's ring as the window reads
export type Readout = {
	times: { number }, -- Seconds of the tick loop's whole work in each, the bots' stage's included
	flags: { number }, -- What the loop did in each, as Tick's flags
	bots: { number }, -- Seconds of the bots' stage in each
	through: number, -- The newest Heartbeat taken, by the loop's count
	lost: number, -- Heartbeats the ring no longer held when they came to be taken
}

-- What a window took, which its closing lines and its figures are made from
export type Taken = {
	sampled: Sampled,
	elapsed: number, -- Seconds the window ran
	readout: Readout,
	totals: { number }, -- Each finished tick's summed stages and any finish, in milliseconds
	finishes: { number }, -- Each held tick's finish alone, in milliseconds
	roundsDropped: number, -- The relay's rounds given up past its timeout
	samples: Samples,
	rates: Samples, -- The configured counts over each read's ticks or relay runs
	skipped: number, -- Commands lazy decode passed over unread
	walked: Walked?, -- A step half's real player, nil for every other load and with no real player in
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
	steps: RBXScriptConnection?, -- A step half's read of the tick loop's count before each Heartbeat, while it runs
	probing: Probe?, -- The probe while it is started and not yet stopped
	viewers: { Player }, -- The real players it set a render distance for, put back after
}

local Run = {}

-- An area moved by an offset, its size kept
local function shifted(area: Area, offset: Vector3): Area
	return { center = area.center + offset, size = area.size }
end

-- The first real player's character on the server, nil while no real player has one
local function followed(server: Tread.Server): Tread.Character?
	for _, target: Tread.Target in server:getAll() do
		-- An NPC has no player, and a bot's is no Instance
		local owner: any = (target :: any).player
		if typeof(owner) == "Instance" then
			return target :: Tread.Character
		end
	end

	return nil
end

--[[
    How far a scenario's areas move so its viewer point lands on the first
    real player's character, or nowhere when no real player has one
--]]

local function viewerOffset(server: Tread.Server, viewer: Vector3): Vector3
	-- Whiteoak TODO: set the real players down at the viewer point with character:teleport once step 3 adds it, as
	-- the A0 arm does, in place of moving the scenario's areas to them
	local character: Tread.Character? = followed(server)
	if not character then
		return Vector3.zero
	end

	return character:getState().root - viewer
end

-- Where a character's root stands, nil for none or for one whose state refuses the read, as a destroyed one's does
local function rootOf(character: Tread.Character?): Vector3?
	if not character then
		return nil
	end

	local read: boolean, state: Tread.State? = pcall(character.getState, character)
	if not read or not state then
		return nil
	end

	return state.root
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
    group's team and any spectate, and a group in cells keeps each body to
    a cell of its own
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

		for place: number = 1, group.count do
			index += 1

			-- A cell draws none of the run's numbers, so a seed's bodies draw as many as they would without cells
			local bodySpawn: Area = spawn
			local bodyRoam: Area? = roam
			if group.cells then
				bodySpawn = Cells.cell(spawn, group.count, place)
				if roam then
					bodyRoam = bodySpawn
				end
			end

			local own: Seeded.Seeded = Seeded.new(seeded:integer(1, SEED_BOUND))
			local at: CFrame = spawnPoint(bodySpawn, own, params, hull, overlap)

			if group.kind == "npc" then
				addNpc(group, at, bodyRoam, own, gait, made)
			elseif group.kind == "sleeper" then
				local sleeper: Tread.Sleeper? = server:createSleeper(at, {})
				if sleeper then
					table.insert(made.sleepers, { sleeper = sleeper, group = group.name })
				end
			else
				local steer: Programs.Steer = Programs.idle()
				if bodyRoam then
					steer = Programs.roam(bodyRoam, own, gait)
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

-- A list's percentiles in one figure, the configured ones unless shares are given, each in the format given. It sorts
-- the list in place
local function spread(values: { number }, format: string, shares: { number }?): string
	local figures: { string } = {}
	for _, share: number in shares or PERCENTILES do
		table.insert(figures, string.format(format, percentile(values, share)))
	end

	return table.concat(figures, "/")
end

-- The pNN labels of a list of shares in one figure, as spread lays them out
local function labels(shares: { number }): string
	local names: { string } = {}
	for _, share: number in shares do
		table.insert(names, `p{math.round(share * PERCENT)}`)
	end

	return table.concat(names, "/")
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

--[[
    The tick stages' line: their total a tick over the window with each
    held tick's finish, the stage beside them's p95 as each read gave it,
    the finish alone over the held ticks, and the rounds the relay gave up
--]]

local function tickLine(
	label: string,
	totals: { number },
	samples: Samples,
	finishes: { number },
	dropped: number
): string
	local besideKey: string = `{BESIDE}P95Ms`
	local summed: string = `{table.concat(TICK_STAGES, SUM)}{SUM}{FINISH}`
	local parts: { string } = {
		`{label} Tread tick stages a tick, {summed}, ms p50/p95/p99 {spread(totals, FIGURE)}`,
		`{#totals} ticks`,
		`{BESIDE} p95 ms beside them, p50/p95/p99 over the reads {spread(samples[besideKey] or {}, FIGURE)}`,
		`the {FINISH} alone ms p50/p95/p99 {spread(finishes, FIGURE)} over {#finishes} held ticks`,
		`{dropped} rounds dropped`,
	}

	return table.concat(parts, SEPARATOR)
end

-- Tread's time less the bots' stage and the bots' stage's own in each Heartbeat, in milliseconds, a list a place
local function byPlace(readout: Readout): ({ { number } }, { { number } })
	local tread: { { number } } = {}
	local bots: { { number } } = {}
	for place: number = 1, #PLACES do
		tread[place] = {}
		bots[place] = {}
	end

	for index: number, place: number in Run.places(readout.flags) do
		if place > 0 then
			table.insert(tread[place], (readout.times[index] - readout.bots[index]) * MILLISECONDS)
			table.insert(bots[place], readout.bots[index] * MILLISECONDS)
		end
	end

	return tread, bots
end

--[[
    Tread's time a Heartbeat by its place in the tick at the configured
    shares, less the bots' stage, which shows apart, with the Heartbeats in
    each place, the relay's rounds in by the next Heartbeat and later, and
    the Heartbeats the ring lost before the window took them
--]]

local function heartbeatLine(label: string, readout: Readout): string
	local tread: { { number } }, bots: { { number } } = byPlace(readout)

	local parts: { string } = {}
	for place: number, name: string in PLACES do
		local own: string = spread(tread[place], FIGURE, BY_HEARTBEAT)
		local stage: string = spread(bots[place], FIGURE, BY_HEARTBEAT)
		table.insert(parts, `{name} {own} with the bots' stage {stage} over {#tread[place]}`)
	end

	local inTime: number, late: number = Run.rounds(readout.flags)
	local head: string =
		`{label} Tread ms a Heartbeat by its place in the tick, {labels(BY_HEARTBEAT)}, less the bots' stage`
	local rounds: string = `{inTime} rounds in by the next Heartbeat, {late} later`
	local lost: string = `{readout.lost} Heartbeats not read`

	return `{head}: {table.concat(parts, SEPARATOR)}{SEPARATOR}{rounds}{SEPARATOR}{lost}`
end

-- The configured counts over the window, each read's change a relay run for a relay count and a tick for the rest
local function countsLine(label: string, rates: Samples): string
	local parts: { string } = {}
	for _, name: string in COUNTS do
		local over: string = table.find(RELAY_COUNTS, name) and "relay run" or "tick"
		table.insert(parts, `{name} a {over} {spread(rates[name] or {}, FIGURE)}`)
	end

	return `{label} counts, p50/p95/p99 over the reads: {table.concat(parts, SEPARATOR)}`
end

-- The tick's stage of that name, nil while the tick has none
local function stageNamed(name: string): Tick.Stage?
	for _, stage: Tick.Stage in Tick.stages() do
		if stage.name == name then
			return stage
		end
	end

	return nil
end

--[[
    The window: the relay's mode line, then Tread's stats read once each
    interval with the real player count and each real player's bytes over
    the last second beside it, each read printed as it comes, the server's
    frames, every finished tick's summed stages and finish, Tread's time
    each Heartbeat, the counts, the relay's clocks while on, verdict memory's
    counts and the commands lazy decode skipped, their lines printed after,
    then the percentiles of every stats figure, every figure's samples and
    the figures the lines carry. Given a step half's load point, it also
    takes the interval of each Heartbeat after one a tick began in, and
    where the real player's character stood from the point and how far it
    walked read to read. It ends on its own deadline
--]]

local function window(
	label: string,
	scenario: Scenario,
	timing: Timing,
	made: Made,
	asked: boolean?,
	point: Vector3?
): (string, Samples, Figures)
	local server: Tread.Server = Game.get()
	local Network = require(Packages.Tread.Network.Server) -- Tread's own scope, which each viewer's bytes are counted on
	local samples: Samples = {}
	local rates: Samples = {}
	local sampled: Sampled = { frames = {}, heartbeatTimes = {}, physicsTimes = {}, dataSend = {} }
	local totals: { number } = {}
	local finishes: { number } = {}
	local dropped: number = 0
	local counted: number = Run.settled()
	local readout: Readout = { times = {}, flags = {}, bots = {}, through = Tick.heartbeats().count, lost = 0 }
	local tickFrames: { number } = {}
	local before: number? = nil -- The tick loop's count as this frame's simulation began, set only in a step half
	local character: Tread.Character? = nil
	local walked: Walked? = nil

	local inProcess: number, views: { number } = Relay.homes()
	print(Run.modeLine(label, Run.workers(), asked, inProcess, views))

	local started: number = os.clock()
	local deadline: number = started + timing.window
	local skippedBefore: number = Commands.skipped()
	local keptBefore: number, boxRaysBefore: number = AntiEsp.memory()
	local memory: Memory = { kept = keptBefore, boxRays = boxRaysBefore }
	local stalled: boolean = false
	local second: number = 0

	-- Disconnected as the window closes, or by the run's removal of all it made should the window throw
	local beats: RBXScriptConnection = RunService.Heartbeat:Connect(function (delta: number)
		table.insert(sampled.frames, delta * MILLISECONDS)
		table.insert(sampled.heartbeatTimes, Stats.HeartbeatTime)
		table.insert(sampled.physicsTimes, Stats.PhysicsStepTime)

		-- A Heartbeat's interval holds the last frame's work, the loop's Heartbeat counted before this one's began
		if before then
			if Run.ticked(Tick.heartbeats(), before) then
				table.insert(tickFrames, delta * MILLISECONDS)
			end

			before = nil
		end
	end)

	made.beats = beats

	-- Read before each frame's Heartbeat, so the pairing holds whichever runs first, the loop's handler or the sampler
	if point then
		sampled.tickFrames = tickFrames
		made.steps = RunService.PreSimulation:Connect(function ()
			before = Tick.heartbeats().count
		end)

		character = followed(server)
		local root: Vector3? = rootOf(character)
		if root then
			walked = { from = (root - point).Magnitude, moved = 0, last = root }
		end
	end

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

		-- The character the window opened with, until it refuses the read
		if walked then
			local root: Vector3? = rootOf(character)
			if root then
				walked.moved += (root - walked.last).Magnitude
				walked.last = root
			end
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

		Run.counts(stats, rates)
		Run.clocks(stats, samples)

		local kept: number, boxRays: number = AntiEsp.memory()
		Run.memory(memory, kept, boxRays, stats.ticks, rates)

		local relayDropped: any = stats.relayDropped
		if type(relayDropped) == "number" then
			dropped += relayDropped
		end

		-- The ticks finished since the last read, each one's stages and any finish summed from their rings, and each
		-- Heartbeat since with the bots' stage's share
		local through: number = Run.settled()
		for _, total: number in Run.tickTotals(Tick.stages(), through - counted, Tick.finishes(), through) do
			table.insert(totals, total * MILLISECONDS)
		end

		for _, time: number in Run.finishTimes(Tick.finishes(), counted, through) do
			table.insert(finishes, time * MILLISECONDS)
		end

		counted = through
		Run.takeBeats(readout, Tick.heartbeats(), stageNamed(BOTS_STAGE))
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
	local skipped: number = Commands.skipped() - skippedBefore
	beats:Disconnect()
	made.beats = nil

	local steps: RBXScriptConnection? = made.steps
	if steps then
		steps:Disconnect()
		made.steps = nil
	end

	local taken: Taken = {
		sampled = sampled,
		elapsed = elapsed,
		readout = readout,
		totals = totals,
		finishes = finishes,
		roundsDropped = dropped,
		samples = samples,
		rates = rates,
		skipped = skipped,
		walked = walked,
	}

	for _, line: string in Run.lines(label, taken) do
		print(line)
	end

	return `{label} summary over {second} reads, p50/p95/p99: {summary(samples)}`, samples, Run.figures(taken)
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
    One seeded run: the relay's mode set for the views its bots make, the
    layout with every viewer at any render distance given, the warm-up, the
    window with any probe beside it, and then the removal of everything it
    made, checked against what the handle lists, the real players put back
    and the mode off again. A probe that started is stopped whatever happened.
    A fixed run, a step benchmark half, stands on the plaza's spawn and
    tracks the real player from it. It gives the figures its window's lines
    carry too, nil when none ran
--]]

local function runSeed(
	name: string,
	scenario: Scenario,
	seed: number,
	timing: Timing,
	probe: Probe?,
	distance: number?,
	asked: boolean?,
	fixed: boolean
): (boolean, string, Figures?)
	local label: string = `Bots {name} seed {seed}`
	local server: Tread.Server = Game.get()
	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return false, `{label}: Workspace.TestContent is missing, so the dev game's casts take no floor laid`, nil
	elseif #Fleet.entries() > 0 then
		return false, `{label}: another run's {#Fleet.entries()} bots are still on the server`, nil
	end

	local params: RaycastParams = castParams(testContent)
	local overlap: OverlapParams = overlapParams(testContent)
	local seeded: Seeded.Seeded = Seeded.new(seed)
	local offset: Vector3 = Run.offset(scenario, fixed)

	-- The point a fixed run's real player is measured from, where its viewer point lands
	local point: Vector3? = nil
	if fixed then
		point = scenario.viewer + offset
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
		steps = nil,
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

	-- Each view is homed when it is made, so the mode is set before any bot joins, and put back off once they are gone
	local workers: number = Run.workers()

	local ran: boolean, result: any, figures: any = pcall(function (): (string, Figures)
		if workers > 0 then
			Relay.useWorkers(asked == true)
		end

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

		local line: string, samples: Samples, carried: Figures = window(label, scenario, timing, made, asked, point)
		drove(label, scenario, made, problems)

		if probe then
			made.probing = nil
			print(`{label} probe: {probe.stop(samples)}`)
		end

		return line, carried
	end)

	local taken: Figures? = nil
	if ran then
		print(result)
		taken = figures
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

	local steps: RBXScriptConnection? = made.steps
	if steps then
		steps:Disconnect()
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

	-- So a real player who joins between loads keeps their view in process
	if workers > 0 then
		Relay.useWorkers(false)
	end

	if #problems > 0 then
		return false, `{label}: {table.concat(problems, SEPARATOR)}`, taken
	end

	return true, `{label}: drove and cleaned up`, taken
end

--[[
    A scenario's seeds in turn after the server's speed calibration, with
    its probe, render distance, relay mode and any step benchmark half, nil
    leaving its bots' views in process and its name unmarked, and a half
    standing on the fixed ground, and whether every run drove and cleaned
    up, with a line for each, and the figures the last seed's lines carry
    with the calibration's loop beside them
--]]

local function runAll(
	name: string,
	timing: Timing,
	probe: Probe?,
	distance: number?,
	workers: boolean?,
	half: string?
): (boolean, string, Figures?)
	local scenario: Scenario? = SCENARIOS[name]
	if not scenario then
		return false, `Bots {name}: no scenario has that name`, nil
	end

	local run: string = Run.runName(name, distance, workers, half)

	-- Before the first load, so it times nothing a load does
	local calibrated: boolean, calibration: string = Calibration.run()
	if not calibrated then
		return false, `Bots {run}: {calibration}`, nil
	end

	print(`Bots {run} calibration: {calibration}`)

	local loop: number? = Run.calibrated(calibration)
	local passed: boolean = true
	local lines: { string } = {}
	local figures: Figures? = nil

	for _, seed: number in timing.seeds do
		local ok: boolean, line: string, carried: Figures? =
			runSeed(run, scenario, seed, timing, probe, distance, workers, half ~= nil)
		passed = passed and ok
		table.insert(lines, line)

		if carried and loop then
			carried.calibration = loop
		end

		figures = carried
	end

	return passed, table.concat(lines, SEPARATOR), figures
end

--[[
    Runs a scenario for each of the timing's seeds in turn, after the
    server's speed calibration, a probe beside each window and every viewer
    at a render distance when given, its bots' views in process, and gives
    whether every run drove and cleaned up, with a line for each. Every
    read, summary and probe's line prints as it comes
--]]

function Run.run(name: string, timing: Timing, probe: Probe?, distance: number?): (boolean, string)
	local passed: boolean, line: string = runAll(name, timing, probe, distance, nil, nil)

	return passed, line
end

--[[
    Runs a scenario as Run.run does, with its bots' views on the relay's
    workers when workers is true and the server started some, and in
    process otherwise, its name marked with the step benchmark's half when
    one is given, which stands on the plaza's spawn, and with the mode it
    asked for otherwise. It gives the figures its last seed's lines carry
    too, nil when no window ran
--]]

function Run.runWorkers(
	name: string,
	timing: Timing,
	workers: boolean,
	probe: Probe?,
	half: string?
): (boolean, string, Figures?)
	return runAll(name, timing, probe, nil, workers, half)
end

--[[
    What a run's lines call it: the scenario's name, marked with any render
    distance, then with the step benchmark's half when one is given and the
    relay mode it asked for otherwise, in one word, so the report still drops
    its per-second lines
--]]

function Run.runName(name: string, distance: number?, workers: boolean?, half: string?): string
	local run: string = name
	if distance then
		run = `{name}@{distance}`
	end

	if half then
		run = `{run}/{half}`
	elseif workers == true then
		run = `{run}/workers`
	elseif workers == false then
		run = `{run}/serial`
	end

	return run
end

-- The native loop's p50 a calibration line gives first, nil for a line that gives none
function Run.calibrated(line: string): number?
	local matched: string? = string.match(line, LOOP)

	return matched and tonumber(matched)
end

-- How many relay workers the running dev server started with, 0 for none
function Run.workers(): number
	local _, _, settings: Tread.ServerSettings = Game.get()
	local relay: { read workers: number? }? = settings.relay
	if relay and relay.workers then
		return relay.workers
	end

	return 0
end

--[[
    How far a scenario's areas move: a following scenario's so its viewer
    point lands on the plaza's first spawn point when fixed, as every step
    benchmark half's does, and on the first real player's character
    otherwise, and a scenario that follows no one's nowhere
--]]

function Run.offset(scenario: Scenario, fixed: boolean): Vector3
	if not scenario.follow then
		return Vector3.zero
	elseif fixed then
		return Spawns.first() - scenario.viewer
	end

	return viewerOffset(Game.get(), scenario.viewer)
end

--[[
    The newest tick whose work is all done, its relay's finish included:
    the newest the tick loop ran, or the one before while that one is held
--]]

function Run.settled(): number
	local ran: number = Tick.counts()
	if Tick.holding() then
		return ran - 1
	end

	return ran
end

--[[
    The line naming a run's relay mode at its window's start: the workers
    the server started, whether this load has its bots' views on them, which
    one asking for them on a server with none says it doesn't, and how many
    views are in process and on each worker
--]]

function Run.modeLine(label: string, started: number, asked: boolean?, inProcess: number, views: { number }): string
	local inside: string = `views {inProcess} in process`
	if started == 0 then
		local mode: string = "no relay workers started"
		if asked then
			mode = `{mode}, so this load, which asked for them, runs serial`
		end

		return `{label} mode: {mode}; {inside}`
	end

	local on: string = "off"
	if asked then
		on = "on"
	end

	local homes: string = `{table.concat(views, VIEWS)} on the workers`

	return `{label} mode: {started} relay workers started, {on} for this load; {inside}, {homes}`
end

-- Adds each time a ring holds onto the total of the tick it ran on, newest first, from newest back to the oldest
local function addTimes(totals: { number }, ring: Timed, oldest: number, newest: number)
	local size: number = #ring.times

	for back: number = 1, ring.held do
		local index: number = (ring.head - back) % size + 1
		local tick: number = ring.ticks[index]
		if tick < oldest then
			break
		elseif tick <= newest then
			totals[tick - oldest + 1] += ring.times[index]
		end
	end
end

--[[
    The configured tick stages' times summed tick by tick, oldest first, in
    seconds: the newest count ticks to the newest any of them ran on, or to
    through when given, at most the longest ring's length and none before
    the oldest their rings hold, each the time of every configured stage
    that ran on that tick and of the finish of a held one, given finishes.
    Any other stage is left out. A configured one missing is refused, and so
    is one whose ring is full and holds no tick as old as the window's
    oldest, since it may have run on a tick of the window it no longer holds
--]]

function Run.tickTotals(stages: { Tick.Stage }, count: number, finishes: Tick.Ring?, through: number?): { number }
	local summed: { Tick.Stage } = {}
	local newest: number = 0
	local floor: number = math.huge -- The oldest tick any of their rings holds
	local length: number = 0

	for _, stage: Tick.Stage in stages do
		if table.find(TICK_STAGES, stage.name) then
			local size: number = #stage.times
			table.insert(summed, stage)
			length = math.max(length, size)

			if stage.held > 0 then
				newest = math.max(newest, stage.ticks[(stage.head - 1) % size + 1])
				floor = math.min(floor, stage.ticks[(stage.head - stage.held) % size + 1])
			end
		end
	end

	if #summed ~= #TICK_STAGES then
		error(`Run.tickTotals sums the stages {table.concat(TICK_STAGES, SUM)}, and the tick has {#summed} of them`, 2)
	end

	if through then
		newest = math.min(newest, through)
	end

	local oldest: number = math.max(newest - math.min(count, length) + 1, floor)
	local totals: { number } = table.create(math.max(newest - oldest + 1, 0), 0)

	for _, stage: Tick.Stage in summed do
		local size: number = #stage.times
		local first: number = stage.ticks[(stage.head - stage.held) % size + 1] -- The oldest tick its ring holds

		if stage.held == size and first > oldest then
			error(
				`Run.tickTotals sums ticks {oldest} to {newest}, and {stage.name}'s full ring holds none before {first}`,
				2
			)
		end

		addTimes(totals, stage, oldest, newest)
	end

	-- A finish is kept once a tick a time, so its ring, as long as the stages', always reaches the window's oldest
	if finishes then
		addTimes(totals, finishes, oldest, newest)
	end

	return totals
end

-- The finishes' times, in seconds, of the held ticks after one tick and up to another, newest first
function Run.finishTimes(finishes: Tick.Ring, after: number, through: number): { number }
	local size: number = #finishes.times
	local times: { number } = {}

	for back: number = 1, finishes.held do
		local index: number = (finishes.head - back) % size + 1
		local tick: number = finishes.ticks[index]
		if tick <= after then
			break
		elseif tick <= through then
			table.insert(times, finishes.times[index])
		end
	end

	return times
end

--[[
    Takes each Heartbeat the tick loop's ring holds since the readout's
    newest into it, oldest first, with the time the bots' stage took in it
    from that stage's ring by the Heartbeat each run came in, and counts as
    lost any the ring no longer holds
--]]

function Run.takeBeats(readout: Readout, beats: Tick.Heartbeats, bots: Tick.Stage?)
	local newest: number = beats.count
	local fresh: number = newest - readout.through
	local taken: number = math.min(fresh, beats.held)
	readout.lost += fresh - taken

	local inBeat: { [number]: number } = {}
	if bots then
		local size: number = #bots.times
		for back: number = 1, bots.held do
			local index: number = (bots.head - back) % size + 1
			local beat: number = bots.beats[index]
			if beat <= readout.through then
				break
			end

			inBeat[beat] = (inBeat[beat] or 0) + bots.times[index]
		end
	end

	local size: number = #beats.times
	for beat: number = newest - taken + 1, newest do
		local index: number = (beats.head - (newest - beat) - 1) % size + 1
		table.insert(readout.times, beats.times[index])
		table.insert(readout.flags, beats.flags[index])
		table.insert(readout.bots, inBeat[beat] or 0)
	end

	readout.through = newest
end

--[[
    Each Heartbeat's place in its tick, oldest first: 1 for one a tick began
    in, 2 for the next, 3 for the one after, the last place for any later,
    and 0 for one before the first a tick began in
--]]

function Run.places(flags: { number }): { number }
	local places: { number } = table.create(#flags, 0)
	local place: number = 0

	for index: number, flag: number in flags do
		if bit32.btest(flag, Tick.TICKED) then
			place = 1
		elseif place > 0 then
			place = math.min(place + 1, #PLACES)
		end

		places[index] = place
	end

	return places
end

-- Whether the tick loop's Heartbeat of that count began a tick, false for one its ring holds no longer or not yet
function Run.ticked(beats: Tick.Heartbeats, count: number): boolean
	if count < 1 or count > beats.count or count <= beats.count - beats.held then
		return false
	end

	return bit32.btest(beats.flags[(count - 1) % #beats.flags + 1], Tick.TICKED)
end

--[[
    The relay's rounds over a window's Heartbeats, one for each Heartbeat a
    round went out in, held as it ended: one a tick began in, or one a
    deferred tick's rest ran in. How many the next Heartbeat's poll
    released, and how many it didn't. The newest, with no Heartbeat after
    it, counts as neither
--]]

function Run.rounds(flags: { number }): (number, number)
	local dispatching: number = bit32.bor(Tick.TICKED, Tick.DEFERRED)
	local inTime: number, late: number = 0, 0

	for index: number = 1, #flags - 1 do
		local flag: number = flags[index]
		if bit32.btest(flag, Tick.HELD) and bit32.btest(flag, dispatching) then
			if bit32.btest(flags[index + 1], Tick.RELEASED) then
				inTime += 1
			else
				late += 1
			end
		end
	end

	return inTime, late
end

--[[
    The split by stage over a window's Heartbeats: the ticks deferred, one
    for each Heartbeat a deferred tick's rest ran in, and the fallbacks, each
    a tick run whole right after one that deferred. A tick deferred when the
    Heartbeat after it ran a rest, so the newest, with none after it, is
    neither deferred nor whole
--]]

function Run.deferrals(flags: { number }): (number, number)
	local deferred: number, fallbacks: number = 0, 0
	local before: boolean = false -- Whether the tick before deferred

	for index: number, flag: number in flags do
		if bit32.btest(flag, Tick.DEFERRED) then
			deferred += 1
		end

		local after: number? = flags[index + 1]
		if after and bit32.btest(flag, Tick.TICKED) then
			local defers: boolean = bit32.btest(after, Tick.DEFERRED)
			if before and not defers then
				fallbacks += 1
			end

			before = defers
		end
	end

	return deferred, fallbacks
end

--[[
    A stats read's configured counts pushed onto samples, a relay count
    over the read's relay runs, its ticks less the relay ticks it skipped,
    and the rest over its ticks, then the viewer-player pairs past the
    crowd cap over its relay runs, anti-ESP's rays over its ticks and its
    workers' busy seconds as milliseconds a second of the read, which only
    the step benchmark's table reads. A figure whose divisor is none is left
    out, as a read whose ticks all dropped gives, or a short one charged
    with relay ticks skipped before it, since they count at the next run
--]]

function Run.counts(stats: { [string]: any }, samples: Samples)
	local ticks: any, skipped: any = stats.ticks, stats.relaySkipped
	if type(ticks) ~= "number" or type(skipped) ~= "number" then
		return
	end

	for _, name: string in COUNTS do
		local count: any = stats[name]
		local over: number = ticks
		if table.find(RELAY_COUNTS, name) then
			over -= skipped
		end

		if type(count) == "number" and over > 0 then
			push(samples, name, count / over)
		end
	end

	-- Each viewer's turn adds its candidates past the cap's size, so a relay run's is those pairs over every viewer
	local rest: any = stats.crowdRest
	if type(rest) == "number" and ticks - skipped > 0 then
		push(samples, "crowdRest", rest / (ticks - skipped))
	end

	local rays: any, busy: any, seconds: any = stats.antiEspRays, stats.antiEspWorkerBusy, stats.seconds
	if type(rays) == "number" and ticks > 0 then
		push(samples, "antiEspRays", rays / ticks)
	end

	-- Only a server that made anti-ESP's workers reads their busy time
	if type(busy) == "number" and type(seconds) == "number" and seconds > 0 then
		push(samples, "antiEspWorkerBusy", busy / seconds * MILLISECONDS)
	end
end

--[[
    A read of verdict memory's running totals pushed onto rates as each
    one's change since the window's last read over the read's ticks, the
    tests a kept answer settled as antiEspKept and the rays a kept box
    blocked as antiEspBoxRays, and kept as the last read. A read with no
    ticks pushes neither, as Run.counts leaves out its rays
--]]

function Run.memory(last: Memory, kept: number, boxRays: number, ticks: any, rates: Samples)
	if type(ticks) == "number" and ticks > 0 then
		push(rates, "antiEspKept", (kept - last.kept) / ticks)
		push(rates, "antiEspBoxRays", (boxRays - last.boxRays) / ticks)
	end

	last.kept = kept
	last.boxRays = boxRays
end

--[[
    A stats read's relay clocks pushed onto samples, each section's newest
    run in milliseconds as clock <name>Ms. A read with relay.clocks off
    carries none and pushes nothing
--]]

function Run.clocks(stats: { [string]: any }, samples: Samples)
	local clocks: any = stats.relayClocks
	if type(clocks) ~= "table" then
		return
	end

	for name: string, times: any in clocks do
		push(samples, `clock {name}Ms`, times.last * MILLISECONDS)
	end
end

--[[
    The relay clocks' line over the window, each section's newest run at
    the configured shares over the reads, in the relay's own order, with
    the two measured across a worker's clock and the main thread's last.
    Nil when no read carried the clocks
--]]

function Run.clocksLine(label: string, samples: Samples): string?
	local parts: { string } = {}
	for _, name: string in Relay.CLOCKS do
		local times: { number }? = samples[`clock {name}Ms`]
		if times then
			table.insert(parts, `{name} {spread(times, FIGURE)}`)
		end
	end

	if #parts == 0 then
		return nil
	end

	local head: string = `{label} relay clocks, ms p50/p95/p99 over the reads`
	local across: string = "delivery and back across a worker's clock and the main thread's"

	return `{head}, {across}: {table.concat(parts, SEPARATOR)}`
end

--[[
    The lines a window prints as it closes, in order: the server's, Tread's
    time a Heartbeat by its place in the tick, the tick stages', the counts',
    a step half's real player's while it had one and, while any read carried
    them, the relay clocks'
--]]

function Run.lines(label: string, taken: Taken): { string }
	local lines: { string } = {
		serverLine(label, taken.sampled, taken.elapsed),
		heartbeatLine(label, taken.readout),
		tickLine(label, taken.totals, taken.samples, taken.finishes, taken.roundsDropped),
		countsLine(label, taken.rates),
	}

	local walked: Walked? = taken.walked
	if walked then
		local from: string = `{string.format(STUDS, walked.from)} studs from the load's point as the window opened`
		table.insert(lines, `{label} real player: {from}, {string.format(STUDS, walked.moved)} walked in it`)
	end

	local clocks: string? = Run.clocksLine(label, taken.samples)
	if clocks then
		table.insert(lines, clocks)
	end

	return lines
end

-- Puts a list's value at a share under a name, unless the list has none
local function put(figures: Figures, name: string, values: { number }?, share: number)
	if values and #values > 0 then
		figures[name] = percentile(values, share)
	end
end

-- Puts a list's sum under a name, unless there is no list
local function total(figures: Figures, name: string, values: { number }?)
	if not values then
		return
	end

	local sum: number = 0
	for _, value: number in values do
		sum += value
	end

	figures[name] = sum
end

--[[
    The figures a window's lines carry, by the names the step benchmark's
    table reads: any real player's distance and walk, the frames, Tread's
    time on the place in the tick with the largest p95 with the bots' stage
    there and on each of the first three places, the ticks deferred and the
    split's fallbacks, any frame holding a tick, the tick total, each stage,
    the finish, the send time, anti-ESP's figures, verdict memory's and any
    workers', the frame caps' counts, the counts with the crowd cap's rest a
    relay run, the viewer's bytes, any OwnerState sends and checks, the
    commands lazy decode skipped and any relay clocks. One with no samples
    is left out
--]]

function Run.figures(taken: Taken): Figures
	local figures: Figures = {}
	local frames: { number } = taken.sampled.frames
	local samples: Samples = taken.samples

	local rates: { number } = {}
	for _, frame: number in frames do
		table.insert(rates, MILLISECONDS / frame)
	end

	if taken.elapsed > 0 then
		figures.heartbeats = #frames / taken.elapsed
	end

	local walked: Walked? = taken.walked
	if walked then
		figures.playerFrom = walked.from
		figures.playerMoved = walked.moved
	end

	put(figures, "fps", rates, FPS)
	put(figures, "frameP50", frames, P50)
	put(figures, "frameP95", frames, P95)

	-- The heaviest place in the tick is the one whose p95 of Tread's time is largest, the first of any that tie
	local tread: { { number } }, bots: { { number } } = byPlace(taken.readout)
	local heaviest: number = 0
	local largest: number = 0
	for place: number = 1, #PLACES do
		local own: { number } = tread[place]
		local p95: number = percentile(own, P95)
		if #own > 0 and (heaviest == 0 or p95 > largest) then
			heaviest, largest = place, p95
		end
	end

	if heaviest > 0 then
		put(figures, "treadP50", tread[heaviest], P50)
		figures.treadP95 = largest
		put(figures, "botsP50", bots[heaviest], P50)
		put(figures, "botsP95", bots[heaviest], P95)
	end

	-- Tread's time on each place in the tick but the last, which gathers every later one
	for place: number = 1, #PLACES - 1 do
		put(figures, `place{place}P50`, tread[place], P50)
		put(figures, `place{place}P95`, tread[place], P95)
	end

	local flags: { number } = taken.readout.flags
	if #flags > 0 then
		figures.deferred, figures.fallbacks = Run.deferrals(flags)
	end

	put(figures, "tickFrameP50", taken.sampled.tickFrames, P50)
	put(figures, "tickFrameP95", taken.sampled.tickFrames, P95)
	put(figures, "tickP50", taken.totals, P50)
	put(figures, "tickP95", taken.totals, P95)

	for _, stage: string in TICK_STAGES do
		put(figures, stage, samples[`{stage}Ms`], P50)
	end

	put(figures, FINISH, taken.finishes, P50)

	-- The send time, a smoothed level in seconds at each read, at p50 over the reads in milliseconds
	local send: { number }? = samples.relaySend
	if send and #send > 0 then
		figures.relaySend = percentile(send, P50) * MILLISECONDS
	end

	put(figures, BESIDE, samples[`{BESIDE}P95Ms`], P50)
	put(figures, "antiEspTests", taken.rates.antiEspTests, P50)
	put(figures, "antiEspRays", taken.rates.antiEspRays, P50)
	put(figures, "antiEspKept", taken.rates.antiEspKept, P50)
	put(figures, "antiEspBoxRays", taken.rates.antiEspBoxRays, P50)
	total(figures, "antiEspHidden", samples.antiEspHidden)
	total(figures, "antiEspFailOpens", samples.antiEspFailOpens)
	total(figures, "antiEspWorkerTests", samples.antiEspWorkerTests)
	put(figures, "antiEspWorkerBusy", taken.rates.antiEspWorkerBusy, P50)
	total(figures, "antiEspLateBatches", samples.antiEspLateBatches)
	total(figures, "dropped", samples.dropped)
	total(figures, "relaySkipped", samples.relaySkipped)
	total(figures, "npcsWaited", samples.npcsWaited)
	total(figures, "antiEspCut", samples.antiEspCut)
	total(figures, "relayLeft", samples.relayLeft)
	total(figures, "relayOver", samples.relayOver)
	total(figures, "farHalved", samples.farHalved)
	put(figures, "records", taken.rates.recordsSent, P50)
	put(figures, "recordsCut", taken.rates.recordsCut, P50)
	put(figures, "crowdRest", taken.rates.crowdRest, P50)
	put(figures, "bytes", taken.rates.bytesOut, P50)

	-- The longest batch a read gave, in seconds, at p95 over the reads in milliseconds
	local longest: { number }? = samples.antiEspWorkerLongest
	if longest and #longest > 0 then
		figures.antiEspWorkerLongest = percentile(longest, P95) * MILLISECONDS
	end

	put(figures, "viewerP50", samples.viewerBytes, P50)
	put(figures, "viewerP95", samples.viewerBytes, P95)
	total(figures, "ownerFull", samples.ownerFull)
	total(figures, "ownerAcks", samples.ownerAcks)
	total(figures, "ownerChecked", samples.ownerChecked)
	total(figures, "ownerMismatches", samples.ownerMismatches)
	figures.skipped = taken.skipped

	for _, name: string in Relay.CLOCKS do
		local times: { number }? = samples[`clock {name}Ms`]
		put(figures, `clock {name} p50`, times, P50)
		put(figures, `clock {name} p95`, times, P95)
	end

	return figures
end

return Run
