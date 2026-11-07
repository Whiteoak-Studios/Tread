--[[
    One of scenarios S0 to S7 on the dev game's server, seed by seed: its
    floors and bots laid out, a warm-up, a window of Tread's stats read once
    a second and printed, and everything it made removed after
--]]

--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Bot = require(ServerScriptService.Server.Bots.Bot)
local Config = require(ServerScriptService.Server.Bots.Config)
local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Seeded = require(ServerScriptService.Server.Bots.Seeded)

local SCENARIOS: { [string]: Config.Scenario } = require(ServerScriptService.Server.Bots.Config).scenarios
local PERCENTILES: { number } = require(ServerScriptService.Server.Bots.Config).percentiles
local MOVED: number = require(ServerScriptService.Server.Bots.Config).moved
local EVERY: number = require(ServerScriptService.Server.Bots.Config).cheats.every
local HOLDS: { number } = require(ServerScriptService.Server.Bots.Config).cheats.holds
local AHEAD: { number } = require(ServerScriptService.Server.Bots.Config).cheats.ahead
local DROPS: number = require(ServerScriptService.Server.Bots.Config).cheats.drops
local FREEZE: number = require(ServerScriptService.Server.Bots.Config).cheats.freeze
local BATCH: number = require(ServerScriptService.Server.Bots.Config).spawn.batch
local LIFT: number = require(ServerScriptService.Server.Bots.Config).spawn.lift
local PROBE: number = require(ServerScriptService.Server.Bots.Config).spawn.probe
local THICKNESS: number = require(ServerScriptService.Server.Bots.Config).spawn.thickness
local SINK: number = require(ServerScriptService.Server.Bots.Config).spawn.sink
local MARGIN: number = require(ServerScriptService.Server.Bots.Config).spawn.margin
local SEED_BOUND: number = 2 ^ 31 - 2 -- The largest seed a bot's own generator is drawn
local TURN: number = 2 * math.pi
local MILLISECONDS: number = 1000 -- A second's, which stage times print in
local SEPARATOR: string = "; " -- Between the parts of one line

-- Where an area is probed for ground: its center and its corners, as shares of its half width and half depth
local PROBES: { Vector2 } = { Vector2.zero, Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.one }

type Area = Config.Area
type Group = Config.Group
type Scenario = Config.Scenario
type Timing = Config.Timing

-- What one seeded run made, all of which it removes whatever happened
type Made = {
	floors: Folder?,
	groups: { [Volt.Bot]: string }, -- Each of its bots' group
	reports: { [string]: { [string]: number } }, -- Its bots' reports by group and kind
	stopReports: (() -> ())?,
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

-- The ground's height under a point, cast down from PROBE above a height to as far below it, or nil over nothing
local function groundAt(x: number, z: number, height: number, params: RaycastParams): number?
	local origin: Vector3 = Vector3.new(x, height + PROBE, z)
	local hit: RaycastResult? = Workspace:Raycast(origin, Vector3.new(0, -2 * PROBE, 0), params)
	if not hit then
		return nil
	end

	return hit.Position.Y
end

--[[
    Lays a floor under each of a scenario's areas that has no ground at
    its center or a corner, its top just under the area's height and
    reaching past its edges, as the A0 arm lays its own
--]]

local function layFloors(scenario: Scenario, offset: Vector3, testContent: Instance, params: RaycastParams): Folder
	local folder: Folder = Instance.new("Folder")
	folder.Name = "Bots"
	folder.Parent = testContent

	local laid: { [Area]: boolean } = {}

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
				local floor: Part = Instance.new("Part")
				floor.Name = "Floor"
				floor.Anchored = true
				floor.CanCollide = true
				floor.CanQuery = true
				floor.CanTouch = false
				floor.Size = Vector3.new(area.size.X + 2 * MARGIN, THICKNESS, area.size.Y + 2 * MARGIN)
				floor.CFrame = CFrame.new(center.X, center.Y - SINK - THICKNESS / 2, center.Z)
				floor.Parent = folder
			end
		end
	end

	return folder
end

-- A seeded point of an area, on the ground there or at the area's height over nothing, facing a seeded way
local function spawnPoint(area: Area, own: Seeded.Seeded, params: RaycastParams): CFrame
	local x: number = area.center.X + own:number(-area.size.X / 2, area.size.X / 2)
	local z: number = area.center.Z + own:number(-area.size.Y / 2, area.size.Y / 2)
	local y: number = groundAt(x, z, area.center.Y, params) or area.center.Y
	local yaw: number = own:number(0, TURN)

	return CFrame.new(x, y + LIFT, z) * CFrame.Angles(0, yaw, 0)
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
    Builds every group's bots in order from the run's one seeded generator,
    each with a generator of its own, so a seed puts each bot at the same
    start and gives it the same path and the same faults, a batch a frame
--]]

local function spawnAll(scenario: Scenario, seeded: Seeded.Seeded, offset: Vector3, made: Made, params: RaycastParams)
	local context: Bot.Context = Fleet.start()
	local _, shared: Tread.Shared = Game.get()
	local index: number = 0

	for _, group: Group in scenario.groups do
		local spawn: Area = shifted(group.spawn, offset)
		local roam: Area? = group.roam and shifted(group.roam, offset)
		local speed: number = shared.step.walk

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
			local at: CFrame = spawnPoint(spawn, own, params)
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

			-- A frame between batches, each bot's client side being a module of its own to load
			if index % BATCH == 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end
