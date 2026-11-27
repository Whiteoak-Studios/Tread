--[[
    A spectate's start puts away every character drawn from before its tick
    and starts the Move's acknowledgment again; while it lasts every other
    player is outlined and never a sleeper or the owner, and a player the
    withheld block carries is drawn with its Slot's withheld set. Its end
    restarts the moderator's own view and takes every outline off
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local SEEN: number = 3 -- A player both views send
local WITHHELD: number = 7 -- Withheld from the target
local SLEEPER: number = 8
local TARGET: number = 14
local GENERATION: number = 1
local OWN_TICK: number = 50
local START: number = 60
local END: number = 70
local FRAMES: number = 4

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local rigs: any = handle._rigs
	local need: any = rig.globals.require
	local tread: any = rig.tread

	local Block: any = need(tread.Codec.Block)
	local Constants: any = need(tread.Constants)
	local Record: any = need(tread.Codec.Record)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }

	-- The pool's stand-in has no outline or watch, so each is added, the outlines written down by slot
	local outlined: { [number]: boolean } = {}
	local outlines: number = 0
	rigs.outline = function (_: any, slot: number, on: boolean)
		outlined[slot] = on
		outlines += 1
	end
	rigs.watch = function (_: any, _: number?) end

	local spawned: { [number]: any } = {}
	handle:onSpawned(function (slot: any, _: any)
		spawned[slot.id] = slot
	end)

	-- A withheld block of players' records at the last relay block's sequence, as the server's rides its copy
	local function withhold(tick: number, slots: { number })
		local block: any = Block.new()
		block.sequence = rig.sequence
		block.tick = tick

		local data: buffer = buffer.create(#slots * Constants.RECORD_BYTES)
		for index: number, slot: number in slots do
			local record: any = Record.new()
			record.slot, record.generation = slot, GENERATION
			Record.write(record, data, (index - 1) * Constants.RECORD_BYTES, limits)
			block.records[index] = (index - 1) * Constants.RECORD_BYTES
		end
		block.recordData, block.recordCount = data, #slots

		local scratch: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
		local bytes: number = Block.write(block, scratch)
		local exact: buffer = buffer.create(bytes)
		buffer.copy(exact, 0, scratch, 0, bytes)

		rig.send("Withheld", exact)
	end

	-- The acknowledgment the newest Move the server heard carries
	local function acknowledged(): number?
		rig.frames(1)
		rig.step()

		local last: any = rig.moves[#rig.moves]
		return last and last.acknowledged
	end

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.slots({
		{ slot = SEEN, generation = GENERATION, rig = "A" },
		{ slot = WITHHELD, generation = GENERATION, rig = "A" },
		{ slot = SLEEPER, generation = GENERATION, rig = "A" },
		{ slot = TARGET, generation = GENERATION, rig = "A" },
	})
	rig.owner(rig.body(vector.create(0, 50, 0), 0, OWN_TICK))

	-- 1) The moderator's own view draws a player, and its Moves acknowledge its blocks
	rig.relay({
		tick = OWN_TICK,
		reveals = { { slot = SEEN, generation = GENERATION, kind = "Player" } },
		records = { { slot = SEEN, generation = GENERATION, position = vector.create(5, 0, 0) } },
	})
	rig.frames(FRAMES)

	if spawned[SEEN] == nil or acknowledged() ~= rig.sequence then
		return false, "The moderator's own view drew nothing, or its Moves didn't acknowledge it"
	elseif outlines ~= 0 then
		return false, "A rig was outlined before any spectate"
	end

	-- 2) The start puts away what was drawn from before its tick, and acknowledges nothing until a block
	rig.send("Spectate", Record.id(TARGET, GENERATION), START)

	local released: any = pool.of("release")[1]
	if released == nil or released.slot ~= SEEN then
		return false, "The spectate's start didn't put away the player drawn from the moderator's own view"
	elseif acknowledged() ~= 0 then
		return false, "A Move after the spectate's start acknowledged a block of the old view"
	end

	-- 3) The target's view: its blocks acknowledged afresh, the other player outlined, the withheld one marked
	rig.relay({
		tick = START,
		reveals = {
			{ slot = SEEN, generation = GENERATION, kind = "Player" },
			{ slot = SLEEPER, generation = GENERATION, kind = "Sleeper" },
		},
		records = {
			{ slot = SEEN, generation = GENERATION, position = vector.create(6, 0, 0) },
			{ slot = SLEEPER, generation = GENERATION, position = vector.create(0, 0, 6) },
		},
	})
	withhold(START, { WITHHELD })
	rig.frames(FRAMES)

	if acknowledged() ~= rig.sequence then
		return false, "The target's first block wasn't the acknowledgment's new start"
	elseif outlined[SEEN] ~= true or outlined[WITHHELD] ~= true then
		return false, "A player in the target's view wasn't outlined while the client spectates"
	elseif outlined[SLEEPER] ~= nil or outlined[OWN] ~= nil then
		return false, "A sleeper or the owner's own rig was outlined"
	elseif spawned[WITHHELD] == nil or spawned[WITHHELD].withheld ~= true then
		return false, "The player the withheld block carries wasn't drawn with its Slot withheld"
	elseif spawned[SEEN].withheld ~= false then
		return false, "A player the target is sent was drawn as withheld"
	end

	-- 4) The end: the moderator's own view comes back from its tick, and every outline comes off
	rig.relay({
		tick = END,
		reveals = { { slot = SEEN, generation = GENERATION, kind = "Player" } },
		records = { { slot = SEEN, generation = GENERATION, position = vector.create(7, 0, 0) } },
	})
	rig.send("Spectate", nil, END)
	rig.frames(1)

	local gone: { [number]: boolean } = {}
	for _, call: any in pool.of("release") do
		gone[call.slot] = true
	end

	if outlined[SEEN] ~= false then
		return false, "The player still drawn kept its outline after the spectate's end"
	elseif not gone[WITHHELD] or not gone[SLEEPER] then
		return false, "The spectate's end left the target's view's withheld player or sleeper out"
	end

	return true, nil
end
