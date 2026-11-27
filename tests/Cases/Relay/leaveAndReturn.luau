--[[
    Replication case 4, over Volt.mock: a viewer that leaves a character's
    range keeps it to 1,000 studs, is sent a hide past that, gets nothing
    back until it is within 950 again, and then a fresh reveal
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local TARGET: vector = vector.create(0, 0, 0)

-- Where the viewer stands on each tick, and whether it is sent the character there
local STEPS: { { x: number, sent: boolean } } = {
	{ x = 500, sent = true },
	{ x = 980, sent = true }, -- Inside 1,000, where relevancy is left
	{ x = 1001, sent = false },
	{ x = 970, sent = false }, -- Outside 950, where it is entered
	{ x = 940, sent = true },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(true)
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", TARGET)

	for index: number, step: { x: number, sent: boolean } in STEPS do
		local wasSent: boolean = client.drawn[slot] ~= nil

		-- The character moves a little each tick, so a record is due whenever it is sent
		harness.states[slot].position = vector.create(0, 0, index)
		client.viewer.position = vector.create(step.x, 0, 0)
		harness:run()

		local seen: any = client.seen
		local sent: boolean = Harness.Relay.isSent(client.viewer.key, slot)
		if sent ~= step.sent or (client.drawn[slot] ~= nil) ~= step.sent then
			return false, `At {step.x} studs the viewer was sent the character: {sent}, where it should be {step.sent}`
		end

		if wasSent and not step.sent and Harness.count(seen.hides, slot) ~= 1 then
			return false, `Leaving to {step.x} studs gave no hide`
		elseif not wasSent and step.sent then
			local record: any = Harness.find(seen.records, slot)
			if
				Harness.count(seen.reveals, slot) ~= 1
				or not record
				or math.abs(record.position.z - index) > QUANTUM
			then
				return false, `Coming back to {step.x} studs gave no fresh reveal at the character's place`
			end
		elseif not step.sent and #seen.records + #seen.reveals ~= 0 then
			return false, `The viewer out of range at {step.x} studs was sent the character`
		end
	end

	return true, nil
end
