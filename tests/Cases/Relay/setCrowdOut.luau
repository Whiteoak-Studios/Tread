--[[
    Relay.setCrowd called while a round is out on 2 stand-in workers leaves
    that round's blocks as dispatched and takes effect at the next run, as
    the same call made between runs does in process
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local SETTLE: number = 4 -- Runs before the record starts, past the targets' reveals
local BEFORE: number = 4 -- Runs with no cap, the cap set during the last of them, then runs under it
local CAPPED: number = 8
local STRIDE: number = 0.1 -- Studs the targets move a run, back and forth, so each always has a change to send
local MEMBER: vector = vector.create(0, 0, -100) -- Ahead of the viewer, inside the example's first band
local REST: vector = vector.create(0, 0, -120) -- Farther along, so the cap of one holds it out
local CROWD: { size: number, rate: number, floor: number } = { size = 1, rate = 5, floor = 5 }

-- The rest's records each run past the settle: every run up to and with the one the cap was set in, then at the cap's
-- 5 Hz, its first due on the cap's fourth run
local EXPECTED: string = "1 1 1 1 0 0 0 1 0 0 0 1"

--[[
    The runs on a harness, the cap set while the run SETTLE + BEFORE is
    out on its workers when given a pool, else between that run and the
    next: the rest's records each run, or why it went wrong
--]]

local function drive(Harness: any, workers: number?): (string?, string?)
	local harness: any = Harness.new(nil, nil, workers)
	local Relay: any = Harness.Relay
	local pool: any = harness.pool
	local setAt: number = SETTLE + BEFORE
	local run: number = 0
	local why: string? = nil

	-- The pool runs its rounds only when delivered, so a call made just before is one made while the round is out
	if pool then
		local deliver: any = pool.deliver
		pool.deliver = function (self: any)
			if run == setAt then
				if Relay.finish() then
					why = "The round was in before its pool delivered it"
				end

				Relay.setCrowd(CROWD)
			end

			deliver(self)
		end
	end

	-- Facing along -Z, so both targets ahead of it are in its view
	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	local member: number = harness:spawn("Player", MEMBER)
	local rest: number = harness:spawn("Player", REST)

	local rests: { string } = {}
	for at: number = 1, SETTLE + BEFORE + CAPPED do
		run = at

		local step: number = at % 2 == 0 and -STRIDE or STRIDE
		harness.states[member].position += vector.create(step, 0, 0)
		harness.states[rest].position += vector.create(step, 0, 0)
		harness:run()

		if at > SETTLE then
			table.insert(rests, `{Harness.count(client.seen.records, rest)}`)
		end

		if at == setAt and not pool then
			Relay.setCrowd(CROWD)
		end
	end

	if why then
		return nil, why
	elseif Relay.crowd() == nil then
		return nil, "Relay.crowd gave no cap after the run it was set in"
	end

	return table.concat(rests, " "), nil
end

return function (): (boolean, string | nil)
	local serial: string?, why: string? = drive(Environment.load(HARNESS), nil)
	if serial == nil then
		return false, `In process: {why}`
	elseif serial ~= EXPECTED then
		return false, `In process the rest's records ran {serial}, not {EXPECTED}`
	end

	local onWorkers: string?, failure: string? = drive(Layouts.harness(), WORKERS)
	if onWorkers == nil then
		return false, `On {WORKERS} workers: {failure}`
	elseif onWorkers ~= serial then
		return false, `On {WORKERS} workers the rest's records ran {onWorkers}, not {serial} as in process`
	end

	return true, nil
end
