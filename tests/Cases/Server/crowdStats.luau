--[[
    Stats gives crowdRest as its change since the last read: none while the
    bots' reveals ride on, two a relay tick once a player sent three bots under
    a cap of one acknowledges them, and none once Relay.setCrowd lifts the cap
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local SETTLE: number = 6 -- One-tick Heartbeats before the acknowledgment, so the bodies stand and every pair is tested
local COUNTED: number = 5 -- Relay ticks between the reads, one a tick at the example's rates
local MASK_BITS: number = 16 -- The sequences before the newest an acknowledgment covers
local WRAP: number = 2 ^ 16
local DELAY: number = 150 -- Milliseconds of interpolation delay the Move reports
local SLOT_FIELD: number = 2 -- The example's held hotbar slot, which the Move's command carries
local CROWD: { size: number, rate: number, floor: number } = { size = 1, rate = 20, floor = 5 }
local BOTS: { number } = { -6, -12, -18 } -- Each bot's x beside the player at the origin, clear of the obstacles

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
	local reveals: number = 0

	client.Relay.on(function (data: buffer)
		local block: any = Block.new()
		Block.read(data, block)
		table.insert(sequences, block.sequence)
		reveals += block.revealCount
	end)

	client.flush()
	rig:deliver()

	server:create(player, rig:at(0, 0))
	for index: number, x: number in BOTS do
		server:create(rig.mock:addBot(`Bot{index}`), rig:at(x, 0))
	end

	rig:tick(SETTLE)
	rig:deliver()

	local last: number? = sequences[#sequences]
	if last == nil or reveals < #BOTS then
		return false, `Before any acknowledgment the client read {#sequences} blocks with {reveals} reveals`
	end

	-- While its reveals ride on, no bot is a candidate, so the cap holds no one out
	local riding: any = server:stats()
	if riding.crowdRest ~= 0 then
		return false, `With every reveal riding on, stats gave {riding.crowdRest} held outside the cap`
	end

	-- The client acknowledges every block it read, in a Move with the next tick's command
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

	-- Each relay run from the acknowledgment on, the player's turn holds two of its three bots outside the cap of one
	server:stats()
	rig:tick(COUNTED)
	local capped: any = server:stats()
	local held: number = COUNTED * (#BOTS - CROWD.size)
	if capped.crowdRest ~= held then
		return false, `Over {COUNTED} relay ticks under the cap, stats gave {capped.crowdRest} held out, not {held}`
	end

	Relay.setCrowd(nil)
	rig:tick(COUNTED)
	local lifted: any = server:stats()
	if lifted.crowdRest ~= 0 then
		return false, `With the cap lifted, stats gave {lifted.crowdRest} held outside it`
	end

	return true, nil
end
