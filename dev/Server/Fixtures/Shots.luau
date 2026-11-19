--[[
    The dev game's stand-in for Frontier Zero's Ballistics: each shot a
    command carries flies from the server's cleared eye and is tested on its
    shooter's timeline against the hit shapes sampleAt places, nearest first
--]]

--!strict
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Ballistics = require(ReplicatedStorage.Shared.Dev.Ballistics)
local Constants = require(Packages.Tread.Constants)
local Public = require(Packages.Tread.Step.Public)

local WEAPONS: { Weapon } = require(ReplicatedStorage.Shared.Dev.BallisticsConfig).weapons
local FRACTION_STEPS: number = require(ReplicatedStorage.Shared.Dev.BallisticsConfig).fractionSteps
local STAGE: string = require(ServerScriptService.Server.Config.Fixtures).stage
local RADIANS_PER_STEP: number = 2 * math.pi / Constants.ANGLE_STEPS -- A shot's packed yaw and pitch, as a command's
local NO_OFFSET: number = 0 -- A shot leaves along its own look, with no head offset to turn or hold to a cone

-- A shot as the dev table declares it
type Shot = {
	sequence: number,
	class: number,
	renderTick: number, -- The low 16 bits of the render tick the shooter saw
	fraction: number,
	yaw: number,
	pitch: number,
}

type Weapon = Ballistics.Weapon

-- What a segment met first: the target, its zone, and where along the segment
export type Strike = {
	target: Tread.Target,
	zone: string,
	at: Vector3,
	distance: number, -- Studs from the segment's start
}

-- One shot from its fire to what it struck or why it missed
export type Result = {
	shooter: Tread.Character,
	sequence: number,
	command: number, -- The number of the command it rode in, a u16
	claimed: number, -- The render time it carried, relay ticks with the fraction, the whole ticks' low 16 bits
	renderTime: number, -- The render time rewindFor gave its claim, relay ticks unwrapped
	inside: boolean, -- Whether its claim was inside the band
	fired: number, -- The simulation tick it was fired and first flew on, unwrapped
	offset: number, -- Relay ticks its render time lay behind its fire, the same for its whole flight
	origin: Vector3, -- The server's cleared eye at its command, where it left from
	direction: Vector3,
	strike: Strike?, -- nil for a miss
	tick: number, -- The tick it struck or ended on
	reason: string?, -- Why it missed: range, unarmed, cap or history; nil for a strike
}

-- A bullet in flight and its result so far
type Bullet = {
	result: Result,
	weapon: Weapon?, -- nil for a shot from a hotbar slot with no fixture weapon
	position: Vector3, -- Where its next step starts
	flown: number, -- Studs it has flown
	stepped: boolean, -- Whether its first step has run, which sets its fire tick and offset
}

local Running: Tread.Server? = nil -- The server the fixtures were started on
local SimulationRate: number = 0 -- Ticks a second, from the shared table at start
local RelayRate: number = 0
local CapTicks: number = 0 -- Relay ticks the rewind's ceiling reaches back
local HistoryTicks: number = 0 -- Relay ticks the history reaches back

local Bullets: { Bullet } = {} -- Every bullet in flight
local Results: { Result } = {} -- Every shot resolved since the start or the last clear, in the order they resolved

local Shots = {}

-- The running server, erroring from the caller of the member named before the start
local function running(member: string): Tread.Server
	local server: Tread.Server? = Running
	if not server then
		error(`{member} ran before Shots.start`, 3)
	end

	return server
end

--[[
    The nearest zone a segment meets among the targets, each read from the
    history at the render time, a rider placed on its platform as it stands
    on the tick, with the shooter's own shapes left out. A target's body
    capsule is the broad check, and only its zones can be struck
--]]

local function strike(
	server: Tread.Server,
	targets: { Tread.Target },
	shooter: Tread.Target?,
	from: Vector3,
	to: Vector3,
	renderTime: number,
	tick: number
): Strike?
	local move: Vector3 = to - from
	local length: number = move.Magnitude
	if length == 0 then
		return nil
	end

	local unit: Vector3 = move / length
	local nearest: Strike? = nil

	for _, target: Tread.Target in targets do
		if target == shooter then
			continue
		end

		local sample: Tread.Sample? = server:sampleAt(target, renderTime, tick)
		if not sample then
			continue
		end

		local zone: string?, distance: number = Ballistics.zone(from, unit, length, sample.body, sample.zones)
		if zone and (not nearest or distance < nearest.distance) then
			nearest = { target = target, zone = zone, at = from + unit * distance, distance = distance }
		end
	end

	return nearest
end

-- Why no shot may be tested at a render time this far behind the present, history past its length and cap past its ceiling
local function beyond(renderTime: number, now: number): string?
	local behind: number = now - renderTime
	if behind > HistoryTicks then
		return "history"
	elseif behind > CapTicks then
		return "cap"
	end

	return nil
end

--[[
    Moves a bullet one tick along its line, tested at the present tick less
    the offset it kept from its fire, and gives whether it resolved: on a
    strike, at the end of its range, from a slot with no weapon, or at a time
    past what a shot may reach. Its first step is on the tick it was fired
--]]

