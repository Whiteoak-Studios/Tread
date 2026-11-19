--[[
    The server refuses a live run while another is going first, then for a
    name the list doesn't have, each in its own words, and refuses nothing
    asked for by a listed name while idle
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local LIVE_RUNS: string = "dev/Shared/LiveRuns.luau"
local UNLISTED: string = "NoSuchRun"

-- One ask and the refusal it gets, nil for none
type Ask = { running: string?, name: string, refusal: string? }

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local LiveRuns: any = place.load(LIVE_RUNS)
	local listed: string = LiveRuns.runs[1].name
	local going: string = LiveRuns.runs[2].name

	local asks: { Ask } = {
		-- A run already going comes first, even for a name not listed
		{ running = going, name = UNLISTED, refusal = `{going} is still running` },
		{ running = going, name = listed, refusal = `{going} is still running` },

		-- Then a name not listed
		{ running = nil, name = UNLISTED, refusal = `no live run is named {UNLISTED}` },

		-- Idle and a listed name
		{ running = nil, name = listed, refusal = nil },
	}

	for _, ask: Ask in asks do
		local refusal: string? = LiveRuns.refusal(ask.running, ask.name)
		if refusal ~= ask.refusal then
			return false,
				`Asking for {ask.name} with {ask.running} running was refused with {refusal}, not {ask.refusal}`
		end
	end

	return true, nil
end
