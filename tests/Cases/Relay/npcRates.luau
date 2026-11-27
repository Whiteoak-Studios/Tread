--[[
    An NPC on the move is sent every relay tick inside the near range, at
    the far rate past it, and not at all past its range, where it is hidden
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TICKS: number = 20 -- A second at the example's 20 Hz relay
local EVERY: number = 20
local FAR_RATE: number = 2 -- The example's npcs.farRate
local SLACK: number = 1
local STRIDE: number = 0.5

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local npc: number = harness:spawn("Npc", vector.create(150, 0, 0)) -- Inside the example's npcs.near of 197

	local function second(): number
		local count: number = 0

		for _ = 1, TICKS do
			harness.states[npc].position += vector.create(0, 0, STRIDE)
			harness:run()
			count += Harness.count(client.seen.records, npc)
		end

		return count
	end

	harness:run()
	if Harness.find(client.seen.reveals, npc) == nil or Harness.find(client.seen.reveals, npc).kind ~= "Npc" then
		return false, "The NPC in range was not revealed as an NPC"
	end

	local count: number = second()
	if count ~= EVERY then
		return false, `Inside the near range the NPC got {count} records a second, not {EVERY}`
	end

	harness.states[npc].position = vector.create(400, 0, 0)
	count = second()
	if math.abs(count - FAR_RATE) > SLACK then
		return false, `Past the near range the NPC got {count} records a second, not {FAR_RATE}`
	end

	harness.states[npc].position = vector.create(900, 0, 0) -- Past the example's npcs.range of 800
	harness:run()
	if Harness.count(client.seen.hides, npc) ~= 1 then
		return false, "The NPC past its range was not hidden"
	end

	count = second()
	if count ~= 0 then
		return false, `Past its range the NPC still got {count} records`
	end

	return true, nil
end
