--[[
    Between a deferred tick's OwnerStates and its rest: a character created
    there is a viewer in the tick's run and sent in it with no sample, and
    gets its first OwnerState a tick later; a spectate started there is told
    it starts at the tick, while its first feed is the next tick's
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local CREATE: number = SplitSide.CALM + 1 -- The deferred tick a character is created between the two parts of
local WATCH: number = CREATE + 2 -- The deferred tick a spectate starts between the two parts of
local AFTER: number = 2 -- Ticks run after that
local TEAM: number = 7
local SLOTS: number = 4096 -- The slots a record's id counts in its low 12 bits

type Driven = SplitSide.Driven

-- Runs one deferred tick's three Heartbeats, a game's calls made between its own and the next
local function deferred(driven: Driven, between: () -> ())
	driven.tick += 1
	SplitSide.beat(driven, SplitSide.THIRD)
	between()
	SplitSide.beat(driven, SplitSide.THIRD)
	SplitSide.beat(driven, SplitSide.THIRD)
end

-- Whether a tap frame's blocks carry a record of a slot
local function carries(side: any, frame: any, slot: number): boolean
	local Block: any = side.rig:require(side.rig.tread.Codec.Block)
	local Constants: any = side.rig:require(side.rig.tread.Constants)
	local read: any = Block.new()

	for _, block: any in frame.blocks do
		Block.read(block.data, read, Constants.TAP_BLOCK_BYTES)
		for index: number = 1, read.recordCount do
			if buffer.readu16(read.recordData, read.records[index]) % SLOTS == slot then
				return true
			end
		end
	end

	return false
end

-- Each frame a list holds, by its tick
local function byTick(side: any, frames: { string }): { [number]: any }
	local found: { [number]: any } = {}
	for _, data: string in frames do
		local frame: any = side.Tap.read(buffer.fromstring(data))
		found[frame.tick] = frame
	end

	return found
end

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true })
	local side: any = driven.side
	local server: any = side.server

	-- The moderator stops watching the client, which spectates later itself
	server:spectate(side.keys.Moderator, nil)
	side.characters.Client:setTeam(TEAM)

	local told: { { target: number?, tick: number } } = {}
	local fed: { number } = {} -- Each feed's OwnerState's tick, past the feed's length byte
	side.client.Spectate.on(function (target: number?, tick: number)
		table.insert(told, { target = target, tick = tick })
	end)

	side.client.Feed.on(function (data: buffer)
		table.insert(fed, buffer.readu16(data, 3))
	end)

	local key: any = side.rig.mock:addBot("Late")
	local frames: { string } = {}
	server:observe(key, function (_: number, data: buffer)
		table.insert(frames, buffer.tostring(data))
	end)

	SplitSide.ticks(driven, CREATE - 1)

	local late: any = nil
	deferred(driven, function ()
		late = server:create(key, side.rig:at(3, 3))
		late:setTeam(TEAM)
	end)

	-- Its run sent it and made it a viewer, while the history holds no sample of it for the tick
	if server:sampleAt(late, CREATE) ~= nil then
		return false, `The character created before tick {CREATE}'s rest had a sample at that tick`
	end

	SplitSide.ticks(driven, WATCH - CREATE - 1)
	deferred(driven, function ()
		server:spectate(side.keys.Client, side.characters.Seen)
	end)
	SplitSide.ticks(driven, AFTER)

	-- Both ticks deferred, each rest on the Heartbeat after its own
	for _, tick: number in { CREATE, WATCH } do
		local rest: number = driven.flags[SplitSide.place(tick, 2)]
		if bit32.band(rest, side.Tick.DEFERRED) == 0 then
			return false, `Tick {tick} did not defer, its next Heartbeat's flags {rest}`
		end
	end

	local own: { [number]: any } = byTick(side, frames)
	local client: { [number]: any } = byTick(side, side.frames.Client)
	local made: any = own[CREATE]
	local after: any = own[CREATE + 1]

	if not made or #made.blocks == 0 or made.owner ~= nil then
		return false, `The created character's frame for tick {CREATE} gave it no blocks as a viewer, or an OwnerState`
	elseif not after or not after.owner or buffer.readu16(after.owner.data, 2) ~= CREATE + 1 then
		return false, `The created character's frame for tick {CREATE + 1} carried no OwnerState of that tick`
	elseif not client[CREATE] or not carries(side, client[CREATE], late._slot) then
		return false, `The client's frame for tick {CREATE} carried no record of the created character`
	end

	for tick: number = 1, CREATE - 1 do
		if own[tick] and #own[tick].blocks > 0 then
			return false, `The created character's frame for tick {tick}, before it was made, carried blocks`
		end
	end

	local Record: any = side.rig:require(side.rig.tread.Codec.Record)
	local seen: any = side.characters.Seen
	local id: number = Record.id(seen._slot, seen._generation)

	if #told ~= 1 or told[1].target ~= id or told[1].tick ~= WATCH then
		local first: string = told[1] and `{told[1].target} from {told[1].tick}` or "none"
		return false, `The spectating client was told {#told} starts, the first {first}, not {id} from {WATCH}`
	elseif fed[1] ~= WATCH + 1 or table.find(fed, WATCH) then
		return false, `The spectating client's first feed was tick {fed[1]}'s, not {WATCH + 1}'s`
	elseif #fed ~= AFTER then
		return false, `The spectating client had {#fed} feeds over the {AFTER} ticks after its start`
	end

	return true, nil
end
