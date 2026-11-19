--[[
    A Heartbeat of two ticks relays on the second alone: an acknowledgment
    filed on the first clears its reveals, sequences go on by one, the pair
    keeps its verdict, one tap frame has both looks, stats counts the skip
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local SETTLE: number = 6 -- One-tick Heartbeats before the catch-up, so the bodies stand and the pair is tested
local CATCH_UP: number = 2 -- The ticks the catch-up Heartbeat runs, the example's catch-up
local MASK_BITS: number = 16 -- The sequences before the newest an acknowledgment covers
local WRAP: number = 2 ^ 16
local DELAY: number = 150 -- Milliseconds of interpolation delay the Move reports
local SLOT_FIELD: number = 2 -- The example's held hotbar slot, which the Move's command carries

-- One block as the client read it
type Read = { sequence: number, tick: number, reveals: number }

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local tread: any = rig.tread

	local AntiEsp: any = rig:require(tread.Server.AntiEsp)
	local Block: any = rig:require(tread.Codec.Block)
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)
	local Tap: any = rig:require(tread.Codec.Tap)
	local Tick: any = rig:require(tread.Server.Tick)

	-- The client joins the mock as its player, and keeps each block it reads
	local client: any = rig:require(tread.Network.Client)
	local player: any = rig.mock.players[1]
	local blocks: { Read } = {}

	client.Relay.on(function (data: buffer)
		local block: any = Block.new()
		Block.read(data, block)
		table.insert(blocks, { sequence = block.sequence, tick = block.tick, reveals = block.revealCount })
	end)

	client.flush()
	rig:deliver()

	server:create(player, rig:at(0, 0))
	local target: any = server:create(rig.mock:addBot("Seen"), rig:at(6, 0))

	-- A walking NPC, so every relay run has a record for the client
	local npc: any = server:createNpc(rig:at(-6, 20))
	local walk: any = Command.new()
	walk.forward = 1
	npc:command(walk)

	local frames: { any } = {}
	server:observe(player, function (_: number, data: buffer)
		table.insert(frames, Tap.read(data))
	end)

	rig:tick(SETTLE)
	rig:deliver()

	local last: Read? = blocks[#blocks]
	local lastFrame: any = frames[#frames]
	if not last or last.reveals == 0 then
		return false, "The client's blocks before any acknowledgment carried no reveal riding on"
	elseif not lastFrame or not lastFrame.owner or #lastFrame.owner.looks ~= 1 then
		return false, "A one-tick Heartbeat's tap frame carried no OwnerState with its one look"
	elseif AntiEsp.reason(player, target._slot) ~= "Clear" then
		return false, `Before the catch-up anti-ESP's pair gave {AntiEsp.reason(player, target._slot)}, not Clear`
	end

	-- The client acknowledges every block it read, in a Move with the next tick's command
	local received: { [number]: boolean } = {}
	for _, read: Read in blocks do
		received[read.sequence] = true
	end

	local mask: number = 0
	for back: number = 1, MASK_BITS do
		if received[(last.sequence - back) % WRAP] then
			mask += 2 ^ (back - 1)
		end
	end

	local ran: number = Tick.counts()
	local command: any = Command.new()
	command.number = ran + 1
	command.fields = { slot = SLOT_FIELD, shots = {} }

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local move: any = Move.new()
	Move.encode(move, { command }, 1, last.sequence, mask, DELAY, layout, limits)
	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()
	rig:deliver()

	server:stats()
	local read: number, framed: number = #blocks, #frames
	rig.frames:run(CATCH_UP / rig.rate)
	rig:deliver()

	local stats: any = server:stats()
	if stats.ticks ~= CATCH_UP or stats.relaySkipped ~= 1 then
		return false, `The catch-up Heartbeat gave {stats.ticks} ticks and {stats.relaySkipped} relay ticks skipped`
	end

	-- One block, the run's after the skip, its sequence the next, and the reveals it rode cleared
	local relayed: number = (ran + CATCH_UP) % WRAP
	local after: Read? = blocks[read + 1]
	if #blocks ~= read + 1 or not after or after.tick ~= relayed then
		return false, `The catch-up Heartbeat sent the client {#blocks - read} blocks, not one at relay tick {relayed}`
	elseif after.sequence ~= (last.sequence + 1) % WRAP then
		return false, `The block after the skip had sequence {after.sequence}, not {last.sequence + 1}`
	elseif after.reveals ~= 0 then
		return false, "The acknowledgment filed on the skipped tick left the reveals riding on"
	end

	-- One tap frame, at the relay tick run, with the looks of both ticks beside its OwnerState
	local frame: any = frames[framed + 1]
	if #frames ~= framed + 1 or not frame or frame.tick ~= relayed then
		return false, `The catch-up Heartbeat gave the sink {#frames - framed} frames, not one at relay tick {relayed}`
	elseif not frame.owner or #frame.owner.looks ~= CATCH_UP then
		return false, `The frame after the skip carried {frame.owner and #frame.owner.looks} looks, not {CATCH_UP}`
	elseif AntiEsp.reason(player, target._slot) ~= "Clear" then
		return false, `After the skipped run anti-ESP's pair gave {AntiEsp.reason(player, target._slot)}, not Clear`
	end

	return true, nil
end
