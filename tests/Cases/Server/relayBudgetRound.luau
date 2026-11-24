--[[
    Under a relay budget of 0 the server hands anti-ESP's passed to the relay,
    so a player its runs leave keeps its visible enemies visible on its next
    turn, and no hide or reveal reaches it
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local SETTLE: number = 6 -- One-tick Heartbeats before the acknowledgment, so every pair is tested and revealed
local WINDOW: number = 12 -- Relay ticks after it, one a tick at the example's rates, three of them the player's left runs
local MASK_BITS: number = 16 -- The sequences before the newest an acknowledgment covers
local WRAP: number = 2 ^ 16
local DELAY: number = 150 -- Milliseconds of interpolation delay the Move reports
local SLOT_FIELD: number = 2 -- The example's held hotbar slot, which the Move's command carries
local BOTS: { number } = { -6, -12, -18 } -- Each bot's x beside the player at the origin, four turn viewers in all
local NPC_AT: { number } = { 2, 12 } -- An NPC walking inside npcs.near, so each of the player's turns sends a block

-- What the player read in one relay block
type Read = {
	tick: number,
	reveals: number,
	hides: number,
}

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.relay = { changes = true, budget = 0 }
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Block: any = rig:require(tread.Codec.Block)
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)
	local Relay: any = rig:require(tread.Server.Relay)
	local Tick: any = rig:require(tread.Server.Tick)

	-- The client joins the mock as its player, and keeps each block's sequence and what it read in it
	local client: any = rig:require(tread.Network.Client)
	local player: any = rig.mock.players[1]
	local sequences: { number } = {}
	local reads: { Read } = {}

	client.Relay.on(function (data: buffer)
		local block: any = Block.new()
		Block.read(data, block)
		table.insert(sequences, block.sequence)
		table.insert(reads, { tick = block.tick, reveals = block.revealCount, hides = block.hideCount })
	end)

	client.flush()
	rig:deliver()

	server:create(player, rig:at(0, 0))
	local bots: { any } = {}
	for index: number, x: number in BOTS do
		table.insert(bots, server:create(rig.mock:addBot(`Bot{index}`), rig:at(x, 0)))
	end

	server:createNpc(rig:at(NPC_AT[1], NPC_AT[2])):command({
		forward = 1,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = { slot = 0, shots = {} },
	})

	for _ = 1, SETTLE do
		rig:tick(1)
		rig:deliver()
	end

	local revealed: number = 0
	for _, read: Read in reads do
		revealed = math.max(revealed, read.reveals)
	end

	local last: number? = sequences[#sequences]
	if last == nil or revealed < #BOTS then
		return false, `Before any acknowledgment the player read {#sequences} blocks revealing at most {revealed}`
	end

	-- The client acknowledges every block it read, so no reveal rides on past it
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

	table.clear(reads)
	server:stats()

	local from: number = Tick.counts() + 1
	for _ = 1, WINDOW do
		rig:tick(1)
		rig:deliver()

		for index: number, bot: any in bots do
			if not Relay.isSent(player, bot._slot) then
				return false, `After relay tick {Tick.counts()} the player was no longer sent bot {index}`
			end
		end
	end

	local window: any = server:stats()

	-- The relay ticks the player read no block for are the runs that left it, each followed by a turn of its own
	local turned: { [number]: boolean } = {}
	for _, read: Read in reads do
		turned[read.tick] = true
		if read.hides ~= 0 or read.reveals ~= 0 then
			return false, `Relay tick {read.tick}'s block carried {read.hides} hides and {read.reveals} reveals`
		end
	end

	local followed: number = 0
	for tick: number = from, from + WINDOW - 2 do
		if not turned[tick % WRAP] and turned[(tick + 1) % WRAP] then
			followed += 1
		end
	end

	if followed == 0 then
		return false, `In {WINDOW} relay ticks no run left the player and the next gave it a turn`
	elseif window.relayLeft ~= WINDOW then
		return false, `Over {WINDOW} relay ticks the server counted {window.relayLeft} turns left, not {WINDOW}`
	end

	return true, nil
end
