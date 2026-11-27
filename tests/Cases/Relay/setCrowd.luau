--[[
    Relay.setCrowd between runs takes effect on the next, alike in process and
    on 1 and 2 stand-in workers, Relay.crowd gives back what it set, and a cap
    whose floor is above its rate is refused as the server's check refuses it
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MOST_WORKERS: number = 2
local SETTLE: number = 4 -- Runs before the record starts, past the targets' reveals
local BEFORE: number = 4 -- Runs with no cap, then under the cap, then with none again
local CAPPED: number = 8
local AFTER: number = 4
local STRIDE: number = 0.1 -- Studs the targets move a run, back and forth, so each always has a change to send
local MEMBER: vector = vector.create(0, 0, -100) -- Ahead of the viewer, inside the example's first band
local REST: vector = vector.create(0, 0, -120) -- Farther along, so the cap of one holds it out
local CROWD: { size: number, rate: number, floor: number } = { size = 1, rate = 5, floor = 5 }
local REFUSED: string = "server.tiers.crowd.floor expected" -- How a floor above its rate is refused
local PLAIN: boolean = true -- string.find's flag that matches the text as it is, with no pattern

-- The member's and the rest's records each run past the settle: the member every run, the rest every run with no cap
-- and at the cap's 5 Hz under it, its first due on the cap's fourth run
local EXPECTED_MEMBER: string = "1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1"
local EXPECTED_REST: string = "1 1 1 1 0 0 0 1 0 0 0 1 1 1 1 1"

-- What one side's runs gave: the two targets' records each run, the candidates held out, or why it went wrong
type Ran = { member: string, rest: string, held: number }

local function drive(Harness: any, workers: number?): (Ran?, string?)
	local harness: any = Harness.new(nil, nil, workers)
	local Relay: any = Harness.Relay

	-- Facing along -Z, so both targets ahead of it are in its view
	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	local member: number = harness:spawn("Player", MEMBER)
	local rest: number = harness:spawn("Player", REST)

	if Relay.crowd() ~= nil then
		return nil, "Relay.crowd gave a cap the example's tables leave out"
	end

	local members: { string } = {}
	local rests: { string } = {}
	for run: number = 1, SETTLE + BEFORE + CAPPED + AFTER do
		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		harness.states[member].position += vector.create(step, 0, 0)
		harness.states[rest].position += vector.create(step, 0, 0)
		harness:run()

		if run > SETTLE then
			table.insert(members, `{Harness.count(client.seen.records, member)}`)
			table.insert(rests, `{Harness.count(client.seen.records, rest)}`)
		end

		if run == SETTLE + BEFORE then
			Relay.setCrowd(CROWD)

			local set: { size: number, rate: number, floor: number }? = Relay.crowd()
			if set == nil or set.size ~= CROWD.size or set.rate ~= CROWD.rate or set.floor ~= CROWD.floor then
				return nil, "Relay.crowd gave other than the cap just set"
			elseif set == CROWD then
				return nil, "Relay.crowd gave back the table it was set with, not a copy"
			end
		elseif run == SETTLE + BEFORE + CAPPED then
			Relay.setCrowd(nil)
			if Relay.crowd() ~= nil then
				return nil, "Relay.crowd still gave a cap after Relay.setCrowd(nil)"
			end
		end
	end

	-- A floor above its rate, refused naming its path, leaves the relay with no cap as it was
	local refused: boolean, failure: any = pcall(Relay.setCrowd, { size = 1, rate = 5, floor = 6 })
	if refused or string.find(tostring(failure), REFUSED, 1, PLAIN) ~= 1 then
		return nil, `Relay.setCrowd took or refused otherwise a floor above its rate: {failure}`
	elseif Relay.crowd() ~= nil then
		return nil, "A refused Relay.setCrowd left a cap in place"
	end

	local _, _, _, held: number = Relay.counts()

	return { member = table.concat(members, " "), rest = table.concat(rests, " "), held = held }, nil
end

return function (): (boolean, string | nil)
	local serial: Ran?, why: string? = drive(Environment.load(HARNESS), nil)
	if serial == nil then
		return false, `In process: {why}`
	elseif serial.member ~= EXPECTED_MEMBER or serial.rest ~= EXPECTED_REST then
		return false, `In process the member's records ran {serial.member} and the rest's {serial.rest}`
	elseif serial.held ~= CAPPED then
		return false, `In process the cap held {serial.held} candidates out over its {CAPPED} runs, not {CAPPED}`
	end

	for workers: number = 1, MOST_WORKERS do
		local Harness: any = Layouts.harness()
		local onWorkers: Ran?, failure: string? = drive(Harness, workers)
		if onWorkers == nil then
			return false, `On {workers} workers: {failure}`
		elseif onWorkers.member ~= serial.member or onWorkers.rest ~= serial.rest then
			return false,
				`On {workers} workers the records ran {onWorkers.member} and {onWorkers.rest}, not as in process`
		elseif onWorkers.held ~= serial.held then
			return false, `On {workers} workers the cap held {onWorkers.held} out, not {serial.held} as in process`
		end
	end

	return true, nil
end
