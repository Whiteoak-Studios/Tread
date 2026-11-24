--[[
    Relay.setBands between runs takes effect on the next, alike in process and
    on 1 and 2 stand-in workers, Relay.bands gives back what it set, and a band
    whose floor is above its aim is refused as the server's check refuses it
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MOST_WORKERS: number = 2
local SETTLE: number = 4 -- Runs before the record starts, past the target's reveal
local BEFORE: number = 4 -- Runs on the example's bands, then on the one band, then on the example's again
local SLOWED: number = 8
local AFTER: number = 4
local STRIDE: number = 0.1 -- Studs the target moves a run, back and forth, so it always has a change to send
local NEAR: vector = vector.create(0, 0, -100) -- Ahead of the viewer, inside the example's first band
local SLOW: { { aim: number, floor: number } } = { { aim = 5, floor = 5 } } -- One band for every distance
local REFUSED: string = "server.tiers.bands[1].floor expected" -- How a floor above its aim is refused
local KEPT_FLOOR: number = 15 -- The example's first band's floor, which a refused set leaves
local PLAIN: boolean = true -- string.find's flag that matches the text as it is, with no pattern

-- The target's records each run past the settle
local EXPECTED: string = "1 1 1 1 0 0 0 1 0 0 0 1 1 1 1 1"

-- The runs on a harness, in process or on workers: the target's records each run, or why it went wrong
local function drive(Harness: any, workers: number?): (string?, string?)
	local harness: any = Harness.new(nil, nil, workers)
	local Relay: any = Harness.Relay

	-- Facing along -Z, so the target ahead of it is in its view
	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	local target: number = harness:spawn("Player", NEAR)

	local counts: { string } = {}
	local keptBands: { any } = {}
	local keptEdges: { any } = {}
	for run: number = 1, SETTLE + BEFORE + SLOWED + AFTER do
		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		harness.states[target].position += vector.create(step, 0, 0)
		harness:run()

		if run > SETTLE then
			table.insert(counts, `{Harness.count(client.seen.records, target)}`)
		end

		if run == SETTLE + BEFORE then
			keptBands, keptEdges = Relay.bands()
			Relay.setBands(SLOW, {})

			local slowBands: { any }, slowEdges: { any } = Relay.bands()
			if #slowBands ~= 1 or slowBands[1].aim ~= SLOW[1].aim or #slowEdges ~= 0 then
				return nil, "Relay.bands gave other than the one band just set"
			end
		elseif run == SETTLE + BEFORE + SLOWED then
			Relay.setBands(keptBands, keptEdges)
		end
	end

	-- A floor above its aim, refused naming its path, leaves the bands as they were
	local refused: boolean, failure: any = pcall(Relay.setBands, { { aim = 5, floor = 6 } }, {})
	if refused or string.find(tostring(failure), REFUSED, 1, PLAIN) ~= 1 then
		return nil, `Relay.setBands took or refused otherwise a floor above its aim: {failure}`
	end

	local bands: { any } = Relay.bands()
	if #bands ~= #keptBands or bands[1].floor ~= KEPT_FLOOR then
		return nil, `A refused Relay.setBands left {#bands} bands`
	end

	return table.concat(counts, " "), nil
end

return function (): (boolean, string | nil)
	local serial: string?, why: string? = drive(Environment.load(HARNESS), nil)
	if serial == nil then
		return false, `In process: {why}`
	elseif serial ~= EXPECTED then
		return false, `In process the target's records ran {serial}, not {EXPECTED}`
	end

	for workers: number = 1, MOST_WORKERS do
		local Harness: any = Layouts.harness()
		local onWorkers: string?, failure: string? = drive(Harness, workers)
		if onWorkers == nil then
			return false, `On {workers} workers: {failure}`
		elseif onWorkers ~= serial then
			return false, `On {workers} workers the target's records ran {onWorkers}, not {serial} as in process`
		end
	end

	return true, nil
end
