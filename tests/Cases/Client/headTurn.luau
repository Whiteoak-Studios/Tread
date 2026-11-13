--[[
    A remote record's head offset reaches the pool through the handle's own
    frame: each frame turns that rig's head by the offset, in radians held
    to the head cone, just before it poses the rig
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local OTHER: number = 3
local GENERATION: number = 2
local TICK: number = 50
local SETTLE: number = 10 -- Frames until the render time reaches the record, past the interpolation delay
local YAW_LEVELS: number = 3 -- The record's head offset, in the signed 4-bit levels it carries
local PITCH_LEVELS: number = -2
local CLOSE: number = 1e-12

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local pool: any = rig.pool
	local cone: number = rig.shared.step.headCone
	local step: number = cone / rig.Constants.HEAD_LEVELS -- Degrees a level stands for

	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	rig.handshake()
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A", player = other } })
	rig.relay({
		tick = TICK,
		reveals = { { slot = OTHER, generation = GENERATION, kind = "Player" } },
		records = {
			{
				slot = OTHER,
				generation = GENERATION,
				position = vector.create(100, 5, 200),
				word = rig.word({}),
				headYaw = YAW_LEVELS * step,
				headPitch = PITCH_LEVELS * step,
			},
		},
	})
	rig.frames(SETTLE)

	-- The last pose of the rig, and the call the frame made just before it
	local calls: { any } = pool.calls
	local posed: number? = nil
	for index: number = #calls, 1, -1 do
		if calls[index].member == "pose" and calls[index].slot == OTHER then
			posed = index
			break
		end
	end

	if posed == nil then
		return false, `{SETTLE} frames never posed slot {OTHER}`
	end

	local turned: any = calls[posed - 1]
	local headYaw: number = math.rad(YAW_LEVELS * step)
	local headPitch: number = math.rad(PITCH_LEVELS * step)
	if turned == nil or turned.member ~= "turn" or turned.slot ~= OTHER then
		return false, `The frame posed slot {OTHER} with no turn of its head just before`
	elseif math.abs(turned.headYaw - headYaw) > CLOSE or math.abs(turned.headPitch - headPitch) > CLOSE then
		local got: string = `{turned.headYaw} and {turned.headPitch}`
		return false, `The frame turned the head by {got} radians, not the record's {headYaw} and {headPitch}`
	end

	return true, nil
end