local function advance(bullet: Bullet, server: Tread.Server, targets: { Tread.Target }, tick: number): boolean
	local result: Result = bullet.result
	local now: number = tick * RelayRate / SimulationRate

	if not bullet.stepped then
		bullet.stepped = true
		result.fired = tick
		result.offset = now - result.renderTime
	end

	result.tick = tick

	local weapon: Weapon? = bullet.weapon
	if not weapon then
		result.reason = "unarmed"

		return true
	end

	local renderTime: number = now - result.offset
	local reason: string? = beyond(renderTime, now)
	if reason then
		result.reason = reason

		return true
	end

	local travel: number = math.min(weapon.speed / SimulationRate, weapon.range - bullet.flown)
	local from: Vector3 = bullet.position
	local to: Vector3 = from + result.direction * travel
	bullet.position = to
	bullet.flown += travel

	local struck: Strike? = strike(server, targets, result.shooter, from, to, renderTime, tick)
	if struck then
		result.strike = struck

		return true
	elseif bullet.flown >= weapon.range then
		result.reason = "range"

		return true
	end

	return false
end

-- Runs where a bullet's step raised its error, so its warning keeps the stack
local function warnBullet(message: any)
	warn(`A fixture bullet's step threw, and it was dropped: {debug.traceback(tostring(message), 2)}`)
end

--[[
    The fixture stage: every bullet in flight one tick on, each under its
    own xpcall so one that throws is dropped and the rest still fly, and
    each that resolved moved to the results
--]]

local function step(tick: number)
	local server: Tread.Server = running("The fixture stage")
	local targets: { Tread.Target } = server:getAll()

	for index: number = #Bullets, 1, -1 do
		local bullet: Bullet = Bullets[index]
		local ran: boolean, resolved: any = xpcall(advance, warnBullet, bullet, server, targets, tick)

		if not ran or resolved then
			table.remove(Bullets, index)
		end

		if ran and resolved then
			table.insert(Results, bullet.result)
		end
	end
end

--[[
    Starts the fixture shots on the running server, once a server: its
    rates, the rewind's ceiling and the history's length in relay ticks,
    and the stage every bullet flies in, which lives as long as the server
--]]

function Shots.start(server: Tread.Server, shared: Tread.Shared, settings: Tread.ServerSettings)
	if Running then
		error("Shots.start runs once a server, and it has already run", 2)
	end

	Running = server
	SimulationRate = shared.rates.simulation
	RelayRate = shared.rates.relay
	CapTicks = settings.rewind.ceiling * RelayRate
	HistoryTicks = settings.history.seconds * RelayRate

	-- After the history, so every sample a bullet reads was written by this tick at the latest
	server:addStage(STAGE, "history", step)
end

--[[
    The dev game's pre-command hook: each shot in a command Tread is about
    to step leaves the server's cleared eye along its own look, at the
    render time rewindFor gives its claim, and flies from this tick's
    fixture stage on. A stand-in's shots are at rest, so it fires none

    @ command | the command as Tread hands the hook, its number a u16
--]]

function Shots.queue(character: Tread.Character, command: Tread.Command)
	local shots: { Shot }? = command.fields.shots
	if not shots or #shots == 0 then
		return
	end

	local server: Tread.Server = running("Shots.queue")
	local origin: Vector3 = character:getState().eye
	local weapon: Weapon? = WEAPONS[command.fields.slot]

	for _, shot: Shot in shots do
		local claimed: number = shot.renderTick + shot.fraction / FRACTION_STEPS
		local renderTime: number, inside: boolean = server:rewindFor(character.player, command.number, claimed)
		local yaw: number = shot.yaw * RADIANS_PER_STEP
		local pitch: number = shot.pitch * RADIANS_PER_STEP
		local look: vector = Public.look(yaw, pitch, NO_OFFSET, NO_OFFSET, NO_OFFSET)

		local result: Result = {
			shooter = character,
			sequence = shot.sequence,
			command = command.number,
			claimed = claimed,
			renderTime = renderTime,
			inside = inside,
			fired = 0,
			offset = 0,
			origin = origin,
			direction = Vector3.new(look.x, look.y, look.z),
			strike = nil,
			tick = 0,
			reason = nil,
		}

		table.insert(Bullets, { result = result, weapon = weapon, position = origin, flown = 0, stepped = false })
	end
end

--[[
    The fixture hit test on its own: the nearest zone a segment meets, the
    targets read at the render time as a bullet reads them, or nil with
    history or cap when the time lies further behind the tick than a shot
    may reach. nil with no reason is a plain miss

    @ renderTime | relay ticks with their fraction, unwrapped
    @ tick | the present simulation tick, unwrapped
--]]

function Shots.test(
	shooter: Tread.Target?,
	from: Vector3,
	to: Vector3,
	renderTime: number,
	tick: number
): (Strike?, string?)
	local server: Tread.Server = running("Shots.test")

	local reason: string? = beyond(renderTime, tick * RelayRate / SimulationRate)
	if reason then
		return nil, reason
	end

	return strike(server, server:getAll(), shooter, from, to, renderTime, tick), nil
end

-- Every shot resolved since the start or the last clear, in the order they resolved, the module's own list
function Shots.results(): { Result }
	return Results
end

-- The resolved shots that struck a target, in a list of their own
function Shots.hits(target: Tread.Target): { Result }
	local found: { Result } = {}

	for _, result: Result in Results do
		local struck: Strike? = result.strike
		if struck and struck.target == target then
			table.insert(found, result)
		end
	end

	return found
end

-- Forgets every resolved shot and every bullet in flight, for a run that leaves the dev game as it found it
function Shots.clear()
	table.clear(Results)
	table.clear(Bullets)
end

return Shots
