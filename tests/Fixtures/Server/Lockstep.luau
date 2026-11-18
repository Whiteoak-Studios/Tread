--[[
    Two servers built alike for the relay stage's cases, one relaying in
    process and one on stand-in workers: a client, three bots, a moderator,
    a walking NPC and a wall each, with every send, frame and stage call kept
--]]

--!strict
local Lockstep = {}

local Rig = require("./Rig")
local StandIn = require("../Relay/StandIn")

local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local SLICE: number = 1 -- Seconds a slice may take, so every pair due is tested in the slice it is due in
local FAIL_OPEN: number = 1000 -- Seconds a hidden pair may go untested, so none fails open while a case runs
local WALL_SIZE: vector = vector.create(1, 40, 40) -- Tall and wide enough to block every ray across it
local WALL_X: number = -3 -- Between the client and the bot named Hidden, and between Hidden and Seen
local NAMES: { string } = { "Client", "Seen", "Hidden", "Moderator" }

-- Where each character is built, its x and z over the fixture floor
local PLACES: { [string]: { number } } = {
	Client = { 0, 0 },
	Seen = { 6, 0 },
	Hidden = { -6, 0 },
	Moderator = { 30, 0 },
}

local NPC_PLACE: { number } = { 12, 10 }

-- The relay table a side's server runs on, with no workers in process
export type Relay = {
	workers: number,
	timeout: number,
}

export type Side = {
	rig: Rig.Rig,
	server: any,
	Tick: any,
	Characters: any,
	Tap: any,
	pool: any, -- The stand-in pool the relay made, nil in process
	keys: { [string]: any }, -- Each character's player or bot, by its name
	characters: { [string]: any },
	owners: { string }, -- Each OwnerState the client was sent, as its bytes
	blocks: { string }, -- Each relay block the client was sent
	frames: { [string]: { string } }, -- Each viewer's tap frames, by its name
	withheld: { string }, -- The withheld tap frames of the client's character, which the moderator watches
	order: { string }, -- What the case marks, each marker stage's run and each of the client's frames, as they came
}

--[[
    A side on the example's tables with every slice given time for every
    pair due and no fail-open, relaying in process or, given a relay table,
    on that many stand-in workers with its timeout, every character built,
    the moderator watching the client and every viewer's frames observed
--]]

function Lockstep.side(relay: Relay?): Side
	local made: { pool: any } = { pool = nil }
	local overrides: { [string]: any }? = nil
	if relay then
		overrides = {
			[POOL] = {
				new = function (count: number, name: string, remote: any, settings: any): any
					made.pool = StandIn.new(count, name, remote, settings)

					return made.pool
				end,
			},
		}
	end

	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.antiEsp.slice = SLICE
		settings.antiEsp.failOpen = FAIL_OPEN

		if relay then
			settings.relay = { changes = true, workers = relay.workers, timeout = relay.timeout }
		end
	end, overrides)

	local server: any = rig:start()
	local tread: any = rig.tread
	local client: any = rig:require(tread.Network.Client)

	local side: Side = {
		rig = rig,
		server = server,
		Tick = rig:require(tread.Server.Tick),
		Characters = rig:require(tread.Server.Characters),
		Tap = rig:require(tread.Codec.Tap),
		pool = made.pool,
		keys = { Client = rig.mock.players[1] },
		characters = {},
		owners = {},
		blocks = {},
		frames = {},
		withheld = {},
		order = {},
	}

	if relay and side.pool == nil then
		error("The relay made no workers in the stand-in pool")
	end

	client.Owner.on(function (data: buffer)
		table.insert(side.owners, buffer.tostring(data))
	end)

	client.Relay.on(function (data: buffer)
		table.insert(side.blocks, buffer.tostring(data))
	end)

	client.flush()
	rig:deliver()

	server:addStage("marker", "decode", function (tick: number)
		table.insert(side.order, `decode {tick}`)
	end)

	server:addStage("late", "relay", function (tick: number)
		table.insert(side.order, `late {tick}`)
	end)

	rig:wall(vector.create(WALL_X, rig.floor + WALL_SIZE.y / 4, 0), WALL_SIZE)

	for _, name: string in NAMES do
		local key: any = side.keys[name] or rig.mock:addBot(name)
		local place: { number } = PLACES[name]
		side.keys[name] = key
		side.characters[name] = server:create(key, rig:at(place[1], place[2]))
		side.frames[name] = {}

		server:observe(key, function (tick: number, data: buffer)
			table.insert(side.frames[name], buffer.tostring(data))
			if name == "Client" then
				table.insert(side.order, `frame {tick}`)
			end
		end)
	end

	local Command: any = rig:require(tread.Codec.Command)
	local walk: any = Command.new()
	walk.forward = 1
	server:createNpc(rig:at(NPC_PLACE[1], NPC_PLACE[2])):command(walk)

	server:spectate(side.keys.Moderator, side.characters.Client)
	server:observeWithheld(side.keys.Client, function (_: number, data: buffer)
		table.insert(side.withheld, buffer.tostring(data))
	end)

	return side
end

-- One Heartbeat of a share of a tick's time, marked in the side's order, with the mock stepped after
function Lockstep.beat(side: Side, share: number)
	table.insert(side.order, "beat")
	side.rig.frames:run(share / side.rig.rate)
	side.rig:deliver()
end

-- Why the first count entries of two lists differ, or nil when they match, each list holding at least count
function Lockstep.differ(what: string, serial: { string }, workers: { string }, count: number): string?
	if #serial < count or #workers < count then
		return `{what}: {#serial} serially and {#workers} on the workers, not {count} each`
	end

	for index: number = 1, count do
		if serial[index] ~= workers[index] then
			return `{what} {index} differs serially and on the workers`
		end
	end

	return nil
end

return Lockstep
