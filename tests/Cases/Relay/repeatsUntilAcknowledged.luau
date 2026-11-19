--[[
    A reveal, a hide and a look entry each ride a block every relay tick
    until the viewer acknowledges one that carried it, whatever is lost on
    the way, and a look changed while pending carries only its latest
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local PLACE: vector = vector.create(100, 0, 0)
local AWAY: vector = vector.create(1500, 0, 0)
local FIRST: { [string]: any } = { head = 1 }
local SECOND: { [string]: any } = { head = 2 }
local LATEST: { [string]: any } = { head = 3, pants = 9 }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", PLACE)

	-- The reveal's first two blocks are lost, so it rides a third, and once that is acknowledged no more
	client.lose = 2
	for tick: number = 1, 2 do
		harness:run()
		if client.seen.lost ~= 1 then
			return false, `Tick {tick} sent the pending reveal in no block`
		end
	end

	harness:run()
	if Harness.count(client.seen.reveals, slot) ~= 1 then
		return false, "The reveal stopped riding before the viewer acknowledged a block that carried it"
	end

	harness:run()
	if Harness.count(client.seen.reveals, slot) ~= 0 then
		return false, "The reveal rode on after the viewer acknowledged it"
	end

	-- The hide's first block is lost; the viewer stops being sent the character all the same
	client.viewer.position = AWAY
	client.lose = 1
	harness:run()
	if client.seen.lost ~= 1 then
		return false, "Leaving range sent no block with the hide"
	elseif Harness.Relay.isSent(client.viewer.key, slot) then
		return false, "The viewer was still counted as sent the character after its hide first rode a block"
	end

	harness:run()
	if Harness.count(client.seen.hides, slot) ~= 1 or client.drawn[slot] ~= nil then
		return false, "The hide stopped riding before the viewer acknowledged it"
	end

	harness:run()
	if #client.seen.sizes ~= 0 then
		return false, "The hide rode on after the viewer acknowledged it"
	end

	-- Back in range, a look change rides until acknowledged, and changes made while it is pending merge into it
	client.viewer.position = vector.zero
	harness:runs(2)

	Harness.Relay.setLook(slot, FIRST)
	client.lose = 1
	harness:run()

	Harness.Relay.setLook(slot, SECOND)
	Harness.Relay.setLook(slot, LATEST)
	client.lose = 1
	harness:run()

	harness:run()
	local look: any = Harness.find(client.seen.looks, slot)
	if not look or look.look ~= harness:pack("slot", LATEST) then
		return false, "The pending look entry did not carry the latest look once read"
	elseif look.held ~= nil then
		return false, "The look entry carried a held item that never changed"
	end

	harness:run()
	if Harness.count(client.seen.looks, slot) ~= 0 then
		return false, "The look entry rode on after the viewer acknowledged it"
	end

	return true, nil
end
