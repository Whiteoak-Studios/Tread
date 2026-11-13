--[[
    Every character but the target is drawn at the target's drawn tick in
    relay time less the view lag its frames carry: with 100 ms of lag at
    20 Hz, ten ticks on a walker moving a stud a tick stands at its record
    from two ticks before
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 300
local FRAMES: number = 12
local WALKER: number = 6
local TARGET: number = 9
local GENERATION: number = 1
local LAG: number = 100 -- Milliseconds, two relay ticks at 20 Hz
local AHEAD: number = 10 -- Ticks on from the keyframe the walker is drawn at
local LAG_TICKS: number = 2
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	rig.handshake()

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local relay: number = rig.shared.rates.relay

	-- The walker's record a tick: a stud along X for each tick since the keyframe
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
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = LAG },
			})
		)
	end

	local playback: any = handle:play(ticks)
	playback:render(AHEAD / relay)

	local drawn: any = log.since(0)[WALKER]
	local expected: number = AHEAD - LAG_TICKS
	if drawn == nil then
		return false, `The walker wasn't drawn {AHEAD} ticks on`
	elseif math.abs(drawn.position.x - expected) > CLOSE then
		return false,
			`The walker was drawn at x = {drawn.position.x}, not its record from {LAG_TICKS} ticks before at {expected}`
	end

	playback:destroy()

	return true, nil
end
