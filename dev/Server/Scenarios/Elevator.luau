--[[
    Rides the test elevator with a Volt bot built on its resting deck: the
    deck called, and on each tick of one whole ride the bot checked riding
    it a skin over its top where the path puts it, then back at rest
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Constants = require(Packages.Tread.Constants)
local Math = require(Packages.Tread.Step.Math)

local Elevator = require(ReplicatedStorage.Shared.Dev.Elevator)
local Game = require(ServerScriptService.Server.Game)

local LIFT: number = 0.5 -- Studs over the deck's top the bot's character is built at
local BOARD_SECONDS: number = 10 -- The longest the wait for the bot to board runs before it fails
local AFTER: number = 1 -- Seconds of rest past the ride the bot is still checked through
local SLACK: number = 5 -- Seconds the ride's wait runs past its ticks before it fails, for a server running late
local SKIN: number = Constants.SKIN -- What a grounded body keeps between its feet and its ground
local QUANTUM: number = Constants.POSITION_QUANTUM
local PROBE_STAGE: string = "elevatorProbe"
local BOT_NAME: string = "ElevatorBot"

local PLATFORM: Tread.Platform = Elevator.platform
local DECK: { center: Vector3, size: Vector3 } = PLATFORM.boxes[1]
local RIDE: number = DECK.center.Y + DECK.size.Y / 2 + SKIN -- The feet over the platform's origin while riding

-- One ride the probe stage checks on each tick from the call's through the last
type Ride = {
	character: Tread.Character,
	calledAt: number,
	last: number,
	checked: number, -- Ticks checked so far
	highest: number, -- The highest the feet stood
	failure: string?, -- What the first tick that failed showed
}

-- What one run made, all of which it removes whatever its checks did
type Made = {
	bot: Volt.Bot?,
	character: Tread.Character?,
}

-- The ride the probe checks, and the newest tick it has seen; added once a server, since stages stay
local Riding: Ride? = nil
local Present: number = 0
local Probing: boolean = false

-- Where the feet of a body riding the deck stand on a tick of a ride, on the quantum the step keeps them on
local function feetOn(tick: number, calledAt: number): number
	return Math.quantize(Math.quantize(PLATFORM.path(tick, calledAt).Y) + RIDE)
end

--[[
    The probe stage, right after every character's step: keeps the tick,
    and while a ride is checked, that its bot still rides the elevator
    with its feet where the path puts them, the first failure kept
--]]

local function probe(tick: number)
	Present = tick

	local ride: Ride? = Riding
	if not ride or tick < ride.calledAt or tick > ride.last or ride.failure ~= nil then
		return
	end

	local state: Tread.State = ride.character:getState()
	local elapsed: number = tick - ride.calledAt
	local expected: number = feetOn(tick, ride.calledAt)
	ride.checked += 1
	ride.highest = math.max(ride.highest, state.root.Y)

	if state.platform ~= PLATFORM.id then
		ride.failure = `{elapsed} ticks into the ride the bot rode platform {state.platform}, not the elevator`
	elseif math.abs(state.root.Y - expected) > QUANTUM then
		ride.failure = `{elapsed} ticks into the ride the bot's feet stood at {state.root.Y}, not {expected}`
	end
end

-- Waits a frame at a time until done says so or the seconds pass, and gives whether it got there
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
    The bot built on the resting deck and boarded, the call, one whole ride
    and the rest after it checked by the probe, then the bot back at rest.
    Gives the first failure, or nil and the line the report carries
--]]

local function drive(handle: Tread.Server, made: Made, rate: number): (string?, string)
	local bot: Volt.Bot = Volt.addBot(BOT_NAME)
	made.bot = bot

	local rest: Vector3 = PLATFORM.path(Present, nil)
	local character: Tread.Character = handle:create(bot, CFrame.new(rest.X, rest.Y + RIDE + LIFT, rest.Z))
	made.character = character

	local boarded: boolean = waitFor(BOARD_SECONDS, function (): boolean
		return character:getState().platform == PLATFORM.id
	end)

	if not boarded then
		return `the bot never boarded the resting deck within {BOARD_SECONDS} s`, ""
	end

	-- A call lands on the tick after the newest the server ran, which the probe saw last
	local ticks: number = math.ceil((Elevator.cycle + AFTER) * rate)
	local calledAt: number = Present + 1
	local ride: Ride = {
		character = character,
		calledAt = calledAt,
		last = calledAt + ticks,
		checked = 0,
		highest = -math.huge,
		failure = nil,
	}

	Riding = ride
	handle:callPlatform(PLATFORM.id)

	local rode: boolean = waitFor(Elevator.cycle + AFTER + SLACK, function (): boolean
		return Present >= ride.last or ride.failure ~= nil
	end)

	Riding = nil

	local failure: string? = ride.failure
	if failure then
		return failure, ""
	elseif not rode then
		return `the server ran {ride.checked} of the ride's {ticks + 1} ticks within its wait`, ""
	end

	local root: Vector3 = character:getState().root
	local after: number = feetOn(ride.last, calledAt)
	if math.abs(root.Y - after) > QUANTUM then
		return `after the ride the bot's feet stood at {root.Y}, not back at rest at {after}`, ""
	end

	return nil, `rode {ride.checked} ticks a skin over the deck, its feet up to {ride.highest}, and back at {root.Y}`
end

return function (): (boolean, string | nil)
	local handle: Tread.Server, shared: Tread.Shared = Game.get()

	if not Probing then
		handle:addStage(PROBE_STAGE, "simulate", probe)
		Probing = true
	end

	local made: Made = { bot = nil, character = nil }
	local ran: boolean, failure: any, line: any = pcall(drive, handle, made, shared.rates.simulation)

	-- Everything it made goes, whatever the checks did
	Riding = nil

	local character: Tread.Character? = made.character
	if character then
		character:destroy()
	end

	local bot: Volt.Bot? = made.bot
	if bot then
		Volt.removeBot(bot)
	end

	if not ran then
		return false, `the ride's checks threw: {failure}`
	elseif failure ~= nil then
		return false, failure
	end

	print(`Elevator: {line}`)

	return true, line
end
