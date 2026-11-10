--[[
    G7's hit agreement: each shooter's own view of its fixture shots, which
    the dev client reports over the dev scope's shot, paired with what the
    server's fixture struck, and the run that has the dev client fire them
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local Programs = require(ServerScriptService.Server.Bots.Programs)
local Seeded = require(ServerScriptService.Server.Bots.Seeded)
local Shots = require(ServerScriptService.Server.Fixtures.Shots)

local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Hits).rate
local SPOT: Vector3 = require(ServerScriptService.Server.Config.Hits).spot
local FLOOR: Vector3 = require(ServerScriptService.Server.Config.Hits).floor
local BEHIND: number = require(ServerScriptService.Server.Config.Hits).behind
local LIFT: number = require(ServerScriptService.Server.Config.Hits).lift
local WIDTH: number = require(ServerScriptService.Server.Config.Hits).width
local SETTLE: number = require(ServerScriptService.Server.Config.Hits).settle
local WARMUP: number = require(ServerScriptService.Server.Config.Hits).warmup
local DRAIN: number = require(ServerScriptService.Server.Config.Hits).drain
local INTERVAL: number = require(ServerScriptService.Server.Config.Hits).interval
local SEED: number = require(ServerScriptService.Server.Config.Hits).seed
local SEQUENCES: number = 2 ^ 6 -- The values a shot's 6-bit sequence holds, as the dev table declares it
local HALF: number = SEQUENCES / 2 -- A report this far or more past the newest is read as one before it
local STOP: number = 0 -- The slot shoot names to stop firing
local SEED_BOUND: number = 2 ^ 31 - 2 -- The largest seed a bot's own generator is drawn
local TURN: number = 2 * math.pi
local MILLISECONDS: number = 1000
local MEDIAN: number = 0.5
local PERCENT: number = 100
local FOLDER: string = "HitAgreement" -- The folder the run lays its floor in
local GROUP: string = "hits" -- What the fleet's entries call the run's targets
local SEPARATOR: string = "; " -- Between the parts of one line

type Key = Player | Volt.Bot

-- One report a shooter's view sent: its counter unwrapped against the reports before it, and the slot it struck
export type Report = {
	counter: number,
	target: number?, -- nil for a miss
}

-- One case of the run: the weapon fired, its targets and how they move, and how long it fires
export type Case = {
	name: string,
	weapon: number, -- The hotbar slot shoot names
	sprint: boolean, -- Whether the targets roam their band at a sprint, or stand idle
	count: number,
	near: number, -- Studs ahead of the spot the targets' band begins
	far: number, -- And ends
	seconds: number,
}

-- What pairing one shooter's reports with the fixture's results found
export type Tally = {
	paired: number,
	lost: number, -- Reports with no result, whose command the server never ran
	unpaired: number, -- Results with no report
	either: number, -- Paired shots either side saw hit a body
	agree: number, -- Paired shots both sides saw hit the same body, whatever the zone
	clientOnly: number, -- The shooter's view hit and the server missed
	serverOnly: number, -- The server hit and the shooter's view missed
	otherBody: number, -- Both hit, different bodies
	clientHits: number, -- Paired shots the shooter's view saw hit
	misses: { [string]: number }, -- Every result the server missed, by its reason
	outside: number, -- Results whose claim lay outside the band
	eitherRate: number?, -- agree over either, nil with none
	pairedRate: number?, -- agree over paired
	clientRate: number?, -- agree over clientHits
}

-- A shooter's reports and the newest counter among them
type Record = {
	reports: { Report },
	newest: number,
}

local Records: { [Key]: Record } = {} -- Each reporting shooter's since the last clear, dropped when they leave
local Started: boolean = false

local Hits = {}

--[[
    The counter whose low 6 bits a report carries nearest the newest so
    far: up to one short of half the counter's range ahead of it, or behind
    it, since reports arrive in the order their bullets resolved
--]]

function Hits.unwrap(newest: number, wire: number): number
	local ahead: number = (wire - newest) % SEQUENCES
	if ahead >= HALF then
		ahead -= SEQUENCES
	end

	return newest + ahead
end

-- A report arrived: kept under its sender, its counter unwrapped
local function heard(key: Key, sequence: number, target: number?)
	local record: Record? = Records[key]
	if not record then
		record = { reports = {}, newest = -1 }
		Records[key] = record
	end

	local kept: Record = record :: Record
	local counter: number = Hits.unwrap(kept.newest, sequence % SEQUENCES)
	kept.newest = math.max(kept.newest, counter)
	table.insert(kept.reports, { counter = counter, target = target })
end

--[[
    Binds the shot event at the dev game's own rate and keeps what arrives
    on it by sender. It runs once a server, and both its listener and its
    leave, which forgets a sender who left, live as long as the server
--]]

function Hits.start()
	if Started then
		error("Hits.start runs once a server, and it has already run", 2)
	end

	Started = true
	Network.rate("shot", RATE.perSecond, RATE.burst)
	Network.shot.on(heard)
	Network.onLeave(function (key: Key)
		Records[key] = nil
	end)
end

-- A sender's reports since the last clear, the module's own list, empty for one that sent none
function Hits.reports(key: Key): { Report }
	local record: Record? = Records[key]
	if not record then
		return {}
	end

	return record.reports
end

-- Forgets every report, for a case that starts counting afresh
function Hits.clear()
	table.clear(Records)
end

-- A share as a percentage to a tenth, or a dash with nothing to divide by
local function percent(rate: number?): string
	if rate == nil then
		return "-"
	end

	return string.format("%.1f%%", rate * PERCENT)
end

-- A count over a total, nil with no total
local function over(count: number, total: number): number?
	if total == 0 then
		return nil
	end

	return count / total
end

--[[
    Pairs one shooter's reports with its fixture results: the results in
    the order they were fired, each 6-bit sequence unwrapped against the one
    before, so a lost command leaves a gap while fewer than 64 go missing in
    a row, and each matched to the report of the same counter. Pure
--]]

function Hits.pair(reports: { Report }, results: { Shots.Result }): Tally
	local tally: Tally = {
		paired = 0,
		lost = 0,
		unpaired = 0,
		either = 0,
		agree = 0,
		clientOnly = 0,
		serverOnly = 0,
		otherBody = 0,
		clientHits = 0,
		misses = {},
		outside = 0,
		eitherRate = nil,
		pairedRate = nil,
		clientRate = nil,
	}

	local byCounter: { [number]: Report } = {}
	for _, report: Report in reports do
		byCounter[report.counter] = report
	end

	-- Fired once a command, so a tick names one shot
	local fired: { Shots.Result } = table.clone(results)
	table.sort(fired, function (a: Shots.Result, b: Shots.Result): boolean
		return a.fired < b.fired
	end)

	local counter: number = -1

	for _, result: Shots.Result in fired do
		local step: number = (result.sequence - counter) % SEQUENCES
		if step == 0 then
			step = SEQUENCES
		end

		counter += step

		local strike: Shots.Strike? = result.strike
		local reason: string? = result.reason
		if not strike and reason then
			tally.misses[reason] = (tally.misses[reason] or 0) + 1
		end

		if not result.inside then
			tally.outside += 1
		end

		local report: Report? = byCounter[counter]
		if not report then
			tally.unpaired += 1
			continue
		end

		byCounter[counter] = nil
		tally.paired += 1

		-- The struck character's slot, which a handle keeps private, against the slot alone the client reports
		local server: number? = strike and (strike.target :: any)._slot
		local client: number? = report.target

		if client ~= nil then
			tally.clientHits += 1
		end

		if server ~= nil or client ~= nil then
			tally.either += 1
		end

		if server ~= nil and server == client then
			tally.agree += 1
		elseif server ~= nil and client ~= nil then
			tally.otherBody += 1
		elseif client ~= nil then
			tally.clientOnly += 1
		elseif server ~= nil then
			tally.serverOnly += 1
		end
	end

	for _ in byCounter do
		tally.lost += 1
	end

	tally.eitherRate = over(tally.agree, tally.either)
	tally.pairedRate = over(tally.agree, tally.paired)
	tally.clientRate = over(tally.agree, tally.clientHits)

	return tally
end

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
local function percentile(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

--[[
    One case's line: every rate, since which shots the agreement is taken
    over is still open, the counts behind them, the server's misses by
    reason, the claims outside the band, what went unpaired, and the p50 of
    the pings measured
--]]

function Hits.line(name: string, tally: Tally, pings: { number }): string
	local reasons: { string } = {}
	for reason: string, count: number in tally.misses do
		table.insert(reasons, `{reason} {count}`)
	end

	table.sort(reasons)

	local missed: string = "none"
	if #reasons > 0 then
		missed = table.concat(reasons, ", ")
	end

	local ping: string =
		string.format("ping p50 %.0f ms over %d reads", percentile(pings, MEDIAN) * MILLISECONDS, #pings)
	local either: string = `agreement {percent(tally.eitherRate)} of {tally.either} either side hit`
	local paired: string = `{percent(tally.pairedRate)} of {tally.paired} paired`
	local client: string = `{percent(tally.clientRate)} of {tally.clientHits} the shooter saw hit`
	local sides: string =
		`{tally.agree} agreed, {tally.clientOnly} client only, {tally.serverOnly} server only, {tally.otherBody} other body`
	local rest: string = `{tally.outside} outside the band, {tally.lost} reports and {tally.unpaired} results unpaired`
	local parts: { string } = { ping, `{either}, {paired}, {client}`, sides, `server misses {missed}`, rest }

	return `HitAgreement {name}: {table.concat(parts, SEPARATOR)}`
end

-- The first real player holding a character, with it, or nil
local function shooterOf(Game: any): (Player?, Tread.Character?)
	for _, player: Player in Players:GetPlayers() do
		local character: Tread.Character? = Game.characterOf(player)
		if character then
			return player, character
		end
	end

	return nil, nil
end

--[[
    One case: its targets built in their band ahead of the spot from the
    case's seeded generator, a warm-up, the counts cleared, the shooter told
    to fire for the case's seconds while its ping is read once a second, a
    drain, and the pairing's line. Its targets go after
--]]

local function runCase(Fleet: any, case: Case, player: Player, character: Tread.Character, shared: Tread.Shared): string
	local seeded: Seeded.Seeded = Seeded.new(SEED)
	local depth: number = case.far - case.near
	local center: Vector3 = SPOT - Vector3.new(0, 0, (case.near + case.far) / 2)
	local area: { center: Vector3, size: Vector2 } = { center = center, size = Vector2.new(WIDTH, depth) }
	local gait: Programs.Gait = {
		speed = shared.step.sprint,
		rate = shared.rates.simulation,
		sprint = true,
		crouch = false,
		long = false,
	}

	for index: number = 1, case.count do
		local own: Seeded.Seeded = Seeded.new(seeded:integer(1, SEED_BOUND))
		local x: number = center.X + own:number(-WIDTH / 2, WIDTH / 2)
		local z: number = center.Z + own:number(-depth / 2, depth / 2)
		local at: CFrame = CFrame.new(x, SPOT.Y + LIFT, z) * CFrame.Angles(0, own:number(0, TURN), 0)
		local steer: Programs.Steer = case.sprint and Programs.roam(area, own, gait) or Programs.idle()

		Fleet.add({
			name = `Hit{index}`,
			group = GROUP,
			at = at,
			steer = steer,
			faults = nil,
			seed = own:integer(1, SEED_BOUND),
		})
	end

	task.wait(WARMUP)
	Shots.clear()
	Hits.clear()
	Network.shoot.fire(player, case.weapon)

	local pings: { number } = {}
	for _ = 1, math.floor(case.seconds / INTERVAL) do
		task.wait(INTERVAL)
		table.insert(pings, player:GetNetworkPing())
	end

	Network.shoot.fire(player, STOP)
	task.wait(DRAIN)

	local mine: { Shots.Result } = {}
	for _, result: Shots.Result in Shots.results() do
		if result.shooter == character then
			table.insert(mine, result)
		end
	end

	local line: string = Hits.line(case.name, Hits.pair(Hits.reports(player), mine), pings)
	print(line)

	return line
end

--[[
    G7's run: refused beside other fleet bots or with no real player who
    has a character. It lays a floor away from everything, teleports the
    shooter onto its spot, runs each case, then takes the floor away,
    respawns the shooter and checks nothing it made is left. It passes when
    it ran cleanly and judges no gate. Every wait is its own deadline
--]]

function Hits.run(cases: { Case }): (boolean, string)
	-- Required here, so the binding and the pairing load without the dev game, as their cases load them
	local Fleet: any = require(ServerScriptService.Server.Bots.Fleet)
	local Game: any = require(ServerScriptService.Server.Game)

	local server: Tread.Server, shared: Tread.Shared = Game.get()
	Fleet.start()
	if #Fleet.entries() > 0 then
		return false, `another run's {#Fleet.entries()} bots are still on the server`
	end

	local player: Player?, character: Tread.Character? = shooterOf(Game)
	if not player or not character then
		return false, "no real player has a character to shoot from"
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
	floor.CFrame = CFrame.new(SPOT + Vector3.new(0, -FLOOR.Y / 2, BEHIND - FLOOR.Z / 2))
	floor.Parent = folder
	folder.Parent = testContent

	local lines: { string } = {}
	local problems: { string } = {}
	local ran: boolean, failure: any = pcall(function ()
		character:teleport(CFrame.new(SPOT + Vector3.new(0, LIFT, 0)))
		task.wait(SETTLE)

		for _, case: Case in cases do
			table.insert(lines, runCase(Fleet, case, player, character, shared))

			for _, problem: string in Fleet.clear() do
				table.insert(problems, problem)
			end
		end
	end)

	-- Everything it made goes, whatever the cases did
	for _, problem: string in Fleet.clear() do
		table.insert(problems, problem)
	end

	local stopped: boolean, stopFailure: any = pcall(Network.shoot.fire, player, STOP)
	folder:Destroy()
	Shots.clear()
	Hits.clear()

	local respawned: boolean, respawnFailure: any = pcall(Game.respawn, player)

	if not ran then
		table.insert(problems, `it threw: {failure}`)
	end

	if not stopped then
		table.insert(problems, `the shooter was never told to stop: {stopFailure}`)
	end

	if not respawned then
		table.insert(problems, `the shooter was not respawned: {respawnFailure}`)
	end

	for _, target: Tread.Target in server:getAll() do
		local owner: any = (target :: any).player
		if owner ~= nil and typeof(owner) ~= "Instance" then
			table.insert(problems, `{owner.Name}'s character is still on the server`)
		end
	end

	for _, problem: string in problems do
		table.insert(lines, problem)
	end

	local report: string = table.concat(lines, SEPARATOR)
	if #problems > 0 then
		return false, report
	end

	return true, report
end

return Hits
