--[[
    With every other relay tick skipped, as a catch-up runs them, timings
    in seconds keep their seconds: a still character's record still goes
    once a second, and a far tier's records at its rate
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local FAR_RATE: number = 5 -- Hz, the far tier's aim and floor here, under half the example's 20 Hz relay
local STILL_TICKS: number = 20 -- A second at the example's 20 Hz relay
local SECONDS: number = 2 -- The span the far tier's records are counted over
local SKIP: number = 2 -- Relay ticks each run here moves on by, every other one skipped
local SETTLE: number = 8 -- Runs before the counts start, past the still character's reveal and rest repeats
local STRIDE: number = 0.5 -- Studs the far character moves each run, so it always has a change to send

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.tiers.farAim = FAR_RATE
		server.tiers.farFloor = FAR_RATE
	end)

	local client: any = harness:viewer("Viewer")
	local still: number = harness:spawn("Player", vector.create(100, 0, 0))
	local far: number = harness:spawn("Player", vector.create(500, 0, 0))

	-- One run SKIP relay ticks after the last, with the relay ticks before it skipped
	local function skipped()
		harness.states[far].position += vector.create(0, 0, STRIDE)
		harness.tick += SKIP - 1
		harness:run()
	end

	for _ = 1, SETTLE do
		skipped()
	end

	-- The relay ticks between the still character's records, and the far character's records, over SECONDS
	local stillTicks: { number } = {}
	local farCount: number = 0
	local farTicks: number = 0

	while farTicks < SECONDS * STILL_TICKS do
		skipped()
		farTicks += SKIP
		farCount += Harness.count(client.seen.records, far)

		if Harness.count(client.seen.records, still) ~= 0 then
			table.insert(stillTicks, harness.tick)
		end
	end

	if #stillTicks < 2 or stillTicks[2] - stillTicks[1] ~= STILL_TICKS then
		return false,
			`The still character's records went at relay ticks {table.concat(stillTicks, ", ")}, not a second apart`
	elseif farCount ~= FAR_RATE * SECONDS then
		return false, `The far character was sent {farCount} records over {SECONDS} s, not {FAR_RATE * SECONDS}`
	end

	return true, nil
end
