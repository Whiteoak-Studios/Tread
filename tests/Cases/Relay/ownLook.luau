--[[
    A viewer's own character is never revealed or sent a record, while its
    look entry comes when the character is made and on each change, held
    item included, repeated until acknowledged
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local LOOK: { [string]: any } = { torso = 21 }
local CHANGED: { [string]: any } = { torso = 22, face = 1 }
local HELD: { [string]: any } = { item = 30 }
local TICKS: number = 5

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local own: number = harness:spawn("Player", vector.zero)

	Harness.Relay.setLook(own, LOOK)
	client.viewer.slot = own
	client.lose = 1
	harness:run()

	if client.seen.lost ~= 1 then
		return false, "The viewer's new character sent it no look entry"
	end

	harness:run()
	local look: any = Harness.find(client.seen.looks, own)
	if not look or look.look ~= harness:pack("slot", LOOK) or look.held ~= "" then
		return false, "The lost look entry for the viewer's own character did not come again whole"
	end

	for tick: number = 1, TICKS do
		harness.states[own].position += vector.create(1, 0, 0)
		harness:run()

		local seen: any = client.seen
		if
			Harness.count(seen.reveals, own) + Harness.count(seen.records, own) + Harness.count(seen.looks, own) ~= 0
		then
			return false, `Tick {tick} sent the viewer its own character, whose look it had acknowledged`
		end
	end

	Harness.Relay.setLook(own, CHANGED)
	harness:run()
	look = Harness.find(client.seen.looks, own)
	if not look or look.look ~= harness:pack("slot", CHANGED) or look.held ~= nil then
		return false, "Changing the viewer's own look sent no entry with the new look alone"
	end

	harness.states[own].held = table.clone(HELD)
	harness:run()
	look = Harness.find(client.seen.looks, own)
	if not look or look.held ~= harness:pack("held", HELD) or look.look ~= nil then
		return false, "Changing the viewer's own held item sent no entry with the held item alone"
	end

	return true, nil
end
