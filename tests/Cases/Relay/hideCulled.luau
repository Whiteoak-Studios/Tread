--[[
    A hide anti-ESP makes of a character a viewer is sent reads culled true
    in that viewer's block
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local PLACE: vector = vector.create(100, 0, 0)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", PLACE)

	harness:run()
	if client.drawn[slot] == nil then
		return false, "The character in range was never revealed"
	end

	harness:hide(client, slot, true)
	harness:run()

	local hide: any = Harness.find(client.seen.hides, slot)
	if Harness.count(client.seen.hides, slot) ~= 1 then
		return false, "Anti-ESP hiding the character gave the viewer no hide"
	elseif hide.culled ~= true then
		return false, `The hide anti-ESP made read culled {hide.culled}, not true`
	end

	return true, nil
end
