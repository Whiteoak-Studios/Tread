--[[
    AntiEsp.leave forgets a viewer and every pair it held, so none is tested
    again and a later ask starts afresh, while another viewer's pairs keep
    theirs; a key never asked about leaves nothing to forget
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local _, leaving: any = harness:player("Leaving", vector.zero)
	local _, staying: any = harness:player("Staying", vector.create(20, 0, 0))
	local target: number = harness:body("Player", vector.create(0, 0, -50))

	AntiEsp.isHidden(leaving, target)
	AntiEsp.isHidden(staying, target)
	harness:slice(0)

	AntiEsp.leave(leaving.key)
	AntiEsp.leave({ Name = "Stranger" })

	-- Past both pairs' 2 Hz recheck: only the staying viewer's is tested
	AntiEsp.isHidden(staying, target)
	harness:slice(1)

	if #harness.rays ~= 1 or harness.rays[1].origin.x ~= 20 then
		return false, `The slice after the leave cast {#harness.rays} rays, not the staying viewer's one open ray`
	elseif AntiEsp.isHidden(staying, target) then
		return false, "The staying viewer's pair lost its visible verdict"
	end

	-- A viewer that comes back under the same key starts afresh
	if not AntiEsp.isHidden(leaving, target) then
		return false, "The viewer that left came back with its old visible verdict"
	end

	return true, nil
end
