--[[
    A command sampled in a frame reads that frame's render time through
    getRenderTime, and the Move it goes in reports that frame's delay, so a
    shot's claim and its command's delay come from the same frame
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local GENERATION: number = 1
local TICK: number = 50 -- The first block's relay tick
local WAITED: number = 2 -- Frames before the next block, which comes a tick late and lifts the delay off its floor
local FRAMES: number = 6 -- Frames checked while the delay eases back down and the render time runs on
local MILLISECONDS: number = 1000

return function (): (boolean, string | nil)
	local rig: any = Handle.new({ start = false })
	local given: (command: any) -> () = rig.client.sample

	-- What the game's sample read of the render time in the frame being run
	local claims: { number } = {}
	rig.client.sample = function (command: any)
		given(command)
		table.insert(claims, rig.handle:getRenderTime())
	end

	rig.start()
	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))

	rig.relay({ tick = TICK })
	rig.frames(WAITED)
	rig.relay({ tick = TICK + 1 })

	-- The case has power only while the delay eases within each frame, so a Move sampled before the ease differs
	local floor: number = rig.client.interpolation.delay
	if not (rig.Interpolate.delay() > floor) then
		return false, `The late block left the delay at {rig.Interpolate.delay()} s, not above its floor of {floor} s`
	end

	local sampled: number = 0
	local reported: number = 0
	local previous: number = rig.handle:getRenderTime()

	for frame: number = 1, FRAMES do
		table.clear(claims)
		local sent: number = #rig.moves
		local eased: number = math.round(rig.Interpolate.delay() * MILLISECONDS)

		rig.frames(1)
		rig.step()

		-- Each frame moves both, so a sample or a Move read before the render clock's step reads the frame before
		local renderTime: number = rig.handle:getRenderTime()
		local delay: number = math.round(rig.Interpolate.delay() * MILLISECONDS)
		if renderTime == previous or delay == eased then
			return false, `Frame {frame} left the render time at {renderTime} or the delay at {delay} ms`
		end
		previous = renderTime

		for index: number = sent + 1, #rig.moves do
			local move: any = rig.moves[index]
			if move.delay ~= delay then
				return false, `Frame {frame}'s Move reported a delay of {move.delay} ms, not the frame's own {delay} ms`
			end
		end

		for _, claim: number in claims do
			if claim ~= renderTime then
				return false, `Frame {frame}'s sample read render time {claim}, not the frame's own {renderTime}`
			end
		end

		sampled += #claims
		reported += #rig.moves - sent
	end

	if sampled < FRAMES or reported < FRAMES then
		return false, `{FRAMES} frames sampled {sampled} commands and sent {reported} Moves, not one of each a frame`
	end

	return true, nil
end
