--[[
    A hide anti-ESP did not make reads culled false, even while anti-ESP
    would hide the pair too: a relevancy exit, a lowered render distance,
    Invisible, a despawn and an NPC past its range
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local PLACE: vector = vector.create(100, 0, 0)
local AWAY: vector = vector.create(1500, 0, 0) -- Past the example's relevancy.leave of 1,000
local SHORT: number = 50 -- A render distance the body at PLACE stands past
local PAST: vector = vector.create(900, 0, 0) -- Past the example's npcs.range of 800, inside relevancy.leave

-- One way a viewer stops being sent a body of a kind, other than anti-ESP's
type Row = {
	name: string,
	kind: string,
	stop: (Harness: any, harness: any, client: any, slot: number) -> (),
}

local ROWS: { Row } = {
	{
		name = "A relevancy exit",
		kind = "Player",
		stop = function (_: any, harness: any, _: any, slot: number)
			harness.states[slot].position = AWAY
		end,
	},

	{
		name = "A lowered render distance",
		kind = "Player",
		stop = function (Harness: any, _: any, client: any, _: number)
			Harness.Relay.setDistance(client.viewer.key, SHORT)
		end,
	},

	{
		name = "Invisible",
		kind = "Player",
		stop = function (Harness: any, _: any, _: any, slot: number)
			Harness.Relay.setInvisible(slot, true)
		end,
	},

	{
		name = "A despawn",
		kind = "Player",
		stop = function (_: any, harness: any, _: any, slot: number)
			harness:despawn(slot)
		end,
	},

	{
		name = "An NPC past its range",
		kind = "Npc",
		stop = function (_: any, harness: any, _: any, slot: number)
			harness.states[slot].position = PAST
		end,
	},
}

return function (): (boolean, string | nil)
	for _, row: Row in ROWS do
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new()
		local client: any = harness:viewer("Viewer")
		local slot: number = harness:spawn(row.kind, PLACE)

		harness:run()
		if client.drawn[slot] == nil then
			return false, `{row.name}: the body in range was never revealed`
		end

		-- Anti-ESP would hide the pair in the same run, and the hide is still not its own
		harness:hide(client, slot, true)
		row.stop(Harness, harness, client, slot)
		harness:run()

		local hide: any = Harness.find(client.seen.hides, slot)
		if Harness.count(client.seen.hides, slot) ~= 1 then
			return false, `{row.name} gave the viewer no hide`
		elseif hide.culled ~= false then
			return false, `{row.name} read culled {hide.culled}, not false`
		end
	end

	return true, nil
end
