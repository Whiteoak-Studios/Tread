--[[
    An acknowledgment that comes back several ticks late still clears what
    the block it names carried: a reveal, a hide and a look entry each ride
    until it arrives and not a tick past it
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local LAG: number = 3 -- Relay ticks an acknowledgment takes to come back, 150 ms at the example's 20 Hz
local LIMIT: number = 20 -- Ticks after which an entry still riding never stops
local AWAY: vector = vector.create(1500, 0, 0)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	client.lag = LAG

	-- The ticks an entry kind rides for the slot, running until it stops
	local function rides(list: string, slot: number): number
		local count: number = 0

		for _ = 1, LIMIT do
			harness:run()

			if Harness.count(client.seen[list], slot) == 0 then
				return count
			end

			count += 1
		end

		return count
	end

	local slot: number = harness:spawn("Player", vector.create(50, 0, 0))
	local count: number = rides("reveals", slot)
	if count ~= LAG + 1 then
		return false, `The reveal rode {count} ticks, where its acknowledgment comes back after {LAG + 1}`
	end

	harness:runs(LAG)
	client.viewer.position = AWAY
	count = rides("hides", slot)
	if count ~= LAG + 1 then
		return false, `The hide rode {count} ticks, where its acknowledgment comes back after {LAG + 1}`
	end

	client.viewer.position = vector.zero
	harness:runs(LAG + 2)
	Harness.Relay.setLook(slot, { head = 3 })
	count = rides("looks", slot)
	if count ~= LAG + 1 then
		return false, `The look entry rode {count} ticks, where its acknowledgment comes back after {LAG + 1}`
	end

	return true, nil
end
