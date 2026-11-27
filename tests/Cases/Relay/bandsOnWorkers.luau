--[[
    The banded crowd, three bands with some viewers zoomed and a moderator
    watching one, gives the digest it is pinned to in process and on 1, 2
    and 4 stand-in workers, with every worker running a round
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local WORKERS: { number } = { 1, 2, 4 }
local EXPECTED: string = Layouts.EXPECTED.bands -- The digest the crowd is pinned to

type Result = Layouts.Result

return function (): (boolean, string | nil)
	local serial: Result = Layouts.bands()

	-- It reaches what it is there for, so its digest pins it
	if serial.reveals == 0 or serial.hides == 0 or serial.changes == 0 then
		return false, "The banded crowd revealed or hid no one, or sent no change"
	elseif serial.withheld == 0 then
		return false, "The banded crowd sent its moderator no withheld block"
	elseif serial.digest ~= EXPECTED then
		return false, `The banded crowd digests to {serial.digest} in process, not {EXPECTED}`
	end

	for _, workers: number in WORKERS do
		local result: Result = Layouts.bands(workers)
		if result.digest ~= serial.digest then
			return false, `The banded crowd on {workers} workers digests to {result.digest}, not {serial.digest}`
		elseif result.worked ~= workers then
			return false, `The banded crowd on {workers} workers had only {result.worked} of them run a round`
		end
	end

	return true, nil
end
