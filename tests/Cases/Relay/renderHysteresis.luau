--[[
    A viewer's own distance keeps the server's hysteresis in proportion: at
    400 studs a player at 390 is not entered until it comes inside 380, 400
    times the example's 950 over 1,000, and once entered stays until past 400
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local DISTANCE: number = 400
local RUNS: number = 2 -- Relay ticks at each place, each enough for a reveal or a hide to arrive

-- Each place along X in turn, and whether the viewer is sent the player once it stands there
local PLACES: { { number | boolean } } = {
	{ 390, false }, -- Inside the leave, outside the entry
	{ 381, false },
	{ 379, true }, -- Inside the entry
	{ 390, true }, -- Entered, so it stays
	{ 399, true },
	{ 401, false }, -- Past the leave
	{ 390, false }, -- Back outside the entry, so it is not entered again
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(PLACES[1][1] :: number, 0, 0))

	Harness.Relay.setDistance(client.viewer.key, DISTANCE)

	for _, place: { number | boolean } in PLACES do
		local x: number = place[1] :: number
		local sent: boolean = place[2] :: boolean

		harness.states[slot].position = vector.create(x, 0, 0)
		harness:runs(RUNS)

		if (client.drawn[slot] ~= nil) ~= sent then
			return false, `At {x} studs the player was {sent and "not " or ""}sent to the viewer at {DISTANCE}`
		end
	end

	return true, nil
end
