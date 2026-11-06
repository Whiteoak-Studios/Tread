--[[
    Relay.reveal gives a fresh reveal, with its record and look, to every
    viewer currently sent the slot and to no other, and viewersOf and
    isSent name exactly the viewers sent it
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local MOVED: vector = vector.create(20, -3, 4) -- Where a sleeper's move puts it

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local Relay: any = Harness.Relay
	local harness: any = Harness.new()

	local sent: any = harness:viewer("Sent")
	local alsoSent: any = harness:viewer("AlsoSent")
	local away: any = harness:viewer("Away")
	local culled: any = harness:viewer("Culled")
	away.viewer.position = vector.create(3000, 0, 0)

	local slot: number = harness:spawn("Sleeper", vector.create(10, 0, 0))
	local alone: number = harness:spawn("Sleeper", vector.create(2000, 0, 2000)) -- Inside nobody's sleeper radius
	harness:hide(culled, slot, true)
	harness:runs(2)

	local viewers: { any } = Relay.viewersOf(slot)
	if #viewers ~= 2 or not table.find(viewers, sent.viewer.key) or not table.find(viewers, alsoSent.viewer.key) then
		return false, `viewersOf named {#viewers} viewers, not the two the sleeper is sent to`
	end

	for _, client: any in { away, culled } do
		if Relay.isSent(client.viewer.key, slot) then
			return false, `isSent counted {client.viewer.key.Name} as sent the sleeper`
		end
	end

	-- Sleepers never change, so nothing goes for it until the move's fresh reveal
	harness.states[slot].position = MOVED
	harness:run()
	if #sent.seen.records ~= 0 then
		return false, "A sleeper that moved was sent a record with no reveal"
	end

	Relay.reveal(slot)
	Relay.reveal(alone)
	harness:run()

	for _, client: any in { sent, alsoSent } do
		local seen: any = client.seen
		local record: any = Harness.find(seen.records, slot)

		if Harness.count(seen.reveals, slot) ~= 1 or Harness.find(seen.reveals, slot).kind ~= "Sleeper" then
			return false, `{client.viewer.key.Name} got no fresh sleeper reveal`
		elseif not record or vector.magnitude(record.position - MOVED) > QUANTUM then
			return false, `{client.viewer.key.Name}'s fresh reveal did not carry the sleeper's new place`
		elseif Harness.count(seen.looks, slot) ~= 1 then
			return false, `{client.viewer.key.Name}'s fresh reveal came without its look entry`
		end
	end

	for _, client: any in { away, culled } do
		if #client.seen.sizes ~= 0 then
			return false, `{client.viewer.key.Name}, not sent the sleeper, got a block from its reveal`
		end
	end

	for _, client: any in { sent, alsoSent, away, culled } do
		if Harness.count(client.seen.reveals, alone) ~= 0 then
			return false, "Revealing a sleeper nobody is sent reached a viewer"
		end
	end

	return true, nil
end
