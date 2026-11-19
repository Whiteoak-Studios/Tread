--[[
    The idle layout with its turns on 1, 2 and 3 stand-in workers gives the
    digest it is pinned to in process, with every worker running a round
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local MOST_WORKERS: number = 3 -- Three over 40 viewers splits them unevenly

return function (): (boolean, string | nil)
	for workers: number = 1, MOST_WORKERS do
		local result: Layouts.Result = Layouts.idle(workers)
		if result.digest ~= Layouts.EXPECTED.idle then
			return false, `The idle layout on {workers} workers digests to {result.digest}, not {Layouts.EXPECTED.idle}`
		elseif result.worked ~= workers then
			return false, `The idle layout on {workers} workers had only {result.worked} of them run a round`
		end
	end

	return true, nil
end
