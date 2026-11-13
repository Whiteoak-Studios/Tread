--[[
    Promise 4.0.0 loads through the environment beside Tread, and its timers
    settle on the fake game's RunService.Heartbeat
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local DELAY: number = 0.05 -- Seconds, a few of the fake Heartbeat's frames
local VALUE: string = "resolved"
local REASON: string = "rejected"

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local Promise: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Promise)

	local resolved: boolean, value: any = Promise.resolve(VALUE):await()
	if not resolved or value ~= VALUE then
		return false, `Promise.resolve awaited to {resolved}, {value}`
	end

	local rejected: boolean, reason: any = Promise.reject(REASON):await()
	if rejected or reason ~= REASON then
		return false, `Promise.reject awaited to {rejected}, {reason}`
	end

	-- Promise.delay counts its time on Heartbeat's frames, so it settles only if the fake one fires
	local delayed: boolean, elapsed: any = Promise.delay(DELAY):await()
	if not delayed or type(elapsed) ~= "number" or elapsed < DELAY then
		return false, `Promise.delay({DELAY}) awaited to {delayed}, {elapsed}`
	end

	return true, nil
end
