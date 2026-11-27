--[[
    The crowd cap counts the players a viewer is sent, a teammate behind a
    wall among them, and never an NPC, a body or a sleeper it is sent too:
    under a cap of one, one of its two players is held out each relay tick
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local SETTLE: number = 6 -- One-tick Heartbeats before the acknowledgment, so the bodies stand and every pair is tested
local COUNTED: number = 5 -- Relay ticks between the reads, one a tick at the example's rates
local MASK_BITS: number = 16 -- The sequences before the newest an acknowledgment covers
local WRAP: number = 2 ^ 16
local DELAY: number = 150 -- Milliseconds of interpolation delay the Move reports
local SLOT_FIELD: number = 2 -- The example's held hotbar slot, which the Move's command carries
local HEAD: number = 12 -- An item index the example's head slot holds
local TEAM: number = 1
local CROWD: { size: number, rate: number, floor: number } = { size = 1, rate = 20, floor = 5 }

-- Where each body stands from the viewer at the origin, clear of the fixture's obstacles, and the wall that hides the
-- teammate from every ray its pair test casts
local TEAMMATE: { number } = { -12, 0 }
local ENEMY: { number } = { 6, 0 }
local NPC: { number } = { 0, 6 }
local BODY: { number } = { 0, -6 }
local SLEEPER: { number } = { -6, -6 }
local WALL: vector = vector.create(-6, 5, 0) -- Its center, its height over the floor's top
local WALL_SIZE: vector = vector.create(1, 12, 12)
local RETEST_TICKS: number = 2 -- Ticks for anti-ESP to test the pair off its team and the hide to go

-- Seconds anti-ESP's slice may take a Heartbeat, more than the runner gives a whole case, so every pair asked is tested
-- by the next tick however fast the machine runs
local SLICE: number = 60

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.tiers.crowd = CROWD
		settings.antiEsp.slice = SLICE
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Block: any = rig:require(tread.Codec.Block)
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)
	local Relay: any = rig:require(tread.Server.Relay)
	local Tick: any = rig:require(tread.Server.Tick)

	-- The client joins the mock as its player, and keeps the sequence of each block it reads
	local client: any = rig:require(tread.Network.Client)
	local player: any = rig.mock.players[1]
	local sequences: { number } = {}

	client.Relay.on(function (data: buffer)
		local block: any = Block.new()
		Block.read(data, block)
		table.insert(sequences, block.sequence)
	end)

	client.flush()
	rig:deliver()

	rig:wall(vector.create(WALL.x, rig.floor + WALL.y, WALL.z), WALL_SIZE)

	local viewer: any = server:create(player, rig:at(0, 0))
	local teammate: any = server:create(rig.mock:addBot("Teammate"), rig:at(TEAMMATE[1], TEAMMATE[2]))
	local enemy: any = server:create(rig.mock:addBot("Enemy"), rig:at(ENEMY[1], ENEMY[2]))
	local npc: any = server:createNpc(rig:at(NPC[1], NPC[2]))
	local dying: any = server:create(rig.mock:addBot("Dying"), rig:at(BODY[1], BODY[2]))
	local sleeper: any = server:createSleeper(rig:at(SLEEPER[1], SLEEPER[2]), { head = HEAD })
	viewer:setTeam(TEAM)
	teammate:setTeam(TEAM)

	rig:tick(1)
	local body: any = dying:die(nil)
	dying:destroy()

	rig:tick(SETTLE)
	rig:deliver()

	-- The viewer is sent every body, the teammate through the wall, each reveal riding a block its client read
	local sent: { [string]: any } = { teammate = teammate, enemy = enemy, npc = npc, body = body, sleeper = sleeper }
	for name: string, handle: any in sent do
		if not Relay.isSent(player, handle._slot) then
			return false, `The viewer was not sent the {name}`
		end
	end

	-- The client acknowledges every block it read, in a Move with the next tick's command
	local last: number? = sequences[#sequences]
	if last == nil then
		return false, "The client read no block"
	end

	local received: { [number]: boolean } = {}
	for _, sequence: number in sequences do
		received[sequence] = true
	end

	local mask: number = 0
	for back: number = 1, MASK_BITS do
		if received[(last - back) % WRAP] then
			mask += 2 ^ (back - 1)
		end
	end

	local command: any = Command.new()
	command.number = Tick.counts() + 1
	command.fields = { slot = SLOT_FIELD, shots = {} }

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local move: any = Move.new()
	Move.encode(move, { command }, 1, last, mask, DELAY, layout, limits)
	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()
	rig:deliver()

	-- Two players and three bodies that aren't, so a cap of one holds one player out a relay tick and nothing else
	server:stats()
	rig:tick(COUNTED)
	local read: any = server:stats()
	local held: number = COUNTED * (2 - CROWD.size)
	if read.crowdRest ~= held then
		return false, `Over {COUNTED} relay ticks, stats gave {read.crowdRest} held outside the cap, not {held}`
	end

	for name: string, handle: any in sent do
		if not Relay.isSent(player, handle._slot) then
			return false, `Under the cap the viewer stopped being sent the {name}`
		end
	end

	-- Off the viewer's team the player behind the wall is hidden, so it was sent, and counted, as a teammate
	teammate:setTeam(nil)
	rig:tick(RETEST_TICKS)
	if Relay.isSent(player, teammate._slot) then
		return false, "Off the viewer's team, the player behind the wall was still sent"
	end

	return true, nil
end
