--[[
    A sleeper's or body's pair no slice has time to test waits hidden and
    never fails open, however long it waits, and is tested once a slice has
    the time
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local KINDS: { string } = { "Sleeper", "Body" }
local WAITS: { number } = { 0.1, 0.5, 2, 30 } -- Seconds starved, each past the players' fail-open time

return function (): (boolean, string | nil)
	for _, kind: string in KINDS do
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new()

		local _, viewer: any = harness:player("Viewer", vector.zero)
		local lying: number = harness:body(kind, vector.create(0, 0, -50))

		harness:slice(0, 0)
		Harness.AntiEsp.isHidden(viewer, lying)

		for _, now: number in WAITS do
			harness:slice(now, 0)

			if not Harness.AntiEsp.isHidden(viewer, lying) then
				return false, `The {kind} pair failed open after {now} s untested`
			end
		end

		local _, _, failOpens: number = Harness.AntiEsp.counts()
		if failOpens ~= 0 then
			return false, `The {kind} pair counted {failOpens} fail-opens`
		end

		harness:slice(WAITS[#WAITS])
		if #harness.rays == 0 then
			return false, `The waiting {kind} pair was not tested once a slice had time`
		elseif Harness.AntiEsp.isHidden(viewer, lying) then
			return false, `The {kind} pair with its rays open stayed hidden`
		end
	end

	return true, nil
end
