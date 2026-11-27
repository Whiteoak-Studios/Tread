--[[
    The capped crowd, the banded crowd under a crowd cap of 8, gives the
    digest it is pinned to in process and on 1, 2 and 4 stand-in workers,
    with the same candidates held outside the cap and every worker running
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local WORKERS: { number } = { 1, 2, 4 }
local EXPECTED: string = Layouts.EXPECTED.crowd -- The digest the capped crowd is pinned to

type Result = Layouts.Result

return function (): (boolean, string | nil)
	local serial: Result = Layouts.crowd()

	-- The cap holds some out, so its digest pins what it changes
	if serial.rest == 0 then
		return false, "The capped crowd held no candidate outside a viewer's cap"
	elseif serial.withheld == 0 or serial.changes == 0 then
		return false, "The capped crowd sent its moderator no withheld block, or sent no change"
	elseif serial.digest ~= EXPECTED then
		return false, `The capped crowd digests to {serial.digest} in process, not {EXPECTED}`
	end

	for _, workers: number in WORKERS do
		local result: Result = Layouts.crowd(workers)
		if result.digest ~= serial.digest then
			return false, `The capped crowd on {workers} workers digests to {result.digest}, not {serial.digest}`
		elseif result.rest ~= serial.rest then
			return false, `The capped crowd on {workers} workers held {result.rest} outside, not {serial.rest}`
		elseif result.worked ~= workers then
			return false, `The capped crowd on {workers} workers had only {result.worked} of them run a round`
		end
	end

	return true, nil
end
