--[[
    With tiers.crowd left out, or given and then taken off by Relay.setCrowd
    before the first run, the banded crowd gives its own pinned digest in
    process and on 1, 2 and 4 stand-in workers, and no candidate is held out
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local WORKERS: { number } = { 1, 2, 4 }
local EXPECTED: string = Layouts.EXPECTED.bands -- The banded crowd's pinned digest, which no crowd cap ever made

type Result = Layouts.Result

-- Why a run of the banded crowd gave other than the pinned digest, or nil when it gave it with no one held out
local function judge(result: Result, what: string): string?
	if result.digest ~= EXPECTED then
		return `{what} digests to {result.digest}, not {EXPECTED}`
	elseif result.rest ~= 0 then
		return `{what} held {result.rest} candidates outside a crowd cap`
	end

	return nil
end

return function (): (boolean, string | nil)
	local why: string? = judge(Layouts.bands(), "The banded crowd with no cap")
		or judge(Layouts.crowd(nil, true), "The capped crowd with its cap lifted, in process,")
	if why then
		return false, why
	end

	for _, workers: number in WORKERS do
		local result: Result = Layouts.crowd(workers, true)
		why = judge(result, `The capped crowd with its cap lifted, on {workers} workers,`)
		if why then
			return false, why
		elseif result.worked ~= workers then
			return false, `The lifted crowd on {workers} workers had only {result.worked} of them run a round`
		end
	end

	return true, nil
end
