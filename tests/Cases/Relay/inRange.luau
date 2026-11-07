--[[
    Replication case 1, over Volt.mock: a character that appears inside a
    viewer's range is revealed in the first block, with its kind and a
    record at its place, and every move after reaches the viewer
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64 -- A record's X and Z step
local APPEARS: vector = vector.create(100, 0, 40) -- Inside the near tier of a viewer at the origin
local STRIDE: vector = vector.create(0.5, 0, 0) -- Studs it moves a tick
local MOVES: number = 5

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(true)
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", APPEARS)

	harness:run()

	local seen: any = client.seen
	if #seen.reveals ~= 1 or seen.reveals[1].slot ~= slot or seen.reveals[1].kind ~= "Player" then
		return false, `The first block revealed {#seen.reveals} characters, where it reveals the player in slot {slot}`
	end

	local record: any = seen.records[1]
	if #seen.records ~= 1 or record.slot ~= slot or vector.magnitude(record.position - APPEARS) > QUANTUM then
		return false, `The reveal's record put slot {slot} at {record and record.position}, not at {APPEARS}`
	end

	if not Harness.Relay.isSent(client.viewer.key, slot) then
		return false, "The viewer was not counted as sent the character once its reveal was carried"
	end

	for move: number = 1, MOVES do
		local at: vector = APPEARS + STRIDE * move
		harness.states[slot].position = at
		harness:run()

		seen = client.seen
		if #seen.reveals ~= 0 then
			return false, `Tick {move} revealed the character again after the viewer acknowledged its reveal`
		elseif #seen.records ~= 1 or vector.magnitude(seen.records[1].position - at) > QUANTUM then
			return false, `Tick {move} carried {#seen.records} records, where the moving character's goes at {at}`
		end
	end

	return true, nil
end
