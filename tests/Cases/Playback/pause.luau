--[[
    The pool's track speed follows the clip seconds a frame's renders moved
    over the frame's own: the same time over two frames draws the same pose
    and holds the rigs still, a quarter of a frame's time plays at 0.25,
    one relay interval moves a walker exactly one tick, and the end gives
    each track its own speed back
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 600
local FRAMES: number = 20
local WALKER: number = 7
local TARGET: number = 9
local GENERATION: number = 1
local FRAME: number = 1 / 60 -- Seconds a rendered frame takes
local START: number = 0.3 -- Seconds into the clip the renders start at
local QUARTER: number = 0.25
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	rig.handshake()

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local relay: number = rig.shared.rates.relay

	local function walker(tick: number): { [string]: any }
		return { slot = WALKER, generation = GENERATION, position = vector.create(tick - K, 0, 0) }
	end

	local ticks: { buffer } = {
		clip.keyframe({
			tick = K,
			characters = { { slot = WALKER, generation = GENERATION, kind = "Player", record = walker(K) } },
		}),
	}

	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { { tick = tick, records = { walker(tick) } } },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
			})
		)
	end

	-- The walker's place a render draws, and the speed the frame after it gave the pool, nil for none given
	local function step(time: number): (vector?, number?)
		local poses: number = #log.poses
		local speeds: number = #pool.of("setSpeed")

		handle._playback:render(time)
		rig.frames(1, FRAME)

		local drawn: any = log.since(poses)[WALKER]
		local given: { any } = pool.of("setSpeed")
		local speed: number? = nil
		if #given > speeds then
			speed = given[#given].speed
		end

		return drawn and drawn.position, speed
	end

	local playback: any = handle:play(ticks)

	-- 1) The first frame has nothing to measure, and the same time over the next gives the same pose and a pause
	local first: vector? = step(START)
	local held: vector?, paused: number? = step(START)
	if first == nil or held == nil then
		return false, "The walker wasn't drawn"
	elseif vector.magnitude(first - held) > CLOSE then
		return false, `The same time drew the walker at {first} and then {held}`
	elseif paused ~= 0 then
		return false, `The same time over two frames set the track speed to {paused}, not 0`
	end

	-- 2) A quarter of a frame's time over a frame plays at a quarter of each track's speed
	local _, slow: number? = step(START + QUARTER * FRAME)
	if slow == nil or math.abs(slow - QUARTER) > CLOSE then
		return false, `A quarter of a frame's progress set the track speed to {slow}, not {QUARTER}`
	end

	-- 3) One relay interval moves the walker, a stud a tick, by exactly one stud
	local before: vector? = step(START)
	local after: vector? = step(START + 1 / relay)
	if before == nil or after == nil or math.abs((after - before).x - 1) > CLOSE then
		return false, `One relay interval moved the walker from {before} to {after}, not one stud`
	end

	-- 4) The end gives each track its own speed back
	playback:destroy()
	local given: { any } = pool.of("setSpeed")
	if given[#given].speed ~= 1 then
		return false, `The playback's end left the track speed at {given[#given].speed}`
	end

	return true, nil
end
