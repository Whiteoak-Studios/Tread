--[[
    The handle's frame ends with the pool's frame end, once a frame and
    after its last pose, so every rig the frame posed moves before it draws
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local OTHER: number = 3
local GENERATION: number = 2
local TICK: number = 50
local SETTLE: number = 10 -- Frames until the render time reaches the record, past the interpolation delay
local FRAMES: number = 3 -- Frames run once the rig is posed

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local pool: any = rig.pool
	local rigs: any = rig.handle._rigs

	-- The stand-in's frame end writes nothing down, so the case writes each one down beside the pool's calls
	rigs.frame = function (_: any)
		table.insert(pool.calls, { member = "frame" })
	end

	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	rig.handshake()
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A", player = other } })
	rig.relay({
		tick = TICK,
		reveals = { { slot = OTHER, generation = GENERATION, kind = "Player" } },
		records = {
			{ slot = OTHER, generation = GENERATION, position = vector.create(100, 5, 200), word = rig.word({}) },
		},
	})
	rig.frames(SETTLE)

	if #pool.of("pose") == 0 then
		return false, `{SETTLE} frames never posed slot {OTHER}`
	end

	-- Each frame's calls end with the frame end, its only one, after the frame's pose of the rig
	for frame: number = 1, FRAMES do
		table.clear(pool.calls)
		rig.frames(1)

		local calls: { any } = pool.calls
		local ends: number = #pool.of("frame")
		local posed: { any } = pool.of("pose")
		if ends ~= 1 or calls[#calls].member ~= "frame" then
			return false,
				`Frame {frame} made {ends} frame ends, its last call a {calls[#calls] and calls[#calls].member}`
		elseif #posed == 0 or posed[#posed].slot ~= OTHER then
			return false, `Frame {frame} never posed slot {OTHER} before its frame end`
		end
	end

	return true, nil
end
