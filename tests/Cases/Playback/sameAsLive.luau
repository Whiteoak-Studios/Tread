--[[
    A clip draws what the live client drew: a 40-tick scene of a walker that
    rests and moves on, a player hidden, one revealed, a look change and a
    sleeper's move, fed live at an interpolation delay equal to the clip's
    view lag and then played as a clip, draws the same rigs, looks and
    poses at ten times within 1e-6
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 1200
local TICKS: number = 40
local WALKER: number = 50
local HIDDEN: number = 51 -- In view from the keyframe, hidden at K + 20
local VISITOR: number = 52 -- Revealed at K + 8
local SLEEPER: number = 53 -- Moved down at K + 18
local TARGET: number = 60
local GENERATION: number = 1
local LAG: number = 150 -- Milliseconds, the live client's interpolation.delay
local HALF: number = 1 / 40 -- Seconds, half a relay interval: two live frames a tick
local REST_FROM: number = 10 -- The walker stops here, sends repeats at K + 12 and K + 16 and moves on after
local REPEAT: number = 12
local REST_TO: number = 16
local HIDE: number = 20
local REVEAL: number = 8
local MOVE: number = 18
local RESTYLE: number = 25
local PACE: number = 0.5 -- Studs a tick the walker moves
local TURN: number = 0.05 -- Radians a tick it turns
local DRIFT: number = 0.3 -- Studs a tick the hidden player moves
local STROLL: number = 0.2 -- Studs a tick the visitor moves
local SLEPT_AT: vector = vector.create(0, 30, 5)
local DROPPED_AT: vector = vector.create(0, 10, 5)
local FIRST_HEAD: number = 1
local SECOND_HEAD: number = 2
local CLOSE: number = 1e-6

-- The ticks after the keyframe the two are compared at, half an interval past each
local COMPARED: { number } = { 4, 6, 9, 11, 13, 17, 19, 22, 24, 33 }

-- The walker's place on a tick: moving on, but held still from its rest to the tick it moves on
local function walkerAt(index: number): vector
	local moved: number = index
	if index >= REST_FROM then
		moved = math.max(REST_FROM, index - (REST_TO - REST_FROM))
	end

	return vector.create(moved * PACE, 0, 0)
end

-- The relay block the target was sent on a tick, the same spec the live client and the clip are both built from
local function blockAt(index: number): { [string]: any }
	local tick: number = K + index
	local reveals: { any } = {}
	local hides: { any } = {}
	local looks: { any } = {}
	local records: { any } = {}

	if index == 0 then
		reveals = {
			{ slot = WALKER, generation = GENERATION, kind = "Player" },
			{ slot = HIDDEN, generation = GENERATION, kind = "Player" },
			{ slot = SLEEPER, generation = GENERATION, kind = "Sleeper" },
		}
		looks = { { slot = WALKER, generation = GENERATION, outfit = { head = FIRST_HEAD } } }
		table.insert(records, { slot = SLEEPER, generation = GENERATION, position = SLEPT_AT })
	elseif index == REVEAL then
		reveals = { { slot = VISITOR, generation = GENERATION, kind = "Player" } }
	elseif index == MOVE then
		reveals = { { slot = SLEEPER, generation = GENERATION, kind = "Sleeper" } }
		table.insert(records, { slot = SLEEPER, generation = GENERATION, position = DROPPED_AT })
	elseif index == HIDE then
		hides = { { slot = HIDDEN, generation = GENERATION } }
	elseif index == RESTYLE then
		looks = { { slot = WALKER, generation = GENERATION, outfit = { head = SECOND_HEAD } } }
	end

	local resting: boolean = index > REST_FROM and index < REST_TO and index ~= REPEAT
	if not resting then
		table.insert(records, {
			slot = WALKER,
			generation = GENERATION,
			position = walkerAt(index),
			yaw = index * TURN,
			pitch = index * TURN / 2,
		})
	end

	if index < HIDE then
		table.insert(records, {
			slot = HIDDEN,
			generation = GENERATION,
			position = vector.create(10, 0, index * DRIFT),
		})
	end

	if index >= REVEAL then
		table.insert(records, {
			slot = VISITOR,
			generation = GENERATION,
			position = vector.create(-5, 0, index * STROLL),
		})
	end

	return { tick = tick, reveals = reveals, hides = hides, looks = looks, records = records }
end

-- The newest look a pool's stand-in gave each slot's rig, from its checkout and every dress since
local function worn(pool: any): { [number]: number? }
	local heads: { [number]: number? } = {}
	for _, call: any in pool.calls do
		if call.member == "checkout" or call.member == "dress" then
			heads[call.slot] = call.outfit.head
		end
	end

	return heads
end

-- Why one draw differs from the other, nil when they match
local function differs(
	live: { [number]: any },
	played: { [number]: any },
	liveHeads: { [number]: number? },
	playedHeads: { [number]: number? }
): string?
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
		elseif math.abs(drawn.facing - pose.facing) > CLOSE or math.abs(drawn.lean - pose.lean) > CLOSE then
			return `slot {slot} faced {drawn.facing} leaning {drawn.lean} in the clip, {pose.facing} and {pose.lean} live`
		elseif math.abs(drawn.pitch - pose.pitch) > CLOSE then
			return `slot {slot} took a pitch of {drawn.pitch} in the clip and {pose.pitch} live`
		elseif drawn.mode ~= pose.mode or drawn.posture ~= pose.posture or drawn.grounded ~= pose.grounded then
			return `slot {slot} was {drawn.mode} {drawn.posture} in the clip and {pose.mode} {pose.posture} live`
		elseif drawn.platform ~= pose.platform or drawn.epoch ~= pose.epoch then
			return `slot {slot} rode {drawn.platform} at epoch {drawn.epoch} in the clip, {pose.platform} and {pose.epoch} live`
		elseif playedHeads[slot] ~= liveHeads[slot] then
			return `slot {slot} wore head {playedHeads[slot]} in the clip and {liveHeads[slot]} live`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	-- 1) The live client, sent each block and drawn twice a tick, its draws kept at the compared ticks
	local live: any = Handle.new()
	live.handshake()
	live.slots({
		{ slot = WALKER, generation = GENERATION, rig = "A" },
		{ slot = HIDDEN, generation = GENERATION, rig = "A" },
		{ slot = VISITOR, generation = GENERATION, rig = "A" },
		{ slot = SLEEPER, generation = GENERATION, rig = "A" },
	})

	local liveLog: any = Clip.log(live)
	local compared: { [number]: boolean } = {}
	for _, index: number in COMPARED do
		compared[index] = true
	end

	local liveDraws: { [number]: { [number]: any } } = {}
	local liveLooks: { [number]: { [number]: number? } } = {}
	for index: number = 0, TICKS - 1 do
		live.relay(blockAt(index))

		local count: number = #liveLog.poses
		live.frames(1, HALF)
		if compared[index] then
			liveDraws[index] = liveLog.since(count)
			liveLooks[index] = worn(live.pool)
		end

		live.frames(1, HALF)
	end

	-- The scene draws each rule live: the visitor once shown, the hidden player before its hide closes and not
	-- after, the sleeper partway down its fall, and the walker's new look
	local falling: any = liveDraws[22][SLEEPER]
	if liveDraws[11][VISITOR] == nil or liveDraws[22][HIDDEN] == nil or liveDraws[24][HIDDEN] ~= nil then
		return false, "The live scene didn't show the visitor, or the hidden player before and not after its hide"
	elseif falling == nil or not (falling.position.y < SLEPT_AT.y and falling.position.y > DROPPED_AT.y) then
		return false, "The live scene didn't draw the sleeper partway down its fall"
	elseif liveLooks[33][WALKER] ~= SECOND_HEAD then
		return false, "The live scene didn't give the walker its new look"
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
				{
					slot = WALKER,
					generation = GENERATION,
					kind = "Player",
					record = { position = walkerAt(0) },
					outfit = { head = FIRST_HEAD },
				},
				{
					slot = HIDDEN,
					generation = GENERATION,
					kind = "Player",
					record = { position = vector.create(10, 0, 0) },
				},
				{ slot = SLEEPER, generation = GENERATION, kind = "Sleeper", record = { position = SLEPT_AT } },
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

		local problem: string? = differs(liveDraws[index], playedLog.since(count), liveLooks[index], worn(played.pool))
		if problem then
			return false, `{index} ticks after the keyframe, {problem}`
		end
	end

	playback:destroy()

	return true, nil
end
