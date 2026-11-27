--[[
    In process, the far rate under load lowers the farthest band's aim and
    floor by its scale from the run after its third over the budget in a row,
    holds them through an over among the unders, and gives them back from the
    run after its third under in a row, the nearer band untouched throughout
--]]

--!strict
local Environment = require("../../Environment")
local UnderLoad = require("../../Fixtures/Relay/UnderLoad")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"

-- Each target's records on the script's twelve runs: the near one's every run, the far one's every run but at half
-- its rate on the fourth to the ninth, its credit rising by a half a run from none there
local EXPECTED_NEAR: string = "111111111111"
local EXPECTED_FAR: string = "111010101111"
local LOWERED: number = 6 -- The fourth to the ninth

return function (): (boolean, string | nil)
	local ran: UnderLoad.Ran = UnderLoad.drive(Environment.load(HARNESS), nil, UnderLoad.two)
	if ran.near ~= EXPECTED_NEAR or ran.far ~= EXPECTED_FAR then
		return false,
			`The near target's records ran {ran.near} and the far one's {ran.far}, not {EXPECTED_NEAR} and {EXPECTED_FAR}`
	elseif ran.halved ~= LOWERED then
		return false, `The caps counted {ran.halved} runs with the farthest band lowered, not {LOWERED}`
	end

	return true, nil
end
