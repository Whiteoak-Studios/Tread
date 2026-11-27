--[[
    Each playback render ends with the pool's frame end, once and after its
    last pose, so a render a game draws on PreRender moves its rigs in the
    frame it draws
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 800
local FRAMES: number = 12
local DRAWN: number = 13
local TARGET: number = 9
local GENERATION: number = 1
local TIMES: { number } = { 2, 6, 9 } -- Relay ticks after the keyframe each render draws

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	rig.handshake()

	-- The stand-in's frame end writes nothing down, so the case writes each one down beside the pool's calls
	handle._rigs.frame = function (_: any)
		table.insert(pool.calls, { member = "frame" })
	end

	local clip: any = Clip.new(rig)
	Clip.log(rig)
	local relay: number = rig.shared.rates.relay

	local record: { [string]: any } = { slot = DRAWN, generation = GENERATION, position = vector.zero }
	local ticks: { buffer } = {
		clip.keyframe({
			tick = K,
			characters = { { slot = DRAWN, generation = GENERATION, kind = "Player", record = {} } },
		}),
	}

	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { { tick = tick, records = { record } } },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
			})
		)
	end

	local playback: any = handle:play(ticks)

	for _, time: number in TIMES do
		table.clear(pool.calls)
		playback:render(time / relay)

		local calls: { any } = pool.calls
		local ends: number = #pool.of("frame")
		local posed: { any } = pool.of("pose")
		if ends ~= 1 or calls[#calls].member ~= "frame" then
			return false, `A render at {time} relay ticks made {ends} frame ends, not one as its last call`
		elseif #posed == 0 then
			return false, `A render at {time} relay ticks posed no rig before its frame end`
		end
	end

	playback:destroy()

	return true, nil
end
