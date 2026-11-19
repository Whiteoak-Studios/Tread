--[[
    Over Volt.mock a joining client gets the shared table's hash with the
    server's tick and the slot table, a Move it fires runs on its tick in
    place of a stand-in, its OwnerState comes back after that command, and
    its relay block reveals the NPC beside it
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local SETTLE: number = 4 -- Ticks before the Move, so the character stands
local SLOT_FIELD: number = 2 -- The example's held hotbar slot, which the Move's command carries
local DELAY: number = 150 -- Milliseconds of interpolation delay the Move reports

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local tread: any = rig.tread

	local Block: any = rig:require(tread.Codec.Block)
	local Command: any = rig:require(tread.Codec.Command)
	local Config: any = rig:require(tread.Config)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)
	local OwnerState: any = rig:require(tread.Codec.OwnerState)
	local State: any = rig:require(tread.Step.State)

	-- The client joins the mock as its player
	local client: any = rig:require(tread.Network.Client)
	local player: any = rig.mock.players[1]

	local shared: { { hash: number, tick: number } } = {}
	local entries: { any } = {}
	local owners: { string } = {}
	local revealed: { [number]: boolean } = {}

	client.Shared.on(function (hash: number, tick: number)
		table.insert(shared, { hash = hash, tick = tick })
	end)

	client.Slots.on(function (list: { any })
		for _, entry: any in list do
			table.insert(entries, entry)
		end
	end)

	client.Owner.on(function (data: buffer)
		table.insert(owners, buffer.tostring(data))
	end)

	client.Relay.on(function (data: buffer)
		local block: any = Block.new()
		Block.read(data, block)

		for index: number = 1, block.revealCount do
			revealed[block.reveals[index].slot] = true
		end
	end)

	client.flush()
	rig:deliver()

	local npc: any = server:createNpc(rig:at(4, 0))
	local character: any = server:create(player, rig:at(0, 0))
	rig:tick(SETTLE)
	rig:deliver()

	if #shared ~= 1 or shared[1].hash ~= Config.hash(rig.shared) then
		return false, `The client got {#shared} Shared messages, not one with the shared table's hash`
	elseif #entries ~= 2 or entries[1].taken == nil or entries[1].taken.rig ~= "A" then
		return false, `The client's slot table holds {#entries} entries, not the NPC's and the character's`
	elseif not revealed[npc._slot] then
		return false, "The client's relay blocks never revealed the NPC beside its character"
	elseif #owners == 0 then
		return false, "The client got no OwnerState"
	end

	-- A command for the next tick, which the server runs in place of a stand-in
	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local command: any = Command.new()
	command.number = SETTLE + 1
	command.forward = 1
	command.fields = { slot = SLOT_FIELD, shots = {} }

	local move: any = Move.new()
	Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits)
	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()
	rig:deliver()

	local before: number = #rig:reportedFor("standIn", player)
	local standing: number = character:getState().root.Z
	rig:tick(1)
	rig:deliver()

	if #rig:reportedFor("standIn", player) ~= before then
		return false, "The tick the Move's command belongs to ran a stand-in"
	elseif not (character:getState().root.Z < standing) then
		return false, "The Move's forward command did not move the character along -Z"
	end

	local latest: buffer = buffer.fromstring(owners[#owners])
	local into: any = State.new()
	OwnerState.read(latest, 0, buffer.len(latest), into, layout, limits)

	if into.command ~= SETTLE + 1 then
		return false, `The newest OwnerState follows command {into.command}, not the Move's {SETTLE + 1}`
	end

	return true, nil
end
