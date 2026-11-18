--[[
    Each of the relay's three cross-VM buffers round-trips through its writer
    and reader with every field at its edges: the shared hand-in, a worker's
    own and its result, with the view copies its changes keep level
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local TURN: string = "src/Server/Relay/Turn.luau"

local SLOTS: number = 4096 -- Constants.SLOTS
local TOP_SLOT: number = SLOTS - 1
local RECORD_BYTES: number = 16
local MAX_LOOK: number = 64
local MAX_HELD: number = 16
local FOOTSTEP_BYTES: number = 10
local DEPTH: number = 32
local ROW_BYTES: number = SLOTS // 8
local U16_TOP: number = 2 ^ 16 - 1
local U32_TOP: number = 2 ^ 32 - 1
local MAX_BLOCK: number = 896 -- Constants.MAX_RELAY_BYTES, the block pool's largest
local TAP_BLOCK: number = U16_TOP -- Constants.TAP_BLOCK_BYTES, a tap frame's largest block
local HEADER_BLOCK: number = 9 -- An empty block's header alone
local RECIPIENTS: number = 32 -- A target and Constants.MAX_WATCHERS watchers
local VIEWERS: number = 300
local STEPS: number = 300 -- Past the 256 a world's footstep buffers start with
local CALLS: number = 75 -- Past the 64 a call log starts with
local FAILURE_LENGTH: number = 1000

type Check = (boolean, string) -> ()

-- The Turn module of an environment, its Wire beside it, and a second Turn of a VM of its own
type Sides = {
	Wire: any,
	Turn: any,
	Other: any,
}

local function sides(): Sides
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread

	return {
		Wire = globals.require(tread.Server.Relay.Wire),
		Turn = globals.require(tread.Server.Relay.Turn),
		Other = Environment.load(TURN),
	}
end

-- Starts a Turn with records as changes, so its world keeps the history a reader writes into
local function start(turn: any)
	local function none(): any
		return false
	end

	turn.start({
		relayRate = 20,
		enter = 950,
		leave = 1000,
		sleepers = 500,
		npcs = 800,
		nearEnterSquared = 40000,
		nearLeaveSquared = 48400,
		nearAim = 20,
		nearFloor = 15,
		farAim = 15,
		farFloor = 10,
		weightNear = 1,
		weightFar = 0.5,
		weightShooter = 2,
		weightCone = 1.5,
		shotRate = 10,
		soft = 64000,
		hard = 96000,
		npcNearSquared = 38809,
		npcFarRate = 2,
		earshot = { 1600, 3600, 3600, 3600 },
		outOfView = nil,
		changes = true,
	}, {
		send = none,
		sendWithheld = none,
		heard = none,
		traffic = none,
		isHidden = none,
		valid = none,
		observing = none,
		observes = none,
		relayed = none,
		withheld = none,
	})
end

-- length bytes counting up from seed, so no two fields hold the same
local function pattern(length: number, seed: number): buffer
	local data: buffer = buffer.create(length)
	for index: number = 0, length - 1 do
		buffer.writeu8(data, index, (seed + index * 7) % 256)
	end

	return data
end

-- Whether length bytes of a from at match those of b from bAt
local function same(a: buffer, at: number, b: buffer, bAt: number, length: number): boolean
	return buffer.readstring(a, at, length) == buffer.readstring(b, bAt, length)
end

-- A Shared for a reader to fill
local function emptyShared(): any
	return {
		run = 0,
		tick = 0,
		elapsed = 0,
		wire = 0,
		places = 0,
		looks = {},
		lookCount = 0,
		helds = {},
		heldCount = 0,
		observing = false,
		observed = {},
		observedCount = 0,
		kinds = buffer.create(SLOTS),
		teams = buffer.create(SLOTS * 8),
	}
end

--[[
    The shared hand-in at its edges: slots 0 and 4,095, a life of 255, the
    longest look and held item beside empty ones, the u32 run and changed
    tick at their tops, a NaN team and facing, and more footsteps than a
    world's buffers start with; then an empty one, with zero footsteps
--]]

local function shared(s: Sides, check: Check)
	local Wire: any = s.Wire
	local from: any = s.Turn.world
	local into: any = s.Other.world
	start(s.Other)

	local run: number = U32_TOP
	local bodies: { { [string]: any } } = {
		{
			slot = TOP_SLOT,
			life = 255,
			kind = 3,
			unparked = true,
			at = vector.create(8192, -1024, -8192),
			facing = -math.pi,
			changed = U32_TOP,
			team = 0 / 0,
			anti = 3,
		},
		{
			slot = 0,
			life = 0,
			kind = 0,
			unparked = false,
			at = vector.zero,
			facing = 0 / 0,
			changed = 0,
			team = -1.5,
			anti = 0,
		},
		{
			slot = 7,
			life = 9,
			kind = 1,
			unparked = true,
			at = vector.create(1.5, 2.25, -3.125),
			facing = 1e300,
			changed = 12345,
			team = 2 ^ 53,
			anti = 1,
		},
	}

	local sharedOut: any = emptyShared()
	sharedOut.run = run
	sharedOut.tick = 2 ^ 40 + 0.5
	sharedOut.elapsed = 3
	sharedOut.wire = U16_TOP
	sharedOut.places = #bodies
	sharedOut.observing = true

	for place: number, body: { [string]: any } in bodies do
		local slot: number = body.slot
		buffer.writeu16(from.walk, place * 2, slot)
		buffer.writeu8(from.generations, slot, body.life)
		buffer.writeu8(from.kinds, slot, body.kind)
		if body.unparked then
			buffer.writeu32(from.unparked, slot * 4, run)
		end

		from.positions[slot + 1] = body.at
		buffer.writef64(from.facings, slot * 8, body.facing)
		buffer.writeu32(from.changed, slot * 4, body.changed)
		buffer.copy(from.records, slot * RECORD_BYTES, pattern(RECORD_BYTES, slot))
		buffer.writeu8(sharedOut.kinds, slot, body.anti)
		buffer.writef64(sharedOut.teams, slot * 8, body.team)
	end

	-- The longest look and held item on the top slot, empty ones on slot 0
	buffer.copy(from.looks, TOP_SLOT * MAX_LOOK, pattern(MAX_LOOK, 1))
	buffer.writeu8(from.lookLengths, TOP_SLOT, MAX_LOOK)
	buffer.writeu8(from.lookLives, TOP_SLOT, 255)
	buffer.writeu16(from.lookVersions, TOP_SLOT * 2, U16_TOP)
	buffer.writeu8(from.invisible, TOP_SLOT, 255)
	buffer.copy(from.helds, TOP_SLOT * MAX_HELD, pattern(MAX_HELD, 2))
	buffer.writeu8(from.heldLengths, TOP_SLOT, MAX_HELD)
	buffer.writeu16(from.heldVersions, TOP_SLOT * 2, U16_TOP)
	buffer.writeu16(from.heldVersions, 0, 1)

	sharedOut.looks = { 0, TOP_SLOT }
	sharedOut.lookCount = 2
	sharedOut.helds = { TOP_SLOT, 0 }
	sharedOut.heldCount = 2
	sharedOut.observed = { 1, U32_TOP, 77 }
	sharedOut.observedCount = 3

	local steps: any = from.steps
	steps.capacity = STEPS
	steps.slots = buffer.create(STEPS * 2)
	steps.kinds = buffer.create(STEPS)
	steps.data = pattern(STEPS * FOOTSTEP_BYTES, 3)
	steps.count = STEPS
	for index: number = 0, STEPS - 1 do
		local slot: number = index % 2 == 0 and 0 or TOP_SLOT
		buffer.writeu16(steps.slots, index * 2, slot)
		buffer.writeu8(steps.kinds, index, index % 4 + 1)
		steps.places[index + 1] = vector.create(index, -index / 4, index * 2)
	end

	local data: buffer = Wire.writeShared(from, sharedOut)
	local read: any = emptyShared()
	local at: number = Wire.readLooks(data, into, read)
	Wire.readBodies(data, at, into, read, true)

	for _, field: string in
		{ "run", "tick", "elapsed", "wire", "places", "lookCount", "heldCount", "observing", "observedCount" }
	do
		check(
			read[field] == sharedOut[field],
			`The shared hand-in's {field} came back {read[field]}, not {sharedOut[field]}`
		)
	end

	local plane: number = (run % DEPTH) * SLOTS
	for place: number, body: { [string]: any } in bodies do
		local slot: number = body.slot
		local unparked: boolean = buffer.readu32(into.unparked, slot * 4) == run
		check(buffer.readu16(into.walk, place * 2) == slot, `Walk place {place} came back other than slot {slot}`)
		check(buffer.readu32(into.present, slot * 4) == run, `Slot {slot} came back not present this run`)
		check(buffer.readu8(into.generations, slot) == body.life, `Slot {slot}'s life came back wrong`)
		check(buffer.readu8(into.kinds, slot) == body.kind, `Slot {slot}'s kind came back wrong`)
		check(unparked == body.unparked, `Slot {slot}'s unparked mark came back {unparked}`)
		check(into.positions[slot + 1] == body.at, `Slot {slot}'s place came back {into.positions[slot + 1]}`)
		check(same(into.facings, slot * 8, from.facings, slot * 8, 8), `Slot {slot}'s facing came back other bytes`)
		check(buffer.readu32(into.changed, slot * 4) == body.changed, `Slot {slot}'s changed tick came back wrong`)
		check(
			same(into.records, slot * RECORD_BYTES, from.records, slot * RECORD_BYTES, RECORD_BYTES),
			`Slot {slot}'s record came back other bytes`
		)
		check(
			same(into.history, (plane + slot) * RECORD_BYTES, from.records, slot * RECORD_BYTES, RECORD_BYTES),
			`Slot {slot}'s record missed the run's plane of the history`
		)
		check(buffer.readu8(read.kinds, slot) == body.anti, `Slot {slot}'s anti-ESP kind came back wrong`)
		check(same(read.teams, slot * 8, sharedOut.teams, slot * 8, 8), `Slot {slot}'s team came back other bytes`)
	end

	for _, slot: number in { 0, TOP_SLOT } do
		local length: number = buffer.readu8(from.lookLengths, slot)
		check(buffer.readu8(into.lookLengths, slot) == length, `Slot {slot}'s look length came back wrong`)
		check(
			same(into.looks, slot * MAX_LOOK, from.looks, slot * MAX_LOOK, length),
			`Slot {slot}'s look came back other bytes`
		)
		check(
			buffer.readu8(into.lookLives, slot) == buffer.readu8(from.lookLives, slot),
			`Slot {slot}'s look life came back wrong`
		)
		check(
			buffer.readu16(into.lookVersions, slot * 2) == buffer.readu16(from.lookVersions, slot * 2),
			`Slot {slot}'s look version came back wrong`
		)
		check(
			buffer.readu8(into.invisible, slot) == buffer.readu8(from.invisible, slot),
			`Slot {slot}'s Invisible mark came back wrong`
		)

		local held: number = buffer.readu8(from.heldLengths, slot)
		check(buffer.readu8(into.heldLengths, slot) == held, `Slot {slot}'s held length came back wrong`)
		check(
			same(into.helds, slot * MAX_HELD, from.helds, slot * MAX_HELD, held),
			`Slot {slot}'s held item came back other bytes`
		)
		check(
			buffer.readu16(into.heldVersions, slot * 2) == buffer.readu16(from.heldVersions, slot * 2),
			`Slot {slot}'s held version came back wrong`
		)
	end

	check(read.looks[1] == 0 and read.looks[2] == TOP_SLOT, "The looks' marks came back in another order")
	check(read.helds[1] == TOP_SLOT and read.helds[2] == 0, "The held items' marks came back in another order")
	check(
		read.observed[1] == 1 and read.observed[2] == U32_TOP and read.observed[3] == 77,
		"The observed ids came back wrong"
	)

	local intoSteps: any = into.steps
	check(
		intoSteps.count == STEPS and intoSteps.capacity >= STEPS,
		`{intoSteps.count} footsteps came back, not {STEPS}`
	)
	check(
		same(intoSteps.data, 0, steps.data, 0, STEPS * FOOTSTEP_BYTES),
		"The footsteps' entries came back other bytes"
	)
	for index: number = 0, STEPS - 1 do
		check(
			buffer.readu16(intoSteps.slots, index * 2) == buffer.readu16(steps.slots, index * 2),
			`Footstep {index}'s slot came back wrong`
		)
		check(
			buffer.readu8(intoSteps.kinds, index) == buffer.readu8(steps.kinds, index),
			`Footstep {index}'s kind came back wrong`
		)
		check(intoSteps.places[index + 1] == steps.places[index + 1], `Footstep {index}'s place came back wrong`)
	end

	-- An empty run: no body, no mark, no footstep and no sink
	steps.count = 0
	local empty: any = emptyShared()
	empty.run = 1
	local emptyData: buffer = Wire.writeShared(from, empty)
	local emptyRead: any = emptyShared()
	Wire.readBodies(emptyData, Wire.readLooks(emptyData, into, emptyRead), into, emptyRead, true)

	check(buffer.len(emptyData) == 35, `An empty shared hand-in took {buffer.len(emptyData)} B, not its 35 B header`)
	check(
		emptyRead.run == 1 and emptyRead.places == 0 and not emptyRead.observing,
		"An empty shared hand-in's header came back wrong"
	)
	check(intoSteps.count == 0, `An empty shared hand-in left {intoSteps.count} footsteps`)
end

--[[
    A worker's own hand-in at its edges: every call kind with its ids and
    values at their tops, more calls than a log starts with, and 300
    viewers with and without a slot, a target, a look and a return, each
    with no target carrying its row; then one with zero viewers
--]]

local function own(s: Sides, check: Check)
	local Wire: any = s.Wire
	local calls: any = Wire.calls()
	local queued: { { number } } = {
		{ Wire.SHOT_NEAR, 1, TOP_SLOT, U32_TOP },
		{ Wire.REVEAL, U32_TOP, 0, 0 },
		{ Wire.REVEAL_ALL, 5, 0, 2 ^ 31 },
		{ Wire.SET_DISTANCE, 6, 0, 0.125 },
		{ Wire.REMOVE, 7, 0, 0 },
	}

	for index: number = #queued + 1, CALLS do
		queued[index] = { index % 5 + 1, index, index % SLOTS, index / 3 }
	end

	for _, call: { number } in queued do
		Wire.call(calls, call[1], call[2], call[3], call[4])
	end

	local visible: buffer = pattern(VIEWERS * ROW_BYTES, 5)
	local hands: { any } = {}
	for index: number = 1, VIEWERS do
		local watching: boolean = index % 3 == 0
		local slot: number? = nil
		if index % 4 == 1 then
			slot = 0
		elseif index % 4 == 2 then
			slot = TOP_SLOT
		elseif index % 4 == 3 then
			slot = index
		end

		local look: vector? = nil
		if index % 2 == 0 then
			look = vector.create(-1, 0, index / 1024)
		end

		local team: number = 0 / 0
		if index % 5 == 0 then
			team = -index
		end

		local target: number? = nil
		if watching then
			target = index + 1
		end

		hands[index] = {
			id = index == VIEWERS and U32_TOP or index,
			slot = slot,
			target = target,
			position = vector.create(index * 0.5, -index, 8192 - index),
			look = look,
			acknowledged = index % 2 == 0 and U16_TOP or 0,
			received = index % 3 == 1 and U16_TOP or index,
			sequence = index % 7 == 0 and U16_TOP or index,
			back = not watching and index % 2 == 1,
			traffic = index * 1e9 + 0.5,
			team = team,
			row = (index - 1) * ROW_BYTES,
		}
	end

	local data: buffer = Wire.writeOwn(calls, hands, VIEWERS, visible, true)
	check(Wire.callCount(data) == CALLS, `The own hand-in carried {Wire.callCount(data)} calls, not {CALLS}`)
	check(Wire.resend(data), "The own hand-in lost its resend flag")

	for index: number, call: { number } in queued do
		local kind: number, id: number, slot: number, value: number = Wire.readCall(data, index)
		check(
			kind == call[1] and id == call[2] and slot == call[3] and value == call[4],
			`Call {index} came back {kind} {id} {slot} {value}`
		)
	end

	local read: { any } = {}
	check(Wire.readOwn(data, read) == VIEWERS, `The own hand-in's viewers didn't come back {VIEWERS}`)

	for index: number, hand: any in hands do
		local back: any = read[index]
		for _, field: string in
			{ "id", "slot", "target", "position", "look", "acknowledged", "received", "sequence", "back", "traffic" }
		do
			check(back[field] == hand[field], `Viewer {index}'s {field} came back {back[field]}, not {hand[field]}`)
		end

		check(
			back.team == hand.team or (back.team ~= back.team and hand.team ~= hand.team),
			`Viewer {index}'s team came back {back.team}`
		)
		if hand.target == nil then
			check(same(data, back.row, visible, hand.row, ROW_BYTES), `Viewer {index}'s row came back other bytes`)
		end
	end

	-- No viewers and no calls: the header alone, with no resend
	local empty: buffer = Wire.writeOwn(Wire.calls(), {}, 0, visible, false)
	check(buffer.len(empty) == 7 and Wire.callCount(empty) == 0, `An empty own hand-in took {buffer.len(empty)} B`)
	check(not Wire.resend(empty), "An own hand-in with no resend carried the flag")
	check(Wire.readOwn(empty, read) == 0, "An empty own hand-in's viewers didn't come back 0")
end

-- A stand-in for a view with the fields a view's copy is made from
local function view(): any
	return {
		own = nil,
		tracked = {},
		flags = buffer.create(SLOTS * 2),
		generations = buffer.create(SLOTS),
		kinds = buffer.create(SLOTS),
		withheld = nil,
	}
end

-- Why a copy differs from a view in what the front's queries read of it, or nil when it doesn't
local function differs(s: Sides, copy: any, from: any): string?
	local Turn: any = s.Turn
	if copy.own ~= from.own then
		return `its own came back {copy.own}, not {from.own}`
	elseif (copy.withheld ~= nil) ~= (from.withheld ~= nil) then
		return "its withheld set came back otherwise"
	elseif #copy.tracked ~= #from.tracked then
		return `its tracked list came back {#copy.tracked} long, not {#from.tracked}`
	end

	for index: number, slot: number in from.tracked do
		if copy.tracked[index] ~= slot then
			return `its tracked place {index} came back {copy.tracked[index]}, not {slot}`
		end
	end

	for slot: number = 0, SLOTS - 1 do
		local flags: number = buffer.readu16(from.flags, slot * 2)
		local sent: boolean = bit32.btest(flags, Turn.SENT)
		local owned: boolean = bit32.btest(flags, Turn.OWN)
		local kept: number = buffer.readu16(copy.flags, slot * 2)

		if sent ~= bit32.btest(kept, Turn.SENT) or owned ~= bit32.btest(kept, Turn.OWN) then
			return `slot {slot}'s sent or own mark came back otherwise`
		elseif (sent or owned) and buffer.readu8(copy.generations, slot) ~= buffer.readu8(from.generations, slot) then
			return `slot {slot}'s life came back otherwise`
		elseif sent and buffer.readu8(copy.kinds, slot) ~= buffer.readu8(from.kinds, slot) then
			return `slot {slot}'s kind came back otherwise`
		end

		local withheld: any = from.withheld
		if withheld then
			local marked: boolean = bit32.btest(buffer.readu8(withheld.flags, slot), Turn.WITHHELD)
			if marked ~= bit32.btest(buffer.readu8(copy.withheld.flags, slot), Turn.WITHHELD) then
				return `slot {slot}'s withheld mark came back otherwise`
			elseif marked and buffer.readu8(copy.withheld.lives, slot) ~= buffer.readu8(withheld.lives, slot) then
				return `slot {slot}'s withheld life came back otherwise`
			end
		end
	end

	return nil
end

-- A tap block whose records are those slots' own
local function tapOf(slots: { number }): any
	local records: { number } = {}
	for index: number, slot: number in slots do
		records[index] = slot * RECORD_BYTES
	end

	return { recordCount = #slots, records = records }
end

--[[
    A worker's result at its edges: every ask from walk place 1 to 4,096, a
    turn with a target's 32 recipients, the largest block and tap block,
    every event kind, a turn with none, each watch answer, a long failure,
    the u32 counts at their tops, and view changes from slots 0 and 4,095;
    then a second run's changes after a slot is let go, over zero places
--]]

local function result(s: Sides, check: Check)
	local Wire: any = s.Wire
	local Turn: any = s.Turn
	local writer: any = Wire.writer()
	local ids: { number } = {}
	for index: number = 1, RECIPIENTS - 1 do
		ids[index] = index
	end

	ids[RECIPIENTS] = U32_TOP

	local asked: { number } = { 1, 8, 9, 4000, SLOTS }
	local largest: buffer = pattern(MAX_BLOCK, 6)
	local header: buffer = pattern(HEADER_BLOCK, 7)
	local tapped: buffer = pattern(TAP_BLOCK, 8)
	local withheld: buffer = pattern(MAX_BLOCK, 9)
	local everySlot: { number } = {}
	for slot: number = 0, TOP_SLOT do
		everySlot[slot + 1] = slot
	end

	Wire.begin(writer, SLOTS)
	Wire.watch(writer, nil)
	Wire.watch(writer, false)
	Wire.watch(writer, true)

	Wire.turn(writer, 1, ids, RECIPIENTS)
	for _, place: number in asked do
		Wire.ask(writer, place)
	end

	Wire.send(writer, largest)
	Wire.relayed(writer, tapOf({ 0, TOP_SLOT, 5 }), nil)
	Wire.heard(writer, U16_TOP)
	Wire.send(writer, header)
	Wire.relayed(writer, tapOf(everySlot), tapped)
	Wire.heard(writer, 0)
	Wire.withheld(writer, withheld)
	Wire.withheldTap(writer, tapOf({ TOP_SLOT }))
	Wire.withheld(writer, header)

	Wire.turn(writer, VIEWERS, { 9 }, 1)

	local first: any = view()
	first.own = TOP_SLOT
	first.withheld = { flags = buffer.create(SLOTS), lives = buffer.create(SLOTS) }
	first.tracked = { 0, TOP_SLOT, 7 }
	buffer.writeu16(first.flags, 0, Turn.SENT)
	buffer.writeu8(first.generations, 0, 255)
	buffer.writeu8(first.kinds, 0, 3)
	buffer.writeu16(first.flags, TOP_SLOT * 2, Turn.OWN)
	buffer.writeu8(first.generations, TOP_SLOT, 15)
	buffer.writeu16(first.flags, 7 * 2, Turn.SENT)
	buffer.writeu8(first.kinds, 7, 1)
	buffer.writeu8(first.withheld.flags, 0, Turn.WITHHELD)
	buffer.writeu8(first.withheld.lives, 0, 255)

	local second: any = view()
	local firstShadow: any = Wire.copy()
	local secondShadow: any = Wire.copy()
	Wire.view(writer, 1, first, firstShadow)
	Wire.view(writer, U32_TOP, second, secondShadow)

	local failure: string = string.rep("x", FAILURE_LENGTH)
	local data: buffer = Wire.finish(writer, U32_TOP, 0, 123, VIEWERS, failure)

	local records: buffer = buffer.create(SLOTS * RECORD_BYTES)
	local reader: any = Wire.reader(records)
	Wire.open(reader, data)

	check(
		reader.turns == 2 and reader.views == 2 and reader.answers == 3,
		"The result's counts of turns, views and answers came back wrong"
	)
	check(
		reader.places == SLOTS and reader.sent == U32_TOP and reader.cut == 0 and reader.visited == 123,
		"The result's run counts came back wrong"
	)
	check(reader.failed == VIEWERS and reader.failure == failure, "The result's failure came back wrong")
	check(
		Wire.watched(reader, 1) == nil and Wire.watched(reader, 2) == false and Wire.watched(reader, 3) == true,
		"The watch answers came back wrong"
	)

	check(Wire.nextTurn(reader), "The result's first turn wasn't there")
	check(
		reader.place == 1 and reader.recipientCount == RECIPIENTS,
		"The first turn's place or recipients came back wrong"
	)
	for index: number, id: number in ids do
		check(reader.recipients[index] == id, `Recipient {index} came back {reader.recipients[index]}, not {id}`)
	end

	-- A list longer than the asks, whose entry past them the read must leave alone
	local places: { number } = { 0, 0, 0, 0, 0, -1 }
	check(Wire.asks(reader, places) == #asked, "The first turn's asks came back another count")
	for index: number, expected: number in asked do
		check(places[index] == expected, `Ask {index} came back at walk place {places[index]}, not {expected}`)
	end

	check(places[#asked + 1] == -1, "The read of the asks wrote past their count")

	-- Each event in order: its kind, then its bytes, records or sequence
	local events: { { any } } = {
		{ Wire.SEND, largest },
		{ Wire.RELAYED, largest, { 0, TOP_SLOT, 5 } },
		{ Wire.HEARD, U16_TOP },
		{ Wire.SEND, header },
		{ Wire.RELAYED, tapped, everySlot },
		{ Wire.HEARD, 0 },
		{ Wire.WITHHELD, withheld },
		{ Wire.WITHHELD_TAP, withheld, { TOP_SLOT } },
		{ Wire.WITHHELD, header },
	}

	for index: number, expected: { any } in events do
		local kind: number = Wire.nextEvent(reader)
		check(kind == expected[1], `Event {index} came back of kind {kind}, not {expected[1]}`)

		if kind == Wire.HEARD then
			check(reader.sequence == expected[2], `Event {index}'s sequence came back {reader.sequence}`)
		else
			check(
				buffer.tostring(reader.block) == buffer.tostring(expected[2]),
				`Event {index}'s bytes came back otherwise`
			)
		end

		local slots: { number }? = expected[3]
		if slots then
			check(
				reader.tap.recordCount == #slots and reader.tap.recordData == records,
				`Event {index}'s tap came back otherwise`
			)
			for at: number, slot: number in slots do
				check(reader.tap.records[at] == slot * RECORD_BYTES, `Event {index}'s record {at} came back otherwise`)
			end
		end
	end

	check(Wire.nextEvent(reader) == 0, "The first turn came back with an event past its last")
	check(
		Wire.nextTurn(reader) and reader.place == VIEWERS and reader.recipients[1] == 9,
		"The second turn came back wrong"
	)
	check(
		#reader.recipients == 1 and Wire.asks(reader, places) == 0 and Wire.nextEvent(reader) == 0,
		"The empty turn came back with something in it"
	)
	check(not Wire.nextTurn(reader), "The result came back with a turn past its last")

	local firstCopy: any = Wire.copy()
	local secondCopy: any = Wire.copy()
	check(Wire.nextView(reader) == 1, "The first view's id came back wrong")
	Wire.applyView(reader, firstCopy)
	check(Wire.nextView(reader) == U32_TOP, "The second view's id came back wrong")
	Wire.applyView(reader, secondCopy)
	check(Wire.nextView(reader) == 0, "The result came back with a view past its last")

	for name: string, pair: { any } in
		{ first = { firstCopy, first }, second = { secondCopy, second }, shadow = { firstShadow, first } }
	do
		local why: string? = differs(s, pair[1], pair[2])
		check(why == nil, `The {name} view's copy differs: {why}`)
	end

	-- Slot 0 let go as untrack lets it go, slot 7 revealed as another kind, over a run of no places
	first.tracked = { 7, TOP_SLOT }
	buffer.writeu16(first.flags, 0, 0)
	buffer.writeu8(first.withheld.flags, 0, 0)
	buffer.writeu8(first.kinds, 7, 2)
	first.own = nil

	Wire.begin(writer, 0)
	Wire.view(writer, 1, first, firstShadow)
	Wire.open(reader, Wire.finish(writer, 0, 0, 0, 0, ""))

	check(
		reader.places == 0 and reader.failed == 0 and reader.failure == "",
		"The second result's header came back wrong"
	)
	check(not Wire.nextTurn(reader) and Wire.nextView(reader) == 1, "The second result's turns or view came back wrong")
	Wire.applyView(reader, firstCopy)

	local why: string? = differs(s, firstCopy, first)
	check(why == nil, `The view's copy after its slot was let go differs: {why}`)
end

return function (): (boolean, string | nil)
	local failure: string? = nil
	local function check(passed: boolean, reason: string)
		if not passed and failure == nil then
			failure = reason
		end
	end

	shared(sides(), check)
	own(sides(), check)
	result(sides(), check)

	if failure ~= nil then
		return false, failure
	end

	return true, nil
end
