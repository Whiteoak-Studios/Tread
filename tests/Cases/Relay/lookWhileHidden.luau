--[[
    A character's look and held item go only when they change while the
    viewer is sent it, each part alone; a change while anti-ESP hides it
    waits, and its next reveal carries the latest of both
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local FIRST: { [string]: any } = { head = 4 }
local HIDDEN: { [string]: any } = { head = 5, leg = 6 }
local HELD: { [string]: any } = { item = 2, skin = 8 }
local QUIET: number = 10

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(30, 0, 0))

	Harness.Relay.setLook(slot, FIRST)
	harness:run()
	if Harness.find(client.seen.looks, slot).look ~= harness:pack("slot", FIRST) then
		return false, "The reveal came without the look"
	end

	for tick: number = 1, QUIET do
		harness.states[slot].position += vector.create(0, 0, 1)
		harness:run()

		if Harness.count(client.seen.looks, slot) ~= 0 then
			return false, `Tick {tick} sent a look entry for a look that never changed`
		end
	end

	harness.states[slot].held = table.clone(HELD)
	harness:run()
	local look: any = Harness.find(client.seen.looks, slot)
	if not look or look.held ~= harness:pack("held", HELD) or look.look ~= nil then
		return false, "A held item picked up while sent went with other than the held item alone"
	end

	harness:hide(client, slot, true)
	harness:run()
	if Harness.count(client.seen.hides, slot) ~= 1 then
		return false, "The culled character was not hidden"
	end

	Harness.Relay.setLook(slot, HIDDEN)
	harness.states[slot].held = {}
	for tick: number = 1, QUIET do
		harness:run()

		if Harness.count(client.seen.looks, slot) ~= 0 then
			return false, `Tick {tick} sent a look the viewer may not see, while anti-ESP hides the character`
		end
	end

	harness:hide(client, slot, false)
	harness:run()

	look = Harness.find(client.seen.looks, slot)
	if Harness.count(client.seen.reveals, slot) ~= 1 or not look then
		return false, "The character's reveal came without its look entry"
	elseif look.look ~= harness:pack("slot", HIDDEN) or look.held ~= "" then
		return false, "The reveal's look entry carried other than the look and held item changed while hidden"
	end

	return true, nil
end
