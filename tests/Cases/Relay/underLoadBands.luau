--[[
    While the far rate under load holds the farthest band lowered, which its
    far target's records show, Relay.bands still gives the bands as given
--]]

--!strict
local Environment = require("../../Environment")
local UnderLoad = require("../../Fixtures/Relay/UnderLoad")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local EXPECTED: string = "20/15,20/20" -- UnderLoad.two's bands, as given
local EXPECTED_FAR: string = "111010101111" -- As underLoadHalves pins it, lowered on the run the bands are read

return function (): (boolean, string | nil)
	local ran: UnderLoad.Ran = UnderLoad.drive(Environment.load(HARNESS), nil, UnderLoad.two)
	if ran.far ~= EXPECTED_FAR then
		return false, `The far target's records ran {ran.far}, not {EXPECTED_FAR}, so no band was lowered when read`
	elseif ran.bands ~= EXPECTED then
		return false, `Relay.bands gave {ran.bands} while the farthest band was lowered, not {EXPECTED} as given`
	end

	return true, nil
end
