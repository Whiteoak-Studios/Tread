--[[
    With one band there is none farther to lower: through the far rate under
    load's whole script both targets keep the band's rate and no run counts
    as lowered
--]]

--!strict
local Environment = require("../../Environment")
local UnderLoad = require("../../Fixtures/Relay/UnderLoad")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local EXPECTED: string = "111111111111" -- Each target's records on the script's twelve runs, one every run

return function (): (boolean, string | nil)
	local ran: UnderLoad.Ran = UnderLoad.drive(Environment.load(HARNESS), nil, UnderLoad.one)
	if ran.near ~= EXPECTED or ran.far ~= EXPECTED then
		return false, `With one band the targets' records ran {ran.near} and {ran.far}, not {EXPECTED} each`
	elseif ran.halved ~= 0 then
		return false, `With one band the caps counted {ran.halved} runs with a band lowered`
	end

	return true, nil
end
