--[[
    The dev server's ghosts: each tick, to each viewer who asks, the feet,
    velocity and clock stamp the server holds for the asked characters that
    viewer is already sent, so its client can draw where they really are
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local Relay = require(Packages.Tread.Server.Relay)
local Tick = require(Packages.Tread.Server.Tick)

local Shared = require(ReplicatedStorage.Shared.Dev.Config)

local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Ghost).rate
local LABEL_BYTES: number = require(ServerScriptService.Server.Config.Ghost).labelBytes

local WRAP: number = 2 ^ 16 -- The values the ghosts event's u16 tick wraps through, as the relay's wire tick does

type Key = Player | Volt.Bot

-- What the start is handed: the running server, the label each send carries, and the live run going, nil while none is
type Setup = {
	server: Tread.Server,
	describe: () -> string,
	liveRun: () -> string?,
}

local Running: Setup? = nil -- From the start

local Asks: { [Player]: { number } } = {} -- Each asking viewer's slots, never an empty list
local Frames: RBXScriptConnection? = nil -- The PreSimulation listener, connected while anyone asks
local Seen: number = 0 -- The ticks run as of the last frame
local Clock: number? = nil -- The server's clock at the last frame's PreSimulation, nil when it stamps nothing

local Ghost = {}

-- The relay tick a tick runs in, numbered as the relay's wire numbers it
local function relayTick(ran: number): number
	return math.floor(ran * Shared.rates.relay / Shared.rates.simulation) % WRAP
end

--[[
    The ghosts of the asked slots an asker is sent: each slot holding a
    character other than the asker's own that the relay sends the asker,
    at its feet and velocity as the last tick left them. An NPC, a sleeper
    and a slot nothing holds get none
--]]

local function answer(characters: { [number]: Tread.Character }, asker: Player, slots: { number }): { Network.Ghost }
	local ghosts: { Network.Ghost } = {}

	for _, slot: number in slots do
		local character: Tread.Character? = characters[slot]
		if character and character.player ~= asker and Relay.isSent(asker, slot) then
			local state: Tread.State = character:getState()

			table.insert(ghosts, {
				slot = slot,
				x = state.root.X,
				y = state.root.Y,
				z = state.root.Z,
				vx = state.velocity.X,
				vy = state.velocity.Y,
				vz = state.velocity.Z,
			})
		end
	end

	return ghosts
end

-- Sends every asker its ghosts of the newest tick, stamped with the clock read before the Heartbeat that ran it
local function send(setup: Setup, ran: number, stamp: number)
	local label: string = string.sub(setup.describe(), 1, LABEL_BYTES)
	local tick: number = relayTick(ran)

	-- Every player's and bot's character by slot, from Tread's own fields: a character's player, which an NPC and a
	-- sleeper lack, and its slot
	local characters: { [number]: Tread.Character } = {}
	for _, target: Tread.Target in setup.server:getAll() do
		local fields: any = target
		if fields.player ~= nil then
			characters[fields._slot] = fields
		end
	end

	for asker: Player, slots: { number } in Asks do
		Network.ghosts.fire(asker, tick, stamp, label, answer(characters, asker, slots))
	end
end

--[[
    Each PreSimulation while anyone asks: when a tick ran in the frame just
    past, the askers are sent its ghosts, stamped with the clock read at
    that frame's PreSimulation. A live run measures the server, so nothing
    goes while one runs, nor on the first frame after it
--]]

local function frame(now: number)
	local ran: number = Tick.counts()
	local stamp: number? = Clock
	local ticked: boolean = ran ~= Seen
	Seen = ran
	Clock = now

	local setup: Setup? = Running
	if not setup then
		return
	elseif setup.liveRun() ~= nil then
		Clock = nil
		return
	end

	if ticked and stamp then
		send(setup, ran, stamp)
	end
end

-- A viewer stops asking, by an empty ask or by leaving, and the frame listener goes with the last one
local function forget(key: Key)
	Asks[key :: Player] = nil

	local frames: RBXScriptConnection? = Frames
	if frames and next(Asks) == nil then
		frames:Disconnect()
		Frames = nil
		Clock = nil
	end
end

-- A viewer's ask for the ghosts of the slots it names, the first asker connecting the frame listener
local function ask(key: Key, slots: { number })
	-- A Volt bot fires none of the dev scope's events, so whoever asked is a player
	local player: Player = key :: Player
	if #slots == 0 then
		return forget(player)
	end

	Asks[player] = slots

	-- Its first frame stamps nothing, since no clock was read before the Heartbeat of the tick it finds
	if not Frames then
		Frames = RunService.PreSimulation:Connect(function ()
			frame(Workspace:GetServerTimeNow())
		end)
	end
end

--[[
    Binds the viewers' asks at the dev game's own rate and forgets each
    viewer who leaves. Each send carries the label describe gives, and
    nothing goes while liveRun names a run. It runs once a server, and its
    listeners live as long as the server
--]]

function Ghost.start(server: Tread.Server, describe: () -> string, liveRun: () -> string?)
	if Running then
		error("Ghost.start runs once a server, and it has already run", 2)
	end

	Running = { server = server, describe = describe, liveRun = liveRun }

	Network.rate("ghostAsk", RATE.perSecond, RATE.burst)
	Network.ghostAsk.on(ask)
	Network.onLeave(forget)
end

return Ghost
