--[[
    The playback cases' clips: keyframes, relay blocks and tap frames built
    with Tread's own codecs over a client rig's tables, and a log of what
    the rig pool is told while a clip draws
--]]

--!strict
local WIRE: number = 2 ^ 16 -- The values a u16 tick holds
local REASON: string = "Clear" -- The send reason every record a frame carries is given
local SCRATCH_BYTES: number = 128 -- Past the largest OwnerState, look or held item

export type Builder = { [string]: any }
export type Log = { [string]: any }

local Clip = {}

--[[
    A builder over a client rig from the client handle's fixture, whose
    codecs and declarations every buffer it makes is packed with
--]]

function Clip.new(rig: any): Builder
	local need: any = rig.globals.require
	local tread: any = rig.tread

	local Block: any = need(tread.Codec.Block)
	local Constants: any = need(tread.Constants)
	local Fields: any = need(tread.Codec.Fields)
	local Keyframe: any = need(tread.Codec.Keyframe)
	local OwnerState: any = need(tread.Codec.OwnerState)
	local Record: any = need(tread.Codec.Record)
	local StateWord: any = need(tread.Codec.StateWord)
	local Tap: any = need(tread.Codec.Tap)

	local shared: any = rig.shared
	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = shared.step.lean, headCone = shared.step.headCone }

	local builder: Builder = {
		layout = layout,
		limits = limits,
		hash = Fields.hash(layout),
		sequence = 0,
		Record = Record,
	}

	-- A list of game fields packed into a buffer of its own length
	local function pack(list: any, values: { [string]: any }): buffer
		local scratch: buffer = buffer.create(SCRATCH_BYTES)
		local length: number = Fields.write(list, values, scratch, 0)
		local data: buffer = buffer.create(length)
		buffer.copy(data, 0, scratch, 0, length)

		return data
	end

	-- A 16 B record of Record fields by name, every one but slot, generation and position optional
	function builder.record(fields: { [string]: any }): buffer
		local record: { [string]: any } = Record.new()
		for name: string, value: any in fields do
			record[name] = value
		end

		local data: buffer = buffer.create(Constants.RECORD_BYTES)
		Record.write(record, data, 0, limits)

		return data
	end

	-- A state word for a record, every field at rest but those given
	function builder.word(fields: { [string]: any }): number
		return rig.word(fields)
	end

	--[[
	    One relay block's bytes, its sequence counting up from 1. Reveals and
	    hides are { slot, generation, kind }; looks are { slot, generation,
	    outfit?, held?, empty? }, empty a held part of 0 B; records are Record
	    fields by name; footsteps are Block's
	--]]

	function builder.block(spec: { [string]: any }): buffer
		local block: any = Block.new()
		builder.sequence += 1
		block.sequence = builder.sequence % WIRE
		block.tick = spec.tick % WIRE

		local reveals: { any } = spec.reveals or {}
		local hides: { any } = spec.hides or {}
		block.reveals, block.revealCount = reveals, #reveals
		block.hides, block.hideCount = hides, #hides

		local looks: { any } = spec.looks or {}
		local partBytes: number = Constants.MAX_LOOK + Constants.MAX_HELD
		local parts: buffer = buffer.create(math.max(#looks, 1) * partBytes)

		for index: number, look: { [string]: any } in looks do
			local at: number = (index - 1) * partBytes
			local entry: { [string]: any } = {
				slot = look.slot,
				generation = look.generation,
				look = false,
				lookData = parts,
				lookAt = at,
				lookLength = 0,
				held = look.empty == true,
				heldData = parts,
				heldAt = at + Constants.MAX_LOOK,
				heldLength = 0,
			}

			if look.outfit then
				entry.look = true
				entry.lookLength = Fields.write(layout.slot, look.outfit, parts, at)
			end

			if look.held then
				entry.held = true
				entry.heldLength = Fields.write(layout.held, look.held, parts, at + Constants.MAX_LOOK)
			end

			block.looks[index] = entry
		end

		block.lookCount = #looks

		local records: { any } = spec.records or {}
		local recordData: buffer = buffer.create(math.max(#records, 1) * Constants.RECORD_BYTES)
		for index: number, fields: { [string]: any } in records do
			buffer.copy(recordData, (index - 1) * Constants.RECORD_BYTES, builder.record(fields))
			block.records[index] = (index - 1) * Constants.RECORD_BYTES
		end

		block.recordData, block.recordCount = recordData, #records

		local steps: { any } = spec.footsteps or {}
		local stepData: buffer = buffer.create(math.max(#steps, 1) * Constants.FOOTSTEP_BYTES)
		for index: number, step: any in steps do
			Block.writeFootstep(step, stepData, (index - 1) * Constants.FOOTSTEP_BYTES)
			block.footsteps[index] = (index - 1) * Constants.FOOTSTEP_BYTES
		end

		block.footstepData, block.footstepCount = stepData, #steps

		local data: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
		local bytes: number = Block.write(block, data)
		local exact: buffer = buffer.create(bytes)
		buffer.copy(exact, 0, data, 0, bytes)

		return exact
	end

	--[[
	    A keyframe at a relay tick: characters are { slot, generation, kind,
	    withheld?, record, outfit?, held? }, record the Record fields beside
	    slot and generation; platforms are { id, tick }; own is { slot,
	    generation, outfit?, held? }; a hash or version given stands in for
	    the declarations' own
	--]]

	function builder.keyframe(spec: { [string]: any }): buffer
		local characters: { any } = {}
		for _, character: { [string]: any } in spec.characters or {} do
			local fields: { [string]: any } = table.clone(character.record or {})
			fields.slot = character.slot
			fields.generation = character.generation
			fields.position = fields.position or vector.zero

			table.insert(characters, {
				kind = character.kind or "Player",
				withheld = character.withheld == true,
				record = builder.record(fields),
				look = character.outfit and pack(layout.slot, character.outfit) or buffer.create(0),
				held = character.held and pack(layout.held, character.held) or buffer.create(0),
			})
		end

		local own: any = nil
		if spec.own then
			own = {
				id = Record.id(spec.own.slot, spec.own.generation),
				look = spec.own.outfit and pack(layout.slot, spec.own.outfit) or buffer.create(0),
				held = spec.own.held and pack(layout.held, spec.own.held) or buffer.create(0),
			}
		end

		local data: buffer = Keyframe.write({
			hash = spec.hash or builder.hash,
			tick = spec.tick % WIRE,
			sequence = 0,
			characters = characters,
			platforms = spec.platforms or {},
			own = own,
		})

		if spec.version then
			buffer.writeu16(data, 0, spec.version)
		end

		return data
	end

	-- A state the server sends as the target's OwnerState: at rest on the ground at a place, on a simulation tick
	function builder.state(position: vector, tick: number): any
		local state: any = rig.body(position, 0, tick % WIRE)
		state.mode = "Ground"
		state.grounded = true

		return state
	end

	--[[
	    A tap frame at a relay tick: blocks are block specs or bytes, and
	    owner is { slot, generation, state, lag, looks }, its lag in
	    milliseconds and its looks { yaw, pitch, headYaw, headPitch },
	    newest first, as the target stepped them since the frame before
	--]]

	function builder.frame(spec: { [string]: any }): buffer
		local blocks: { buffer } = {}
		for _, given: any in spec.blocks or {} do
			table.insert(blocks, typeof(given) == "buffer" and given or builder.block(given))
		end

		local read: any = Block.new()
		local length: number = 0
		for _, block: buffer in blocks do
			Block.read(block, read)
			length += Tap.blockBytes(buffer.len(block), read.recordCount)
		end

		local body: buffer = buffer.create(math.max(length, 1))
		local offset: number = 0
		for _, block: buffer in blocks do
			Block.read(block, read)

			local reasons: { string } = {}
			for index: number = 1, read.recordCount do
				reasons[index] = REASON
			end

			offset = Tap.writeBlock(body, offset, block, reasons, read.recordCount)
		end

		local owner: { [string]: any }? = spec.owner
		if not owner then
			return Tap.frame(spec.tick, #blocks, body, length, nil, 0, 0)
		end

		local scratch: buffer = buffer.create(Constants.MAX_OWNER_STATE)
		local ownerLength: number = OwnerState.write(owner.state, scratch, 0, layout, limits)
		local looks: { any } = owner.looks or {}

		return Tap.frame(
			spec.tick,
			#blocks,
			body,
			length,
			scratch,
			ownerLength,
			Record.id(owner.slot, owner.generation),
			owner.lag or 0,
			looks,
			#looks,
			limits
		)
	end

	builder.StateWord = StateWord

	return builder
end

--[[
    A log of what the client handle's rig pool is told: every pose with a
    copy of the state it drew, each watch, and each slot's outline, the
    stand-in's own records kept as they are
--]]

function Clip.log(rig: any): Log
	local rigs: any = rig.handle._rigs
	local log: Log = { poses = {}, watches = {}, outlined = {} }
	local pose: any = rigs.pose

	rigs.pose = function (self: any, slot: number, state: any, distance: number, pitch: number)
		pose(self, slot, state, distance, pitch)

		table.insert(log.poses, {
			slot = slot,
			position = state.position,
			facing = state.facing,
			lean = state.lean,
			velocity = state.velocity,
			mode = state.mode,
			posture = state.posture,
			platform = state.platform,
			epoch = state.epoch,
			grounded = state.grounded,
			distance = distance,
			pitch = pitch,
		})
	end

	rigs.watch = function (_: any, slot: number?)
		table.insert(log.watches, slot or false)
	end

	rigs.outline = function (_: any, slot: number, outlined: boolean)
		log.outlined[slot] = outlined
	end

	-- The poses since a count of them, by slot, the last of each
	function log.since(count: number): { [number]: any }
		local found: { [number]: any } = {}
		for index: number = count + 1, #log.poses do
			local drawn: any = log.poses[index]
			found[drawn.slot] = drawn
		end

		return found
	end

	return log
end

--[[
    The slots with a rig checked out of the pool's stand-in now, each with
    its rig, from the calls it was made in order
--]]

function Clip.out(pool: any): { [number]: any }
	local out: { [number]: any } = {}
	for _, call: any in pool.calls do
		if call.member == "checkout" then
			out[call.slot] = call.rig
		elseif call.member == "release" then
			out[call.slot] = nil
		elseif call.member == "ragdoll" then
			out[call.slot] = nil
			out[call.body] = call.rig
		end
	end

	return out
end

return Clip
