--[[
    A clip draws a reveal's past as the live client does: a player anti-ESP
    hid, its stretch closed, then revealed with a past reaching back before
    the last stretch's newest record, is drawn from the clip tick the reveal
    arrived and never before, at the same poses as live within 1e-6
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 1400
local TICKS: number = 24
local PLAYER: number = 50 -- Seen from the keyframe, hidden by anti-ESP, then revealed with its past
local TARGET: number = 60
local GENERATION: number = 1
local LAG: number = 100 -- Milliseconds, the live client's interpolation.delay
local HALF: number = 1 / 40 -- Seconds, half a relay interval: two live frames a tick
local HIDE: number = 7 -- The block carrying the hide, and none of the player's records
local REVEAL: number = 10 -- The block carrying the reveal and its past
local AGES: { number } = { 5, 4, 3, 2, 1 } -- Its past, the oldest before the last record its stretch was sent
local TURN: number = 6 -- The player walks along x up to here, then along z, while it is hidden
local PACE: number = 0.5 -- Studs a tick
local CLOSE: number = 1e-6

-- The ticks after the keyframe the two are compared at, half an interval past each
local COMPARED: { number } = { 3, 5, 7, 8, 9, 10, 11, 12, 15, 20 }

-- Where the player stands on a tick after the keyframe
local function path(index: number): vector
	if index <= TURN then
		return vector.create(index * PACE, 0, 0)
	end

	return vector.create(TURN * PACE, 0, (index - TURN) * PACE)
end

local function record(index: number): { [string]: any }
	return { slot = PLAYER, generation = GENERATION, position = path(index) }
end

-- The relay block the target was sent on a tick, the same spec the live client and the clip are both built from
local function blockAt(index: number): { [string]: any }
	local reveals: { any } = {}
	local hides: { any } = {}
	local records: { any } = {}

	if index == 0 then
		reveals = { { slot = PLAYER, generation = GENERATION, kind = "Player" } }
	elseif index == HIDE then
		hides = { { slot = PLAYER, generation = GENERATION, culled = true } }
	elseif index == REVEAL then
		local past: { any } = {}
		for _, age: number in AGES do
			table.insert(past, { age = age, record = record(index - age) })
		end

		reveals = { { slot = PLAYER, generation = GENERATION, kind = "Player", past = past } }
	end

	if index < HIDE or index >= REVEAL then
		table.insert(records, record(index))
	end

	return { tick = K + index, reveals = reveals, hides = hides, records = records }
end

-- Why one draw differs from the other, nil when they match
local function differs(live: { [number]: any }, played: { [number]: any }): string?
	for slot: number in played do
		if slot ~= TARGET and live[slot] == nil then
			return `the clip drew slot {slot}, which the live client didn't`
		end
	end

	for slot: number, pose: any in live do
		local drawn: any = played[slot]
		if drawn == nil then
			return `the live client drew slot {slot}, which the clip didn't`
		elseif vector.magnitude(drawn.position - pose.position) > CLOSE then
			return `slot {slot} was drawn at {drawn.position} in the clip and {pose.position} live`
		elseif vector.magnitude(drawn.velocity - pose.velocity) > CLOSE then
			return `slot {slot} moved at {drawn.velocity} in the clip and {pose.velocity} live`
		elseif math.abs(drawn.facing - pose.facing) > CLOSE then
			return `slot {slot} faced {drawn.facing} in the clip and {pose.facing} live`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	-- 1) The live client, sent each block and drawn twice a tick, its draws kept at the compared ticks
	local live: any = Handle.new()
	live.handshake()
	live.slots({ { slot = PLAYER, generation = GENERATION, rig = "A" } })

	local liveLog: any = Clip.log(live)
	local compared: { [number]: boolean } = {}
	for _, index: number in COMPARED do
		compared[index] = true
	end

	local liveDraws: { [number]: { [number]: any } } = {}
	for index: number = 0, TICKS - 1 do
		live.relay(blockAt(index))

		local count: number = #liveLog.poses
		live.frames(1, HALF)
		if compared[index] then
			liveDraws[index] = liveLog.since(count)
		end

		live.frames(1, HALF)
	end

	-- The scene draws each rule live: the player while its hide waits, its frozen body undrawn once the hide passes,
	-- and the player drawn again on the frame after its reveal arrived, its past reaching back past that render time
	if liveDraws[HIDE + 1][PLAYER] == nil or liveDraws[REVEAL - 1][PLAYER] ~= nil then
		return false, "The live scene didn't draw the player while its hide waited, or drew it once the hide passed"
	elseif #live.pool.of("freeze") ~= 1 then
		return false, "The live scene's hide left no frozen body"
	elseif liveDraws[REVEAL][PLAYER] == nil then
		return false, "The live scene didn't draw the player on the frame after its reveal with a past arrived"
	end

	-- 2) The clip of the same blocks, its view lag the live delay, drawn at the same clip ticks
	local played: any = Handle.new()
	played.handshake()

	local clip: any = Clip.new(played)
	local playedLog: any = Clip.log(played)
	local relay: number = played.shared.rates.relay

	local ticks: { buffer } = {
		clip.keyframe({
			tick = K,
			characters = {
				{ slot = PLAYER, generation = GENERATION, kind = "Player", record = { position = path(0) } },
			},
		}),
	}

	for index: number = 0, TICKS - 1 do
		local tick: number = K + index
		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { blockAt(index) },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = LAG },
			})
		)
	end

	local playback: any = played.handle:play(ticks)
	for _, index: number in COMPARED do
		local count: number = #playedLog.poses
		playback:render((index + 0.5) / relay)

		local problem: string? = differs(liveDraws[index], playedLog.since(count))
		if problem then
			return false, `{index} ticks after the keyframe, {problem}`
		end
	end

	playback:destroy()

	return true, nil
end
