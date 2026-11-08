--[[
    A player's relay view lasts across their characters: after one is
    destroyed and the next built, a reveal pending for the new character's
    view rides one block and is cleared by the client's next acknowledgment,
    which never resets, so it stops repeating
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local MASK_BITS: number = 16 -- The sequences before the newest an acknowledgment's mask names
local MASK: number = 2 ^ MASK_BITS - 1
local BEFORE: number = 30 -- Relay ticks before the respawn, so the client's newest is past what a fresh view would number
local AFTER: number = 6 -- Relay ticks watched after the reveal first rides a block
local DELAY: number = 150 -- Milliseconds of interpolation delay each Move reports

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Block: any = rig:require(rig.tread.Codec.Block)
	local Fields: any = rig:require(rig.tread.Codec.Fields)
	local Move: any = rig:require(rig.tread.Codec.Move)
	local Sequence: any = rig:require(rig.tread.Codec.Sequence)

	local client: any = rig:require(rig.tread.Network.Client)
	local key: any = rig.mock.players[1]
	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local move: any = Move.new()

	-- The client's acknowledgment as Interpolate keeps it, which only ever moves on
	local acknowledged: number = 0
	local mask: number = 0
	local started: boolean = false
	local carried: { [number]: number } = {} -- How many blocks carried a reveal of each slot

	client.Relay.on(function (data: buffer)
		local block: any = Block.new()
		Block.read(data, block)

		local sequence: number = block.sequence
		if not started then
			started = true
			acknowledged = sequence
		else
			local ahead: number = Sequence.difference(sequence, acknowledged)
			if ahead > 0 then
				mask = ahead > MASK_BITS and 0
					or bit32.band(bit32.bor(bit32.lshift(mask, ahead), 2 ^ (ahead - 1)), MASK)
				acknowledged = sequence
			elseif ahead < 0 and -ahead <= MASK_BITS then
				mask = bit32.bor(mask, 2 ^ (-ahead - 1))
			end
		end

		for index: number = 1, block.revealCount do
			local slot: number = block.reveals[index].slot
			carried[slot] = (carried[slot] or 0) + 1
		end
	end)

	-- One relay tick, its blocks read and the client's acknowledgment sent back before the next
	local function round()
		rig:tick(1)
		rig:deliver()

		Move.encode(move, {}, 0, acknowledged, mask, DELAY, layout, limits)
		client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
		client.flush()
		rig:deliver()
	end

	client.flush()
	rig:deliver()

	-- An NPC walking beside the player is owed a record every relay tick, so every tick sends a block
	local walker: any = server:createNpc(rig:at(-20, 15))
	walker:command({
		forward = 1,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		yaw = -math.pi / 2,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	})

	local first: any = server:create(key, rig:at(0, 0))
	for _ = 1, BEFORE do
		round()
	end

	if not (acknowledged > MASK_BITS + AFTER) then
		return false, `The client's newest block before the respawn is {acknowledged}, too few to tell a fresh view`
	end

	first:destroy()
	server:create(key, rig:at(2, 0))
	local arrival: any = server:create(rig.mock:addBot("Arrival"), rig:at(6, 0))

	for _ = 1, AFTER do
		round()
	end

	local times: number? = carried[arrival._slot]
	if times ~= 1 then
		return false, `The new character's view carried the arrival's reveal in {times} blocks, not one`
	end

	return true, nil
end
