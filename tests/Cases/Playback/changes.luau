--[[
    A clip's tap blocks carry every record whole: client:play refuses a
    frame or withheld frame with a change record, and draws from a block of
    60 records, past the 896 B a relay block holds
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 200
local FRAMES: number = 5
local WALKER: number = 5
local TARGET: number = 9
local OTHERS: number = 100 -- The first of the slots the big block's other records name
local GENERATION: number = 1
local LAG: number = 50 -- Milliseconds, one relay tick at 20 Hz
local FAR: vector = vector.create(4, 0, 0)
local RECORDS: number = 60
local REASON: string = "Clear"
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	rig.handshake()

	local need: any = rig.globals.require
	local Block: any = need(rig.tread.Codec.Block)
	local Constants: any = need(rig.tread.Constants)
	local OwnerState: any = need(rig.tread.Codec.OwnerState)
	local Record: any = need(rig.tread.Codec.Record)
	local Tap: any = need(rig.tread.Codec.Tap)

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local relay: number = rig.shared.rates.relay

	local function owner(tick: number): { [string]: any }
		return { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = LAG }
	end

	-- A block's bytes holding one still change of the walker's, against the record a tick before
	local function changed(tick: number): buffer
		local change: buffer = buffer.create(4)
		buffer.writeu16(change, 0, Record.id(WALKER, GENERATION))
		buffer.writeu8(change, 2, 1)

		local block: any = Block.new()
		block.tick = tick
		block.changeData, block.changeOffsets, block.changeLengths, block.changeCount = change, { 0 }, { 4 }, 1

		local data: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
		local bytes: number = Block.write(block, data)
		local exact: buffer = buffer.create(bytes)
		buffer.copy(exact, 0, data, 0, bytes)

		return exact
	end

	-- A frame whose one block holds the walker's record at FAR and 59 others, written within a tap block's bound
	local function big(tick: number): buffer
		local block: any = Block.new()
		local pool: buffer = buffer.create(RECORDS * Constants.RECORD_BYTES)
		local reasons: { string } = {}
		for index: number = 1, RECORDS do
			local fields: { [string]: any } = { slot = OTHERS + index, generation = GENERATION, position = vector.zero }
			if index == 1 then
				fields = { slot = WALKER, generation = GENERATION, position = FAR }
			end

			buffer.copy(pool, (index - 1) * Constants.RECORD_BYTES, clip.record(fields))
			block.records[index] = (index - 1) * Constants.RECORD_BYTES
			reasons[index] = REASON
		end

		block.tick = tick
		block.recordData, block.recordCount = pool, RECORDS

		local data: buffer = buffer.create(Constants.TAP_BLOCK_BYTES)
		local bytes: number = Block.write(block, data, Constants.TAP_BLOCK_BYTES)
		local exact: buffer = buffer.create(bytes)
		buffer.copy(exact, 0, data, 0, bytes)

		local body: buffer = buffer.create(Tap.blockBytes(bytes, RECORDS))
		local filled: number = Tap.writeBlock(body, 0, exact, reasons, RECORDS)
		local scratch: buffer = buffer.create(Constants.MAX_OWNER_STATE)
		local made: { [string]: any } = owner(tick)
		local ownerLength: number = OwnerState.write(made.state, scratch, 0, clip.layout, clip.limits)
		local id: number = Record.id(TARGET, GENERATION)

		return Tap.frame(tick, 1, body, filled, scratch, ownerLength, id, LAG, {}, 0, clip.limits)
	end

	local keyframe: buffer = clip.keyframe({
		tick = K,
		characters = { { slot = WALKER, generation = GENERATION, kind = "Player", record = {} } },
	})

	local ticks: { buffer } = { keyframe }
	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		if index == 2 then
			table.insert(ticks, big(tick))
		else
			table.insert(ticks, clip.frame({ tick = tick, blocks = { { tick = tick } }, owner = owner(tick) }))
		end
	end

	-- 1) A frame or withheld frame carrying a change record is refused by name, the clip unplayed
	local carrying: buffer = clip.frame({ tick = K + 1, blocks = { changed(K + 1) }, owner = owner(K + 1) })
	local refusals: { { name: string, ticks: { buffer }, withheld: { buffer }? } } = {
		{ name = "a frame", ticks = { keyframe, carrying } },
		{
			name = "a withheld frame",
			ticks = ticks,
			withheld = { clip.frame({ tick = K + 1, blocks = { changed(K + 1) } }) },
		},
	}

	for _, refusal in refusals do
		local played: boolean, problem: any = pcall(handle.play, handle, refusal.ticks, refusal.withheld)
		if played then
			return false, `client:play took {refusal.name} with a change record`
		elseif not string.find(tostring(problem), "client:play", 1, true) then
			return false, `client:play refused {refusal.name} without naming itself: {problem}`
		elseif not string.find(tostring(problem), "change records", 1, true) or handle._playback ~= nil then
			return false, `client:play refused {refusal.name} as "{problem}"`
		end
	end

	-- 2) The 60-record block draws the walker as any block does: halfway to FAR a tick behind its arrival
	local playback: any = handle:play(ticks)
	local count: number = #log.poses
	playback:render(2 / relay)

	local drawn: any = log.since(count)[WALKER]
	if drawn == nil or math.abs(drawn.position.x - FAR.x / 2) > CLOSE then
		return false, `The walker was drawn at {drawn and drawn.position}, not halfway to {FAR} from the big block`
	end

	playback:destroy()

	return true, nil
end
