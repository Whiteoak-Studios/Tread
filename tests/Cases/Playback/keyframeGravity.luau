--[[
    A clip draws its sleepers' falls under the gravity its keyframe
    carries: one recorded at 30 on a client whose live gravity is 68.1
    draws a sleeper halfway through its fall's time under 30 at a quarter
    of its drop, where 68.1 would have it far lower
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 1000
local FRAMES: number = 30
local SLEEPER: number = 32
local TARGET: number = 9
local GENERATION: number = 1
local MOVE: number = 6 -- Ticks after the keyframe the sleeper's move comes
local RECORDED: number = 30 -- Studs/s², the gravity in force when the clip was recorded
local SLEPT_AT: vector = vector.create(0, 20, 0)
local DROPPED_AT: vector = vector.zero
local CLOSE: number = 1e-6
local APART: number = 1 -- Studs the two gravities' places must at least sit apart, so the case tells them apart

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	rig.handshake()

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local relay: number = rig.shared.rates.relay
	local live: number = rig.shared.step.gravity
	local Math: any = rig.globals.require(rig.tread.Step.Math)

	local ticks: { buffer } = {
		clip.keyframe({
			tick = K,
			gravity = RECORDED,
			characters = {
				{ slot = SLEEPER, generation = GENERATION, kind = "Sleeper", record = { position = SLEPT_AT } },
			},
		}),
	}

	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		local spec: { [string]: any } = { tick = tick, records = {} }

		if index == MOVE then
			spec.reveals = { { slot = SLEEPER, generation = GENERATION, kind = "Sleeper" } }
			spec.records = { { slot = SLEEPER, generation = GENERATION, position = DROPPED_AT } }
		end

		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { spec },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
			})
		)
	end

	local playback: any = handle:play(ticks)

	local count: number = #log.poses
	local drop: number = SLEPT_AT.y - DROPPED_AT.y
	local half: number = math.sqrt(2 * drop / RECORDED) / 2
	playback:render(MOVE / relay + half)

	local expected: vector = Math.fall(SLEPT_AT, DROPPED_AT, RECORDED, half)
	local underLive: vector = Math.fall(SLEPT_AT, DROPPED_AT, live, half)
	local sleeper: any = log.since(count)[SLEEPER]
	if vector.magnitude(expected - underLive) < APART then
		return false, `The two gravities put the sleeper within {APART} stud, so the case can't tell them apart`
	elseif sleeper == nil then
		return false, "The sleeper wasn't drawn"
	elseif vector.magnitude(sleeper.position - expected) > CLOSE then
		return false, `The sleeper was drawn at {sleeper.position}, not {expected} under the keyframe's {RECORDED}`
	end

	playback:destroy()

	return true, nil
end
