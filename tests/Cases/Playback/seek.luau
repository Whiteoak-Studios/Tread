--[[
    A render depends on its time alone: after seeks either way, each draws
    the rigs and poses a fresh playback's first render at that time draws,
    and a character revealed at 0.5 s and hidden at 0.8 s is drawn between
    them and before or after neither
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 500
local FRAMES: number = 25 -- Frames at K to K + 24, a little past 1.2 s at 20 Hz
local WALKER: number = 3 -- In view from the keyframe on
local VISITOR: number = 4 -- Revealed at K + 10 and hidden at K + 16
local TARGET: number = 9
local GENERATION: number = 1
local REVEAL: number = 10
local HIDE: number = 16
local TIMES: { number } = { 0.6, 0.2, 1, 0.6, 0.9 } -- Seconds, each render's, backward and forward
local CLOSE: number = 1e-6

-- The clip's buffers, the same bytes for every rig that plays them
local function build(clip: any): { buffer }
	local function walker(tick: number): { [string]: any }
		return { slot = WALKER, generation = GENERATION, position = vector.create(tick - K, 0, 0) }
	end

	local function visitor(tick: number): { [string]: any }
		return { slot = VISITOR, generation = GENERATION, position = vector.create(0, 0, tick - K) }
	end

	local ticks: { buffer } = {
		clip.keyframe({
			tick = K,
			characters = { { slot = WALKER, generation = GENERATION, kind = "Player", record = walker(K) } },
		}),
	}

	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		local records: { any } = { walker(tick) }
		local reveals: { any } = {}
		local hides: { any } = {}

		if index == REVEAL then
			reveals = { { slot = VISITOR, generation = GENERATION, kind = "Player" } }
		end

		if index >= REVEAL and index < HIDE then
			table.insert(records, visitor(tick))
		elseif index == HIDE then
			hides = { { slot = VISITOR, generation = GENERATION } }
		end

		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { { tick = tick, reveals = reveals, hides = hides, records = records } },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
			})
		)
	end

	return ticks
end

-- What a render drew: the slots with a rig out, and each pose's place, by slot
local function drawnAt(rig: any, log: any, playback: any, time: number): ({ [number]: any }, { [number]: any })
	local count: number = #log.poses
	playback:render(time)

	return Clip.out(rig.pool), log.since(count)
end

-- Why two renders drew differently, nil when they drew the same
local function differs(
	out: { [number]: any },
	poses: { [number]: any },
	fresh: { [number]: any },
	posed: { [number]: any }
): string?
	for slot: number in out do
		if fresh[slot] == nil then
			return `slot {slot} had a rig out that a fresh render has none for`
		end
	end

	for slot: number in fresh do
		if out[slot] == nil then
			return `slot {slot} had no rig out where a fresh render has one`
		end
	end

	for slot: number, pose: any in posed do
		local drawn: any = poses[slot]
		if drawn == nil or vector.magnitude(drawn.position - pose.position) > CLOSE then
			return `slot {slot} was drawn at {drawn and drawn.position}, not a fresh render's {pose.position}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	rig.handshake()

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local ticks: { buffer } = build(clip)
	local playback: any = rig.handle:play(ticks)
	local relay: number = rig.shared.rates.relay

	for _, time: number in TIMES do
		local out: { [number]: any }, poses: { [number]: any } = drawnAt(rig, log, playback, time)

		-- A fresh client playing the same clip, rendered once at that time
		local other: any = Handle.new()
		other.handshake()
		local otherLog: any = Clip.log(other)
		local fresh: { [number]: any }, posed: { [number]: any } =
			drawnAt(other, otherLog, other.handle:play(ticks), time)

		local problem: string? = differs(out, poses, fresh, posed)
		if problem then
			return false, `At {time} s after the renders before it, {problem}`
		end

		local visible: boolean = time > REVEAL / relay and time < HIDE / relay
		if (out[VISITOR] ~= nil) ~= visible then
			return false, `At {time} s the visitor had a rig out {out[VISITOR] ~= nil}, not {visible}`
		end
	end

	playback:destroy()

	return true, nil
end
