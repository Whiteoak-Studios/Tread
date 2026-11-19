--[[
    Every live run the panel lists is a scenario module the Runner finds,
    listed once, its name inside the run event's 32 bytes and its length a
    number of minutes above 0
--]]

--!strict
local fs = require("@lune/fs")

local Harness = require("../../Fixtures/DevClient/Harness")

local LIVE_RUNS: string = "dev/Shared/LiveRuns.luau"
local SCENARIOS: string = "dev/Server/Scenarios"
local NAME_BYTES: number = 32 -- The run event's name, string(1..32) in dev/Schemas/Dev.volt

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local runs: { any } = place.load(LIVE_RUNS).runs
	local seen: { [string]: boolean } = {}

	if #runs == 0 then
		return false, "The panel lists no live run"
	end

	for index: number, run: any in runs do
		local name: string = run.name
		if #name < 1 or #name > NAME_BYTES then
			return false, `Run {index}'s name {name} is {#name} B, outside the run event's 1 to {NAME_BYTES}`
		elseif seen[name] then
			return false, `{name} is listed twice`
		elseif not fs.isFile(`{SCENARIOS}/{name}.luau`) then
			return false, `{name} has no scenario module at {SCENARIOS}/{name}.luau`
		elseif type(run.minutes) ~= "number" or not (run.minutes > 0) then
			return false, `{name} runs for {run.minutes} minutes`
		end

		seen[name] = true
	end

	return true, nil
end
