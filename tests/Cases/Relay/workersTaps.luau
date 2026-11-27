--[[
    The tapped fight with its turns on 1, 2 and 3 stand-in workers gives the
    digest it is pinned to in process, with every worker running a round
    and, from 2 workers on, its moderator on another worker than its target
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local MOST_WORKERS: number = 3
local APART: number = 2 -- The workers one round sends a watcher to once its home isn't its target's

return function (): (boolean, string | nil)
	for workers: number = 1, MOST_WORKERS do
		local result: Layouts.Result = Layouts.taps(workers)
		if result.digest ~= Layouts.EXPECTED.taps then
			return false, `The taps layout on {workers} workers digests to {result.digest}, not {Layouts.EXPECTED.taps}`
		elseif result.worked ~= workers then
			return false, `The taps layout on {workers} workers had only {result.worked} of them run a round`
		elseif workers >= APART and result.split < APART then
			return false, `The taps layout on {workers} workers kept its moderator on its target's worker`
		end
	end

	return true, nil
end
