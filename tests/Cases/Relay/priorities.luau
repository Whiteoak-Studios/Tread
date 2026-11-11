--[[
    When the soft budget leaves room for one record a tick past the floors,
    the queue sends the higher weight first: a shooter whose bullet passed
    near the viewer before another, and a character in the viewer's view
    cone before one behind it
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TICKS: number = 20
local SOFT: number = 64 * 1000
local ONE_RECORD: number = 28 -- A block's header and framing and one record
local FLOOR: number = 1 -- A far floor low enough that the queue, not the floor, decides who goes

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.tiers.farFloor = FLOOR
		server.shotNear.rate = FLOOR
	end)

	local client: any = harness:viewer("Viewer")
	local own: number = harness:spawn("Player", vector.zero)
	client.viewer.slot = own

	-- Each character moves every tick, so each is due on its tier ticks
	local function second(slots: { number }): { [number]: number }
		local counts: { [number]: number } = {}

		for _ = 1, TICKS do
			for _, slot: number in slots do
				harness.states[slot].position += vector.create(0.1, 0, 0)
			end

			harness:run()

			for _, slot: number in slots do
				counts[slot] = (counts[slot] or 0) + Harness.count(client.seen.records, slot)
			end
		end

		return counts
	end

	-- Both to the viewer's side, outside its view cone, as it faces along -Z
	local shooter: number = harness:spawn("Player", vector.create(500, 0, 0))
	local other: number = harness:spawn("Player", vector.create(-500, 0, 0))
	harness:run()

	Harness.Relay.shotNear(client.viewer.key, shooter)
	harness.traffic = SOFT - ONE_RECORD

	local counts: { [number]: number } = second({ shooter, other })
	if counts[shooter] <= counts[other] then
		return false, `The shooter got {counts[shooter]} records to the {counts[other]} of the other`
	end

	harness:despawn(shooter)
	harness:despawn(other)

	local ahead: number = harness:spawn("Player", vector.create(0, 0, -500))
	local behind: number = harness:spawn("Player", vector.create(0, 0, 500))
	harness.traffic = 0
	harness:run()

	harness.traffic = SOFT - ONE_RECORD
	counts = second({ ahead, behind })
	if counts[ahead] <= counts[behind] then
		return false, `In the view cone a character got {counts[ahead]} records to the {counts[behind]} of one behind`
	end

	return true, nil
end