end

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
local function percentile(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

-- Each figure's percentiles over the window, in one line
local function summary(samples: { [string]: { number } }): string
	local names: { string } = {}
	for name: string in samples do
		table.insert(names, name)
	end

	table.sort(names)

	local parts: { string } = {}
	for _, name: string in names do
		local values: { string } = {}
		for _, share: number in PERCENTILES do
			table.insert(values, string.format("%.3f", percentile(samples[name], share)))
		end

		table.insert(parts, `{name} {table.concat(values, "/")}`)
	end

	return table.concat(parts, SEPARATOR)
end

local function push(samples: { [string]: { number } }, name: string, value: number)
	local list: { number } = samples[name] or {}
	samples[name] = list
	table.insert(list, value)
end

--[[
    The window: Tread's stats read once each interval with the real player
    count and each real player's bytes over the last second beside it, each
    read printed as it comes, and the percentiles of every figure after.
    It ends on its own deadline
--]]

local function window(label: string, scenario: Scenario, timing: Timing): string
	local server: Tread.Server = Game.get()
	local Network = require(Packages.Tread.Network.Server) -- Tread's own scope, which each viewer's bytes are counted on
	local samples: { [string]: { number } } = {}
	local started: number = os.clock()
	local deadline: number = started + timing.window
	local stalled: boolean = false
	local second: number = 0

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
		end

		local counts: string = `real players {#real}, viewers {HttpService:JSONEncode(viewers)}`
		print(`{label} second {second}: {counts}, stats {HttpService:JSONEncode(stats)}`)

		-- A hitch half way through, once, as a live server's would come
		local stall: number? = scenario.stall
		if stall and not stalled and os.clock() - started >= timing.window / 2 then
			stalled = true
			Fleet.stall(stall)
		end
	end

	return `{label} summary over {second} reads, p50/p95/p99: {summary(samples)}`
end

--[[
    Whether every group's bots drove: each heard its OwnerState and sent,
    held or lost its Moves, and a roaming group's moved on average. Each
    group's figures and its bots' reports print as a line of their own
--]]

local function drove(label: string, scenario: Scenario, made: Made, problems: { string })
	for _, group: Group in scenario.groups do
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

		local counts: string = `{bots} bots, {heard} OwnerStates heard, {sent} Moves sent, {dropped} lost, {held} held`
		local motion: string = string.format("moved %.2f studs on average, fastest %.2f studs/s", average, fastest)
		local holding: string = string.format("%d holds, the body moving %.2f studs at most in one", holds, farthest)
		local reports: string = HttpService:JSONEncode(made.reports[group.name] or {})
		print(`{label} group {group.name}: {counts}, {motion}, {holding}, reports {reports}`)

		if silent > 0 then
			table.insert(problems, `{silent} of {group.name}'s {bots} bots heard no OwnerState or sent nothing`)
		elseif group.roam and bots > 0 and average < MOVED then
			table.insert(problems, `{group.name}'s bots moved {average} studs on average, under {MOVED}`)
		end
	end
end

--[[
    One seeded run: the layout, the warm-up, the window, and then the
    removal of everything it made, checked against what the handle lists
--]]

local function runSeed(name: string, scenario: Scenario, seed: number, timing: Timing): (boolean, string)
	local label: string = `Bots {name} seed {seed}`
	local server: Tread.Server = Game.get()
	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return false, `{label}: Workspace.TestContent is missing, so the dev game's casts take no floor laid`
	elseif #Fleet.entries() > 0 then
		return false, `{label}: another run's {#Fleet.entries()} bots are still on the server`
	end

	local params: RaycastParams = castParams(testContent)
	local seeded: Seeded.Seeded = Seeded.new(seed)
	local offset: Vector3 = Vector3.zero
	if scenario.follow then
		offset = viewerOffset(server, scenario.viewer)
	end

	local made: Made = { floors = nil, groups = {}, reports = {}, stopReports = nil }
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

	print(`{label}: starting, its areas moved {offset}, with {#Players:GetPlayers()} real players in`)

	local ran: boolean, result: any = pcall(function (): string
		made.floors = layFloors(scenario, offset, testContent, params)

		if not scenario.storm then
			spawnAll(scenario, seeded, offset, made, params)
		end

		task.wait(timing.warmup)

		-- The read the window's first change counts from
		server:stats()

		if scenario.storm then
			spawnAll(scenario, seeded, offset, made, params)
		end

		local line: string = window(label, scenario, timing)
		drove(label, scenario, made, problems)

		return line
	end)

	if ran then
		print(result)
	else
		table.insert(problems, `it threw: {result}`)
	end

	-- Everything it made goes, whatever the run did
	local stopReports: (() -> ())? = made.stopReports
	if stopReports then
		stopReports()
	end

	for _, problem: string in Fleet.clear() do
		table.insert(problems, problem)
	end

	local floors: Folder? = made.floors
	if floors then
		floors:Destroy()
	end

	for _, target: Tread.Target in server:getAll() do
		local owner: any = (target :: any).player
		if owner ~= nil and made.groups[owner] ~= nil then
			table.insert(problems, `{owner.Name}'s character is still on the server`)
		end
	end

	if #problems > 0 then
		return false, `{label}: {table.concat(problems, SEPARATOR)}`
	end

	return true, `{label}: drove and cleaned up`
end

--[[
    Runs a scenario for each of the timing's seeds in turn and gives
    whether every run drove and cleaned up, with a line for each. Every
    read and summary prints as it comes, for a run longer than one call
--]]

function Run.run(name: string, timing: Timing): (boolean, string)
	local scenario: Scenario? = SCENARIOS[name]
	if not scenario then
		return false, `Bots {name}: no scenario has that name`
	end

	local passed: boolean = true
	local lines: { string } = {}

	for _, seed: number in timing.seeds do
		local ok: boolean, line: string = runSeed(name, scenario, seed, timing)
		passed = passed and ok
		table.insert(lines, line)
	end

	return passed, table.concat(lines, SEPARATOR)
end

return Run
