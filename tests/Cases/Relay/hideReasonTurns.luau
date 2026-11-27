--[[
    A pending hide anti-ESP made carries each run's own reason: its copies
    read culled true until its character turns Invisible and false from that
    run on, while the viewer's acknowledgment is still on its way
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local LAG: number = 3 -- Relay ticks an acknowledgment takes to come back, so a hide rides LAG + 1 of them
local CULLED: number = 2 -- The hide's copies before its character turns Invisible
local PLACE: vector = vector.create(100, 0, 0)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", PLACE)
	client.lag = LAG

	-- Long enough for the reveal's acknowledgment to come back, so the hide alone is pending
	harness:runs(LAG + 2)
	if client.drawn[slot] == nil then
		return false, "The character in range was never revealed"
	end

	harness:hide(client, slot, true)

	for copy: number = 1, LAG + 1 do
		if copy == CULLED + 1 then
			Harness.Relay.setInvisible(slot, true)
		end

		harness:run()

		local expected: boolean = copy <= CULLED
		local hide: any = Harness.find(client.seen.hides, slot)
		if not hide then
			return false, `The hide's copy {copy} never rode, its acknowledgment still on its way`
		elseif hide.culled ~= expected then
			return false, `The hide's copy {copy} read culled {hide.culled}, not {expected}`
		end
	end

	return true, nil
end
