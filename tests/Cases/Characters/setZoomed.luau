--[[
    character:setZoomed sends a falling player in the far band at the near
    band's rate while on and its own once off, refuses a non-boolean and an
    ended handle, and the player's next character starts with it off
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local MASK_BITS: number = 16 -- The sequences before the newest an acknowledgment's mask names
local MASK: number = 2 ^ MASK_BITS - 1
local DELAY: number = 150 -- Milliseconds of interpolation delay each Move reports
local SETTLE: number = 10 -- Relay ticks before each count, past the reveal and anti-ESP's first test
local TICKS: number = 20 -- A second at the example's 20 Hz relay
local FAR: number = 300 -- Studs ahead of the viewer, past the example's 220-stud edge and off the fixture floor

-- The records the client got of the target in each second: off, on, off again, and as a new character
local EXPECTED: { number } = { 15, 20, 15, 15 }

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

	-- The client's acknowledgment as Interpolate keeps it, and every record it read, whole or as a change, which are
	-- all the target's, since the client is sent no one else
	local acknowledged: number = 0
	local mask: number = 0
	local started: boolean = false
	local records: number = 0

	client.Relay.on(function (data: buffer)
		local block: any = Block.new()
		Block.read(data, block)
		records += block.recordCount + block.changeCount

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

	-- The records over a second, after the reveal and the stretch's start have settled
	local function second(): number
		for _ = 1, SETTLE do
			round()
		end

		records = 0
		for _ = 1, TICKS do
			round()
		end

		return records
	end

	-- The client reads no OwnerState, so they are taken and dropped rather than left to fill its queue
	client.Owner.on(function (_: buffer) end)
	client.flush()
	rig:deliver()

	-- Facing along -Z, so the target ahead of it, off the floor and falling, is in its view and always moving
	local viewer: any = server:create(key, rig:at(0, 0))
	server:create(rig.mock:addBot("Target"), rig:at(0, -FAR))

	local counts: { number } = {}
	table.insert(counts, second())
	viewer:setZoomed(true)
	table.insert(counts, second())
	viewer:setZoomed(false)
	table.insert(counts, second())

	if pcall(viewer.setZoomed, viewer, "on") then
		return false, "setZoomed took a string"
	end

	viewer:setZoomed(true)
	viewer:destroy()
	if pcall(viewer.setZoomed, viewer, false) then
		return false, "setZoomed ran on a character that was destroyed"
	end

	server:create(key, rig:at(0, 0))
	table.insert(counts, second())

	for index: number, expected: number in EXPECTED do
		if counts[index] ~= expected then
			local got: string = `{counts[index]} records, not {expected} ({table.concat(counts, ", ")})`
			return false, `Second {index} sent the client {got}`
		end
	end

	return true, nil
end
