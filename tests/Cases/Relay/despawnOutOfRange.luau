--[[
    Replication case 6, over Volt.mock: a character that despawns while the
    viewer is out of its range costs the viewer nothing then or when it
    comes back, while a character spawned there in its place is revealed
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local PLACE: vector = vector.create(100, 0, 0)
local AWAY: vector = vector.create(2000, 0, 0)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(true)
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", PLACE)

	harness:run()
	if client.drawn[slot] == nil then
		return false, "The character in range was never revealed"
	end

	client.viewer.position = AWAY
	harness:run()
	if Harness.count(client.seen.hides, slot) ~= 1 then
		return false, "Leaving the character's range gave no hide"
	end

	harness:run()
	harness:despawn(slot)
	harness:run()

	local seen: any = client.seen
	if #seen.sizes ~= 0 then
		return false, `The despawn while out of range sent the viewer {#seen.sizes} blocks`
	end

	local after: number = harness:spawn("Player", PLACE)
	client.viewer.position = vector.zero
	harness:run()

	seen = client.seen
	local named: number = Harness.count(seen.reveals, slot) + Harness.count(seen.hides, slot)
	if named + Harness.count(seen.records, slot) + Harness.count(seen.looks, slot) ~= 0 then
		return false, `Coming back named the despawned character's slot {slot}`
	elseif Harness.count(seen.reveals, after) ~= 1 then
		return false, "The character spawned in its place was not revealed"
	elseif Harness.Relay.isSent(client.viewer.key, slot) then
		return false, "The viewer was counted as sent the despawned slot"
	end

	return true, nil
end
