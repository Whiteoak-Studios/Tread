--[[
    client:kick takes a slot table, a finite pitch and yaw and a finite
    duration above 0, and errors naming itself on anything else
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local SLOT: number = 3
local PITCH: number = 0.1
local YAW: number = 0.1
local DURATION: number = 0.2
local MEMBER: string = "client:kick"

-- One call the kick must refuse
type Refused = { name: string, slot: any, pitch: any, yaw: any, duration: any }

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local slot: { [string]: any } = { id = SLOT, kind = "Player", player = nil, withheld = false }

	-- A slot no rig is drawn for takes the kick and does nothing with it
	local took: boolean, failure: any = pcall(handle.kick, handle, slot, PITCH, YAW, DURATION)
	if not took then
		return false, `A kick of finite values threw: {failure}`
	end

	local refused: { Refused } = {
		{ name = "no slot", slot = nil, pitch = PITCH, yaw = YAW, duration = DURATION },
		{ name = "a slot number", slot = SLOT, pitch = PITCH, yaw = YAW, duration = DURATION },
		{ name = "a NaN pitch", slot = slot, pitch = 0 / 0, yaw = YAW, duration = DURATION },
		{ name = "an infinite pitch", slot = slot, pitch = math.huge, yaw = YAW, duration = DURATION },
		{ name = "a string pitch", slot = slot, pitch = "0.1", yaw = YAW, duration = DURATION },
		{ name = "a NaN yaw", slot = slot, pitch = PITCH, yaw = 0 / 0, duration = DURATION },
		{ name = "an infinite yaw", slot = slot, pitch = PITCH, yaw = -math.huge, duration = DURATION },
		{ name = "a duration of 0", slot = slot, pitch = PITCH, yaw = YAW, duration = 0 },
		{ name = "a negative duration", slot = slot, pitch = PITCH, yaw = YAW, duration = -DURATION },
		{ name = "an infinite duration", slot = slot, pitch = PITCH, yaw = YAW, duration = math.huge },
		{ name = "a NaN duration", slot = slot, pitch = PITCH, yaw = YAW, duration = 0 / 0 },
	}

	for _, call: Refused in refused do
		local ran: boolean, message: any = pcall(handle.kick, handle, call.slot, call.pitch, call.yaw, call.duration)
		if ran then
			return false, `A kick with {call.name} was taken`
		elseif not tostring(message):find(MEMBER, 1, true) then
			return false, `A kick with {call.name} threw without naming {MEMBER}: {message}`
		end
	end

	return true, nil
end
