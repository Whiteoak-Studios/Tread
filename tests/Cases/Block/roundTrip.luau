--[[
    A relay block carries every section in order, whatever order it was
    filled in: reveals of each kind, hides, look entries with each mix of
    parts, footstep entries and records, through Volt's Relay to a viewer
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local STEPS: number = 3 -- Mock steps for a flush to reach the client
local SEQUENCE: number = 65535
local TICK: number = 4321
local KINDS: { string } = { "Player", "Npc", "Body", "Sleeper" }

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local replicatedStorage: any = globals.game:GetService("ReplicatedStorage")
	local tread: any = replicatedStorage.Packages.Tread

	local server: any = globals.require(tread.Network.Server)
	local client: any = globals.require(tread.Network.Client)
	local mock: any = globals.require(replicatedStorage.Packages.Volt).mock
	local Block: any = globals.require(tread.Codec.Block)
	local Fields: any = globals.require(tread.Codec.Fields)
	local Record: any = globals.require(tread.Codec.Record)
	local roblox: any = require("@lune/roblox")

	local layout: any = Fields.compile(Game.fields)

	-- Each slot's look and held item packed once, as the relay keeps them
	local parts: buffer = buffer.create(64 + 16)
	local lookLength: number = Fields.write(layout.slot, Game.high.slot, parts, 0)
	local heldLength: number = Fields.write(layout.held, Game.high.held, parts, 64)

	-- Three records and two footstep entries, encoded once each into pools the block copies from
	local records: { { [string]: any } } = {}
	local recordPool: buffer = buffer.create(3 * 16)
	for index: number = 1, 3 do
		local record: { [string]: any } = Record.new()
		record.slot, record.generation = 4093 + index - 1, index
		record.position = vector.create(index * 10, index, -index * 10)
		record.word = index
		Record.write(record, recordPool, (index - 1) * 16, Game.limits)
		table.insert(records, record)
	end

	local steps: { { [string]: any } } = {
		{ at = vector.create(1, 2, 3), kind = "Sprint", material = roblox.Enum.Material.Grass },
		{ at = vector.create(-4, 5, -6), kind = "Land", material = roblox.Enum.Material.Concrete },
	}
	local stepPool: buffer = buffer.create(2 * 10)
	for index: number, step: { [string]: any } in steps do
		Block.writeFootstep(step, stepPool, (index - 1) * 10)
	end

	-- Filled records first and reveals last, the reverse of the order they go out in
	local block: any = Block.new()
	block.sequence, block.tick = SEQUENCE, TICK
	block.recordData, block.records, block.recordCount = recordPool, { 32, 0, 16 }, 3
	block.footstepData, block.footsteps, block.footstepCount = stepPool, { 10, 0 }, 2

	local looks: { { [string]: any } } = {
		{ look = true, lookLength = lookLength, held = true, heldLength = heldLength }, -- Both parts
		{ look = true, lookLength = lookLength, held = false, heldLength = 0 }, -- The look alone
		{ look = false, lookLength = 0, held = true, heldLength = 0 }, -- Nothing held
		{ look = false, lookLength = 0, held = false, heldLength = 0 },
	}
	for index: number, look: { [string]: any } in looks do
		look.slot, look.generation = index, 15
		look.lookData, look.lookAt = parts, 0
		look.heldData, look.heldAt = parts, 64
	end

	block.looks, block.lookCount = looks, #looks
	block.hides, block.hideCount = { { slot = 4095, generation = 0 }, { slot = 0, generation = 15 } }, 2

	local reveals: { { [string]: any } } = {}
	for index: number, kind: string in KINDS do
		table.insert(reveals, { slot = index * 100, generation = index, kind = kind })
	end

	block.reveals, block.revealCount = reveals, #reveals

	local data: buffer = buffer.create(896)
	local bytes: number = Block.write(block, data)
	local size: number = 8
		+ 4 * 3
		+ 2 * 2
		+ (5 + lookLength + heldLength)
		+ (4 + lookLength)
		+ (4 + 0)
		+ 3
		+ 2 * 10
		+ 3 * 16
	if bytes ~= size then
		return false, `The block filled {bytes} B, where its sections fill {size}`
	end

	-- The header: the sequence, the tick, then the four counts
	local header: { number } = { 0xFF, 0xFF, TICK % 256, TICK // 256, 4, 2, 4, 2 }
	for index: number, byte: number in header do
		if buffer.readu8(data, index - 1) ~= byte then
			return false, `Header byte {index - 1} is {buffer.readu8(data, index - 1)}, where it is {byte}`
		end
	end

	-- Through Volt to the viewer, as a buffer of the block's exact length
	local exact: buffer = buffer.create(bytes)
	buffer.copy(exact, 0, data, 0, bytes)

	local heard: buffer? = nil
	client.Relay.on(function (received: buffer)
		heard = received
	end)

	-- The client's handshake goes out on its first flush, before which the server sends it nothing
	client.flush()
	for _ = 1, STEPS do
		mock:step()
	end

	server.Relay.fire(mock.players[1], exact)
	server.flush()
	for _ = 1, STEPS do
		mock:step()
	end

	if not heard then
		return false, "The block never reached the viewer"
	end

	local read: any = Block.new()
	Block.read(heard, read)

	if read.sequence ~= SEQUENCE or read.tick ~= TICK then
		return false, `The block read as sequence {read.sequence} at tick {read.tick}`
	end

	for index: number = 1, 4 do
		local differs: string? = Same(reveals[index], read.reveals[index], `reveal {index}`)
		if differs then
			return false, differs
		end
	end

	for index: number = 1, 2 do
		local differs: string? = Same(block.hides[index], read.hides[index], `hide {index}`)
		if differs then
			return false, differs
		end
	end

	if read.revealCount ~= 4 or read.hideCount ~= 2 or read.lookCount ~= 4 then
		return false, "The block read back other section counts than it was written with"
	end

	for index: number, look: { [string]: any } in looks do
		local back: { [string]: any } = read.looks[index]
		if back.slot ~= look.slot or back.generation ~= 15 or back.look ~= look.look or back.held ~= look.held then
			return false, `Look entry {index} read back as slot {back.slot} with other parts`
		end

		if look.look then
			local outfit: { [string]: any } = {}
			if
				back.lookLength ~= lookLength or Fields.read(layout.slot, heard, back.lookAt, back.lookLength, outfit)
			then
				return false, `Look entry {index}'s look read back other bytes than it was packed to`
			end

			local differs: string? = Same(Game.high.slot, outfit, `look {index}`)
			if differs then
				return false, differs
			end
		end

		if look.held and back.heldLength ~= look.heldLength then
			return false, `Look entry {index}'s held item read back {back.heldLength} B, not {look.heldLength}`
		end
	end

	local item: { [string]: any } = {}
	Fields.read(layout.held, heard, read.looks[1].heldAt, read.looks[1].heldLength, item)
	local differs: string? = Same(Game.high.held, item, "held item")
	if differs then
		return false, differs
	end

	-- Footstep entries and records in the order the block named them
	for index: number, from: number in { 2, 1 } do
		local step: { [string]: any } = { at = vector.zero, kind = "Walk", material = roblox.Enum.Material.Air }
		Block.readFootstep(heard, read.footsteps[index], step)

		differs = Same(steps[from], step, `footstep {index}`)
		if differs then
			return false, differs
		end
	end

	for index: number, from: number in { 3, 1, 2 } do
		local record: { [string]: any } = Record.new()
		Record.read(heard, read.records[index], record, Game.limits)

		differs = Same(records[from], record, `record {index}`)
		if differs then
			return false, differs
		end
	end

	return true, nil
end
