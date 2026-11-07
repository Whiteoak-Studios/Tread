--[[
    Replication case 5, over Volt.mock: a viewer that joins after the
    characters around it have moved, rested and dressed gets each one's
    reveal with its kind, its current place and its look
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local BEFORE: number = 10 -- Ticks run before the viewer joins
local STRIDE: vector = vector.create(0.5, 0, 0)
local LOOK: { [string]: any } = { head = 7, shirt = 300 }
local HELD: { [string]: any } = { item = 12, skin = 4 }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(true)

	local moving: number = harness:spawn("Player", vector.create(50, 0, 0))
	local resting: number = harness:spawn("Player", vector.create(-300, 0, 20))
	local npc: number = harness:spawn("Npc", vector.create(0, 0, 150))
	Harness.Relay.setLook(moving, LOOK)
	harness.states[moving].held = table.clone(HELD)

	for tick: number = 1, BEFORE do
		harness.states[moving].position = vector.create(50, 0, 0) + STRIDE * tick
		harness:run()
	end

	local client: any = harness:viewer("Late")
	harness:run()

	local seen: any = client.seen
	local expected: { [number]: { kind: string, at: vector } } = {
		[moving] = { kind = "Player", at = harness.states[moving].position },
		[resting] = { kind = "Player", at = harness.states[resting].position },
		[npc] = { kind = "Npc", at = harness.states[npc].position },
	}

	for slot: number, want: { kind: string, at: vector } in expected do
		local reveal: any = Harness.find(seen.reveals, slot)
		local record: any = Harness.find(seen.records, slot)

		if not reveal or reveal.kind ~= want.kind then
			return false, `The late viewer got no {want.kind} reveal for slot {slot}`
		elseif not record or vector.magnitude(record.position - want.at) > QUANTUM then
			return false, `The late viewer's record put slot {slot} away from its current place {want.at}`
		end
	end

	local look: any = Harness.find(seen.looks, moving)
	if not look or look.look ~= harness:pack("slot", LOOK) or look.held ~= harness:pack("held", HELD) then
		return false, "The dressed character's reveal came without its look and held item"
	end

	local bare: any = Harness.find(seen.looks, resting)
	if not bare or bare.look ~= nil or bare.held ~= "" then
		return false, "A character with no look set was revealed with other than an empty held item"
	end

	return true, nil
end
