--[[
    A clip draws a character from the samples that had arrived by the clip
    tick, at the render time the target's view lag puts it at: nothing
    before its first record, the keyframe's alone until the next arrives,
    and between the two once it has
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 200 -- The keyframe's relay tick
local FRAMES: number = 5 -- Frames at K to K + 4
local WALKER: number = 5
local TARGET: number = 9
local GENERATION: number = 1
local LAG: number = 50 -- Milliseconds, one relay tick at 20 Hz
local FAR: vector = vector.create(4, 0, 0) -- Where the walker's record at K + 2 puts it
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	rig.handshake()

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local relay: number = rig.shared.rates.relay

	local ticks: { buffer } = {
		clip.keyframe({
			tick = K,
			characters = { { slot = WALKER, generation = GENERATION, kind = "Player", record = {} } },
		}),
	}

	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		local records: { any } = {}
		if index == 2 then
			records = { { slot = WALKER, generation = GENERATION, position = FAR } }
		end

		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { { tick = tick, records = records } },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = LAG },
			})
		)
	end

	local playback: any = handle:play(ticks)

	-- The walker's x at a clip time, nil when it wasn't drawn
	local function walkerAt(time: number): number?
		local count: number = #log.poses
		playback:render(time)

		local drawn: any = log.since(count)[WALKER]
		return drawn and drawn.position.x
	end

	-- 1) At the keyframe the render time a tick behind it comes before the walker's first record
	local early: number? = walkerAt(0)
	if early ~= nil then
		return false, `The walker was drawn at x = {early} before the render time reached its first record`
	end

	-- 2) A tick and a tick and a half on, only the keyframe's record had arrived, and it is drawn as it is
	for _, time: number in { 1 / relay, 1.5 / relay } do
		local x: number? = walkerAt(time)
		if x == nil then
			return false, `The walker wasn't drawn at {time} s, though its keyframe record had arrived`
		elseif math.abs(x) > CLOSE then
			return false, `The walker was drawn at x = {x} at {time} s, not its keyframe record's 0`
		end
	end

	-- 3) Two ticks on, both records had arrived, and the render time a tick behind draws it between them
	local between: number? = walkerAt(2 / relay)
	if between == nil or math.abs(between - FAR.x / 2) > CLOSE then
		return false, `The walker was drawn at x = {between} two ticks on, not halfway at {FAR.x / 2}`
	end

	playback:destroy()

	return true, nil
end
